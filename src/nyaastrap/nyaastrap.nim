include ../purr/common

proc initDirectories(buildDirectory: string, arch: string) =
    # Initializes directories.

    #if dirExists(buildDirectory):
    #    info_msg "rootfs directory exist, removing"
    #    removeDir(buildDirectory)

    debug "Making initial rootfs directories"

    createDir(buildDirectory)
    createDir(buildDirectory&"/etc")
    createDir(buildDirectory&"/var")
    createDir(buildDirectory&"/usr")
    createDir(buildDirectory&"/usr/bin")
    createDir(buildDirectory&"/usr/lib")
    createDir(buildDirectory&"/home")
    createDir(buildDirectory&"/boot")
    createDir(buildDirectory&"/media")
    createDir(buildDirectory&"/root")
    createDir(buildDirectory&"/srv")
    createDir(buildDirectory&"/dev")
    createDir(buildDirectory&"/opt")
    createDir(buildDirectory&"/proc")
    createDir(buildDirectory&"/sys")
    createDir(buildDirectory&"/tmp")
    createDir(buildDirectory&"/etc/nyaa.installed")
    createDir(buildDirectory&"/run")

    if arch == "amd64":
        createSymlink("usr/lib", buildDirectory&"/lib64")
        createSymlink("lib", buildDirectory&"/usr/lib64")

    createSymlink("usr/bin", buildDirectory&"/sbin")
    createSymlink("bin", buildDirectory&"/usr/sbin")
    createSymlink("usr/bin", buildDirectory&"/bin")
    createSymlink("usr/lib", buildDirectory&"/lib")

    info_msg "Root directory structure created."

proc nyaastrap_install(package: string, installWithBinaries: bool,
        buildDir: string, useCacheIfPossible = true) =
    # Install a package.
    info_msg "Installing package '"&package&"'"
    if installWithBinaries == true:
        debug "Installing package as a binary"
        discard install(toSeq([package]), buildDir, true)
    else:
        debug "Building package from source"
        # Turning offline to false for now because current offline mode implementation doesnt work on Docker containers.
        discard build(yes = true, root = buildDir, packages = toSeq([
                package]), offline = false,
                useCacheIfAvailable = useCacheIfPossible)

    ok("Package "&package&" installed successfully")

proc set_default_cc(buildDir: string, cc: string) =
    ## Sets the default compiler.
    let files = ["/bin/cc", "/bin/c99", "/bin/g++", "/bin/c++"]
    var file: string
    for i in files:
        file = buildDir&i
        if not fileExists(file):
            createSymlink(cc, file)

