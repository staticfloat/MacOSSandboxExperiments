# MacOS sandboxing experiments

To run a Julia test, use `make sandbox-FOO` where `FOO` is the name of a valid argument to `Base.runtests()`.  Good examples are `all`, `cmdlineargs`, `InteractiveUtils`, etc...

To compare against unsandboxed execution, run `test-FOO`.

# Known issues:

The following tests fail on both `test-FOO` and `sandbox-FOO`:

- `cmdlineargs`: Unknown, arguments seem to be getting lost, probably because `startup-file` is interacting badly with some environment variables.  Fails from direct execution as well.
- `REPL`: Unknown, fails from direct execution as well.

The following tests fail only on `sandobx-FOO`:

- `InteractiveUtils`: ignores `HOME`/`JULIA_DEPOT_PATH`, tries to access `~/.julia`.
- `SuiteSparse`: ignores `HOME`/`JULIA_DEPOT_PATH`, tries to access `~/.julia`.

# Workarounds in place:

The following tests have strange behavior that we should probably fix:

- `loading` test requires writing to `share/julia/test/depot`
- `cmdlineargs` test requires writing to `share/julia/test/testhelpers`
- `get_anon_hdl()` ignores `$TMPDIR`, instead [always writing to `/tmp`](https://github.com/JuliaLang/julia/blob/v1.5.3/src/cgmemmgr.cpp#L197-L198)

# Reading list:

- https://blog.squarelemon.com/2015/02/os-x-sandbox-quickstart/

- https://jmmv.dev/2019/11/macos-sandbox-exec.html

- https://reverse.put.as/wp-content/uploads/2011/09/Apple-Sandbox-Guide-v1.0.pdf