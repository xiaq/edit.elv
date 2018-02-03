BUILD_FLAGS = '''
-a
        force rebuilding of packages that are already up-to-date.
-n
        print the commands but do not run them.
-p n
        the number of programs, such as build commands or
        test binaries, that can be run in parallel.
        The default is the number of CPUs available.
-race
        enable data race detection.
        Supported only on linux/amd64, freebsd/amd64, darwin/amd64 and windows/amd64.
-msan
        enable interoperation with memory sanitizer.
        Supported only on linux/amd64,
        and only with Clang/LLVM as the host C compiler.
-v
        print the names of packages as they are compiled.
-work
        print the name of the temporary work directory and
        do not delete it when exiting.
-x
        print the commands.

-asmflags 'flag list'
        arguments to pass on each go tool asm invocation.
-buildmode mode
        build mode to use. See 'go help buildmode' for more.
-compiler name
        name of compiler to use, as in runtime.Compiler (gccgo or gc).
-gccgoflags 'arg list'
        arguments to pass on each gccgo compiler/linker invocation.
-gcflags 'arg list'
        arguments to pass on each go tool compile invocation.
-installsuffix suffix
        a suffix to use in the name of the package installation directory,
        in order to keep output separate from default builds.
        If using the -race flag, the install suffix is automatically set to race
        or, if set explicitly, has _race appended to it. Likewise for the -msan
        flag. Using a -buildmode option that requires non-default compile flags
        has a similar effect.
-ldflags 'flag list'
        arguments to pass on each go tool link invocation.
-linkshared
        link against shared libraries previously created with
        -buildmode=shared.
-pkgdir dir
        install and load all packages from dir instead of the usual locations.
        For example, when building with a non-standard configuration,
        use -pkgdir to keep generated packages in a separate location.
-tags 'tag list'
        a space-separated list of build tags to consider satisfied during the
        build. For more information about build tags, see the descliription of
        build constraints in the documentation for the go/build package.
-toolexec 'cmd args'
        a program to use to invoke toolchain programs like vet and asm.
        For example, instead of running asm, the go command will run
        'cmd args /path/to/asm <arguments for asm>'.
'''

flag = ''
descli = []

def put():
    global flag, descli
    if flag != '':
        desc = ' '.join(descli).split('.')[0]
        print('cand %s "%s"' % (flag, desc.replace('"', '\\"')))
    flag = ''
    descli = []

for line in BUILD_FLAGS.splitlines():
    if not line:
        continue
    if line.startswith('-'):
        put()
        flag = line.split()[0]
    else:
        descli.append(line.strip())
put()
