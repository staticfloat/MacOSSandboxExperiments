using Pkg

abstract type SandboxResource; end
SandboxResource(res::SandboxResource) = res

struct SandboxPath <: SandboxResource
    path::String
end
SandboxResource(path::AbstractString) = SandboxPath(String(path))
Base.print(io::IO, res::SandboxPath) = print(io, "(path \"$(res.path)\")")

struct SandboxSubpath <: SandboxResource
    path::String
end
SandboxResource(path::SubstitutionString) = SandboxSubpath(path.string)
Base.print(io::IO, res::SandboxSubpath) = print(io, "(subpath \"$(res.path)\")")

struct SandboxRegex <: SandboxResource
    path::String
end
SandboxResource(path::Regex) = SandboxRegex(path.pattern)
Base.print(io::IO, res::SandboxRegex) = print(io, "(regex #\"$(res.path)\")")

abstract type SandboxRule; end

struct SandboxGlobalRule <: SandboxRule
    name::String
end
SandboxRule(name::AbstractString) = SandboxGlobalRule(String(name))
Base.print(io::IO, rule::SandboxGlobalRule) = print(io, "(allow $(rule.name))")

struct SandboxScopedRule <: SandboxRule
    name::String
    resources::Vector{<:SandboxResource}
end
SandboxRule(name::AbstractString, scopes::Vector{<:SandboxResource}) = SandboxScopedRule(String(name), scopes)
SandboxRule(name::AbstractString, scopes::Vector) = SandboxRule(String(name), SandboxResource.(scopes))
function Base.print(io::IO, rule::SandboxScopedRule)
    println(io, "(allow $(rule.name)")
    for resource in rule.resources
        println(io, "    $(resource)")
    end
    println(io, ")")
end



struct MacOSSandboxConfig
    # Usually something like `"bsd.sb"`
    parent_config::Union{Nothing,String}

    # List of actions that should be allowed
    rules::Vector{<:SandboxRule}

    # Whether we should try getting debug output (doesn't work on modern macOS versions)
    debug::Bool

    function MacOSSandboxConfig(;rules::Vector{<:SandboxRule} = SandboxRule[],
                                 parent_config::Union{Nothing,String} = "bsd.sb",
                                 debug::Bool = false,
                                )
        return new(parent_config, rules, debug)
    end
end

function generate_sandbox_config(io::IO, config::MacOSSandboxConfig)
    # First, print out the header:
    print(io, """
    (version 1)
    (deny default)
    """)

    if config.debug
        println(io, "(debug deny)")
    end

    # Inherit from something like `bsd.sb`
    if config.parent_config !== nothing
        println(io, "(import \"$(config.parent_config)\")")
    end

    # Add all rules that are not path-based
    for rule in config.rules
        println(io, rule)
    end
end

function with_sandbox(f::Function, sandbox_generator::Function, args...; kwargs...)
    mktempdir() do dir
        sb_path = joinpath(dir, "macos_sandbox.sb")
        open(sb_path, write=true) do io
            sandbox_generator(io, args...; kwargs...)
        end
        f(sb_path)
    end
end

function dirname_chain(path::AbstractString)
    dirnames = AbstractString[]
    while dirname(path) != path
        path = dirname(path)
        push!(dirnames, path)
    end
    return dirnames
end