proc nyaastrap(buildType = "builder", arch = "amd64",
        useCacheIfPossible = true) =
    ## Kreato Linux's build tool.

    if not isAdmin():
        error "You have to be root to continue."

    var conf: Config

    if fileExists(getAppDir()&"/arch/"&arch&"/configs/"&buildType&".conf"):
        conf = loadConfig(getAppDir()&"/arch/"&arch&"/configs/"&buildType&".conf")
    else:
        error("Config "&buildType&" does not exist!")

    info_msg "nyaastrap v3.0.0"

    discard update()

    debug "Architecture is set as "&arch
    debug "Build type is "&buildType

    let buildDir = conf.getSectionValue("General", "BuildDirectory")

    initDirectories(buildDir, arch)

    if conf.getSectionValue("General", "useOverlay") != "false" and dirExists(
            getAppDir()&"/overlay"):
        info_msg "Overlay found, installing contents"

        setCurrentDir(getAppDir()&"/overlay")

        for kind, path in walkDir("."):
            case kind:
                of pcFile:
                    debug "Adding the file '"&lastPathPart(
                            path)&"' to '"&buildDir&"/"&lastPathPart(path)&"'"
                    copyFile(path, buildDir&"/"&lastPathPart(path))
                of pcDir:
                    debug "Adding the directory '"&lastPathPart(
                            path)&"' to '"&buildDir&"/"&lastPathPart(path)&"'"
                    copyDir(path, buildDir&"/"&lastPathPart(path))
                of pcLinkToFile:
                    debug "Adding the symlinked file '"&lastPathPart(
                            path)&"' to '"&buildDir&"/"&lastPathPart(
                            path)&"' (will not follow symlink)"
                    copyFile(path, buildDir&"/"&lastPathPart(path), options = {})
                of pcLinkToDir:
                    debug "Adding the symlinked directory '"&lastPathPart(
                            path)&"' to '"&buildDir&"/"&lastPathPart(path)&"'"
                    copyDir(path, buildDir&"/"&lastPathPart(path))

        var installWithBinaries: bool

        if conf.getSectionValue("General", "BuildPackages").normalize() ==
                "true" or conf.getSectionValue("General", "BuildPackages") == "yes":
            installWithBinaries = false
        else:
            installWithBinaries = true

        # Installation of TLS library
        case conf.getSectionValue("Core", "TlsLibrary").normalize():
            of "openssl":
                info_msg "Installing OpenSSL as TLS Library"
                nyaastrap_install("openssl", installWithBinaries, buildDir, useCacheIfPossible)
            of "libressl":
                info_msg "Installing LibreSSL as TLS library"
                nyaastrap_install("libressl", installWithBinaries, buildDir, useCacheIfPossible)
            else:
                error conf.getSectionValue("Core",
                        "TlsLibrary")&" is not available as a TLS library option."

        # Installation of a Compiler
        case conf.getSectionValue("Core", "Compiler").normalize():
            of "gcc":
                info_msg "Installing GCC as Compiler"
                nyaastrap_install("gcc", installWithBinaries, buildDir, useCacheIfPossible)
                set_default_cc(buildDir, "gcc")
            of "clang":
                info_msg "Installing clang as Compiler"
                nyaastrap_install("llvm", installWithBinaries, buildDir, useCacheIfPossible)
                set_default_cc(buildDir, "clang")
            of "no":
                warn "Skipping compiler installation"
            else:
                error conf.getSectionValue("Core",
                        "Compiler")&" is not available as a Compiler option."

        # Installation of Libc
        case conf.getSectionValue("Core", "Libc").normalize():
            of "glibc":
                info_msg "Installing glibc as libc"
                nyaastrap_install("glibc", installWithBinaries, buildDir, useCacheIfPossible)
            of "musl":
                info_msg "Installing musl as libc"
                nyaastrap_install("musl", installWithBinaries, buildDir, useCacheIfPossible)
            else:
                error conf.getSectionValue("Core",
                        "Libc")&" is not available as a Libc option."

        # Installation of Core utilities
        case conf.getSectionValue("Core", "Coreutils").normalize():
            of "busybox":
                info_msg "Installing BusyBox as Coreutils"
                nyaastrap_install("busybox", installWithBinaries, buildDir, useCacheIfPossible)

                if execCmdEx("chroot "&buildDir&" /bin/busybox --install").exitcode != 0:
                    error "Installing busybox failed"

            of "gnu":
                info_msg "Installing GNU Coreutils as Coreutils"
                nyaastrap_install("gnu-coreutils", installWithBinaries,
                        buildDir, useCacheIfPossible)
            else:
                error conf.getSectionValue("Core",
                        "Coreutils")&" is not available as a Coreutils option."

        # Install nyaa, p11-kit and make-ca here
        nyaastrap_install("nyaa", installWithBinaries, buildDir, useCacheIfPossible)
        nyaastrap_install("p11-kit", installWithBinaries, buildDir, useCacheIfPossible)
        nyaastrap_install("make-ca", installWithBinaries, buildDir, useCacheIfPossible)


        # Generate certdata here
        info_msg "Generating CA certificates"

        setCurrentDir(buildDir)

        waitFor download("https://hg.mozilla.org/releases/mozilla-release/raw-file/default/security/nss/lib/ckfw/builtins/certdata.txt",
                "certdata.txt")

        let caCertCmd = execCmdEx("chroot "&buildDir&" /bin/sh -c '. /etc/profile && cd / && /usr/sbin/make-ca -C certdata.txt'")

        if caCertCmd.exitcode != 0:
            debug "CA certification generation output: "&caCertCmd.output
            error "Generating CA certificates failed"
        else:
            ok "Generated CA certificates"

        removeFile(buildDir&"/certdata.txt")

        if conf.getSectionValue("Extras", "ExtraPackages") != "":
            info_msg "Installing extra packages"
            for i in conf.getSectionValue("Extras", "ExtraPackages").split(" "):
                nyaastrap_install(i, installWithBinaries, buildDir, useCacheIfPossible)


dispatch(nyaastrap)
