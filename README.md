# MacOS sandboxing experiments

To run a Julia test, use `make sandbox-FOO` where `FOO` is the name of a valid argument to `Base.runtests()`.  Good examples are `all`, `cmdlineargs`, `InteractiveUtils`, etc...

To compare against unsandboxed execution, run `test-FOO`.

# Known issues:

With a few patches merged, this is now working as expected!

# Workarounds in place:

The following tests have strange behavior that we should probably fix:

- `cmdlineargs` test requires writing to `share/julia/test/testhelpers`
- `get_anon_hdl()` ignores `$TMPDIR`, instead [always writing to `/tmp`](https://github.com/JuliaLang/julia/blob/v1.5.3/src/cgmemmgr.cpp#L197-L198)
- `Profile` looks up lineinfo data which uses paths embedded during build, so it requires read access to paths that most likely do not exist (e.g. `/Users/julia/buildbot/worker/package_macos64/build`).

# Reading list:

- https://blog.squarelemon.com/2015/02/os-x-sandbox-quickstart/

- https://jmmv.dev/2019/11/macos-sandbox-exec.html

- https://reverse.put.as/wp-content/uploads/2011/09/Apple-Sandbox-Guide-v1.0.pdf