function generate_julia_test_sandbox(io::IO, julia_exe_path::String;
                                     extra_rw_paths::Vector{<:AbstractString} = String[])
    julia_dir = dirname(dirname(julia_exe_path))

    # Add Homebrew (the default path on each architecture)
    homebrew_paths = []
    if Sys.ARCH == :aarch64
        if isdir("/opt/homebrew/Cellar")
            push!(homebrew_paths, r"/opt/homebrew/Cellar/.*/bin/.*")
        end
    elseif Sys.ARCH == :x86_64
        if isdir("/usr/local/Cellar")
            push!(homebrew_paths, r"/usr/local/Cellar/.*/bin/.*")
        end
    end

    # We'll generate here a SandboxConfig that 
    config = MacOSSandboxConfig(;
        rules = vcat(
            # First, global rules that are not scoped in any way
            SandboxRule.([
                # These are foundational capabilities, and should potentially
                # be enabled for _all_ sandboxed processes?
                "process-fork", "process-info*", "process-codesigning-status*",
                "signal", "mach-lookup", "sysctl-read",

                # Running Julia's test suite requires IPC/shared memory mechanisms as well
                "ipc-posix-sem", "ipc-sysv-shm", "ipc-posix-shm",

                # We require network access
                "network-bind", "network-outbound", "network-inbound", "system-socket",
            ]),

            # Allow `job-creation`, but only inside of the Julia directory
            # TODO: is this necessary?
            #SandboxRule("job-creation", [
            #    SandboxSubpath(julia_dir),
            #]),

            SandboxRule("process-exec*", [
                # Allow process execution within the Julia directory (so we can spawn
                # other Julia instances, for example)
                SandboxSubpath(julia_dir),

                # Allow ourselves to launch things like `curl`, `bash`, etc...
                SandboxSubpath("/usr/local/bin"),
                SandboxSubpath("/usr/local/sbin"),
                SandboxSubpath("/usr/bin"),
                SandboxSubpath("/usr/sbin"),
                SandboxSubpath("/bin"),
                SandboxSubpath("/sbin"),

                # Allow launching of binaries provided by Homebrew
                homebrew_paths...,
            ]),

            # Provide read-only access to a bevvy of files
            SandboxRule("file-read*", [
                # Allow reading the current directory    
                pwd(),
            
                # Allow reading of the top-level Julia directory
                SandboxSubpath(julia_dir),

                # Allow reading of every directory in the parental chain of Julia
                # Note that these are not recursive allows, they are simply that
                # exact file path.
                dirname_chain(julia_dir)...,

                # There are a number of preferences that get read by Cocoa stuff.
                # Perhaps we should single them out as literals?
                SandboxSubpath(joinpath(Base.homedir(), "Library", "Preferences")),

                # The lineinfo paths embedded within the system image are going to
                # try and load these paths; EPERM is fatal, while ENOENT is not,
                # so let the process get an ENOENT during the the `Profile` tests.
                # NOTE: we'll need to update this once this path changes....
                # Perhaps we should do this with a weird regex so we're not so
                # sensitive to buildbot pathing?
                SandboxSubpath("/Users/julia/buildbot/worker/package_macos64/build"),

                # We invoke `curl` which wants to load its certificate stores
                SandboxSubpath("/private/etc/ssl"),

                # We generally provide read-only access to all system directories
                SandboxSubpath("/usr"),
                #SandboxSubpath("/System"),
                SandboxSubpath("/Library"),
                SandboxSubpath("/dev"),
                SandboxSubpath("/etc"),
                SandboxSubpath("/private/var/"),
            ]),

            # Provide read-write access to a more restricted set of files
            SandboxRule("file*", [
                # Allow control over TTY devices
                r"/dev/tty.*",
                "/dev/ptmx",

                # We need to be able to read/write our depot path
                SandboxSubpath(Pkg.depots1()),

                # Also our temp directory
                SandboxSubpath(tempdir()),

                # Keychain access requires R/W access to a path in /private/var/folders whose path name is difficult to know beforehand
                SandboxSubpath("/private/var/folders"),

                # Allow read/write to extra paths according to the whim of the user
                SandboxSubpath.(extra_rw_paths)...,
            ]),
        )
    )

    # Write the config out to the provided IO object
    generate_sandbox_config(io, config)
    return nothing
end

function run_sandboxed_test(;
                            julia_exe_path::AbstractString = first(Base.julia_cmd().exec),
                            test_name::String = "all",
                            sandboxed::Bool = false,
                            ncores::Int = ceil(Int, Sys.CPU_THREADS/2),
                            revise::Bool = false,)
    test_cmd = `$(julia_exe_path) --depwarn=error -e "Base.runtests([\"$(test_name)\"]; ncores=$(ncores), revise=$(revise))"`
    if sandboxed
        with_sandbox(generate_julia_test_sandbox, julia_exe_path) do sb_path
            run(`cat $(sb_path)`)
            println()
            println()
            run(`sandbox-exec -f $(sb_path) $(test_cmd)`)
        end
    else
        run(test_cmd)
    end
end

function run_sandboxed_julia(;julia_exe_path::AbstractString = first(Base.julia_cmd().exec))
    with_sandbox(generate_julia_test_sandbox, julia_exe_path; extra_rw_paths=[pwd()]) do sb_path
        run(`cat $(sb_path)`)
        println()
        println()
        run(`sandbox-exec -f $(sb_path) $(julia_exe_path) --color=yes`)
    end
end

