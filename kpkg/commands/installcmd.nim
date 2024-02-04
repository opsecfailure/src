import os
import posix
import osproc
import strutils
import sequtils
import parsecfg
import ../modules/config
import ../modules/logger
import ../modules/lockfile
import ../modules/checksums
import ../modules/runparser
import ../modules/processes
import ../modules/downloader
import ../modules/dephandler
import ../modules/libarchive
import ../modules/commonTasks
import ../modules/removeInternal

setControlCHook(ctrlc)

proc copyFileWithPermissionsAndOwnership(source, dest: string, options = {cfSymlinkFollow}) =
    ## Copies a file with both permissions and ownership.
    var statVar: Stat
    assert stat(source, statVar) == 0
    copyFileWithPermissions(source, dest)
    debug "copyFileWithPermissions successful, setting chown"
    assert posix.chown(dest, statVar.st_uid, statVar.st_gid) == 0

proc createDirWithPermissionsAndOwnership(source, dest: string, followSymlinks = true) =
    var statVar: Stat
    assert stat(source, statVar) == 0
    createDir(dest)
    debug "createDir successful, setting chown and chmod"
    assert posix.chown(dest, statVar.st_uid, statVar.st_gid) == 0
    debug "chown successful, setting permissions"
    setFilePermissions(dest, getFilePermissions(source), followSymlinks)


proc installPkg*(repo: string, package: string, root: string, runf = runFile(
        isParsed: false), manualInstallList: seq[string], isUpgrade = false, arch = hostCPU, ignorePostInstall = false) =
    ## Installs a package.

    var pkg: runFile
    
    try:
        if runf.isParsed:
            pkg = runf
        else:
            pkg = parseRunfile(repo&"/"&package)
    except CatchableError:
        err("Unknown error while trying to parse package on repository, possibly broken repo?")

    debug "installPkg ran, repo: '"&repo&"', package: '"&package&"', root: '"&root&"', manualInstallList: '"&manualInstallList.join(" ")&"'"

    if isUpgrade:
        let existsPkgPreUpgrade = execCmdEx(". "&repo&"/"&package&"/run"&" && command -v preupgrade_"&replace(package, '-', '_')).exitCode
        let existsPreUpgrade = execCmdEx(". "&repo&"/"&package&"/run"&" && command -v preupgrade").exitCode

        if existsPkgPreUpgrade == 0:
            if execCmdKpkg(". "&repo&"/"&package&"/run"&" && preupgrade_"&replace(
                    package, '-', '_')) != 0:
                err("preupgrade failed")
            
        if existsPreUpgrade == 0:
            if execCmdKpkg(". "&repo&"/"&package&"/run"&" && preupgrade") != 0:
                err("preupgrade failed")
    
    let isGroup = pkg.isGroup

    for i in pkg.conflicts:
        if dirExists(root&"/var/cache/kpkg/installed/"&i):
            err(i&" conflicts with "&package)

    removeDir("/tmp/kpkg/reinstall/"&package&"-old")
    createDir("/tmp")
    createDir("/tmp/kpkg")

    var tarball: string

    if not isGroup:
        tarball = "/var/cache/kpkg/archives/arch/"&arch&"/kpkg-tarball-"&package&"-"&pkg.versionString&".tar.gz"
        
        if fileExists(tarball&".sum.b2"):
            if getSum(tarball, "b2") != readAll(open(
                tarball&".sum.b2")):
                err("b2sum doesn't match for "&package, false)
        elif fileExists(tarball&".sum"):
            # For backwards compatibility
            if getSum(tarball, "sha256")&"  "&tarball != readAll(open(
                tarball&".sum")):
                err("sha256sum doesn't match for "&package, false)

    setCurrentDir("/var/cache/kpkg/archives")
    
    for i in pkg.replaces:
        if symlinkExists(root&"/var/cache/kpkg/installed/"&i):
            removeFile(root&"/var/cache/kpkg/installed/"&i)
        elif dirExists(root&"/var/cache/kpkg/installed/"&i):
            if arch != hostCPU:
                removeInternal(i, root, initCheck = false)
            else:
                removeInternal(i, root)
        createSymlink(package, root&"/var/cache/kpkg/installed/"&i)

    if dirExists(root&"/var/cache/kpkg/installed/"&package) and
            not symlinkExists(root&"/var/cache/kpkg/installed/"&package) and not isGroup:

        info "package already installed, reinstalling"
        if arch != hostCPU:
            removeInternal(package, root, ignoreReplaces = true, noRunfile = true, initCheck = false)
        else:
            removeInternal(package, root, ignoreReplaces = true, noRunfile = true)

    discard existsOrCreateDir(root&"/var/cache")
    discard existsOrCreateDir(root&"/var/cache/kpkg")
    discard existsOrCreateDir(root&"/var/cache/kpkg/installed")
    removeDir(root&"/var/cache/kpkg/installed/"&package)
    copyDir(repo&"/"&package, root&"/var/cache/kpkg/installed/"&package)
    
    if not isGroup:
        var extractTarball: seq[string]
        let kpkgInstallTemp = "/opt/kpkg/install-"&package
        if dirExists(kpkgInstallTemp):
            removeDir(kpkgInstallTemp)
        
        createDir(kpkgInstallTemp)
        try:
          extractTarball = extract(tarball, kpkgInstallTemp, pkg.backup)
        except Exception:
            removeDir(root&"/var/cache/kpkg/installed/"&package)
            when defined(release):
                err("extracting the tarball failed for "&package)
            else:
                raise getCurrentException()
        
        if not fileExists(kpkgInstallTemp&"/pkgsums.ini"):
            # Backwards compatibility with kpkg v6
            writeFile(root&"/var/cache/kpkg/installed/"&package&"/list_files", extractTarball.join("\n"))
        else:    
            var dict = loadConfig(kpkgInstallTemp&"/pkgsums.ini")

            # Checking loop
            for file in extractTarball:
                if "pkgsums.ini" == lastPathPart(file): continue
                debug kpkgInstallTemp&"/"&relativePath(file, kpkgInstallTemp)
                let value = dict.getSectionValue("", relativePath(file, kpkgInstallTemp))
                let doesFileExist = fileExists(kpkgInstallTemp&"/"&file)

                if isEmptyOrWhitespace(value) and not doesFileExist:
                    continue
                
                if isEmptyOrWhitespace(value) and doesFileExist:
                    err("package sums invalid")

                if getSum(kpkgInstallTemp&"/"&file, "b2") != value:
                    err("sum for file '"&file&"' invalid")
            
            # Installation loop 
            for file in extractTarball:
                if "pkgsums.ini" == lastPathPart(file):
                    moveFile(kpkgInstallTemp&"/"&file, "/var/cache/kpkg/installed/"&package&"/list_files")
                let doesFileExist = fileExists(kpkgInstallTemp&"/"&file)
                if doesFileExist:
                    if not dirExists(root&"/"&file.parentDir()):
                        createDirWithPermissionsAndOwnership(kpkgInstallTemp&"/"&file.parentDir(), root&"/"&file.parentDir())
                    copyFileWithPermissionsAndOwnership(kpkgInstallTemp&"/"&file, root&"/"&file)
                elif dirExists(kpkgInstallTemp&"/"&file) and (not dirExists(root&"/"&file)):
                    createDirWithPermissionsAndOwnership(kpkgInstallTemp&"/"&file, root&"/"&file)

    # Run ldconfig afterwards for any new libraries
    discard execProcess("ldconfig")

    removeDir("/tmp/kpkg")
    removeDir("/opt/kpkg")

    if package in manualInstallList:
      info "Setting as manually installed"
      writeFile(root&"/var/cache/kpkg/installed/"&package&"/manualInstall", "")

    var existsPkgPostinstall = execCmdEx(
            ". "&repo&"/"&package&"/run"&" && command -v postinstall_"&replace(
                    package, '-', '_')).exitCode
    var existsPostinstall = execCmdEx(
            ". "&repo&"/"&package&"/run"&" && command -v postinstall").exitCode

    if existsPkgPostinstall == 0:
        if execCmdKpkg(". "&repo&"/"&package&"/run"&" && postinstall_"&replace(
                package, '-', '_')) != 0:
            if ignorePostInstall:
                warn "postinstall failed"
            else:
                err("postinstall failed")
    elif existsPostinstall == 0:
        if execCmdKpkg(". "&repo&"/"&package&"/run"&" && postinstall") != 0:
            if ignorePostInstall:
                warn "postinstall failed"
            else:
                err("postinstall failed")

    
    if isUpgrade:
        var existsPkgPostUpgrade = execCmdEx(". "&repo&"/"&package&"/run"&" && command -v postupgrade_"&replace(package, '-', '_')).exitCode
        var existsPostUpgrade = execCmdEx(". "&repo&"/"&package&"/run"&" && command -v postupgrade").exitCode
        
        if existsPkgPostUpgrade == 0:
            if execCmdKpkg(". "&repo&"/"&package&"/run"&" && postupgrade_"&replace(package, '-', '_')) != 0:
                err("postupgrade failed")
        
        if existsPostUpgrade == 0:
            if execCmdKpkg(". "&repo&"/"&package&"/run"&" && postupgrade") != 0:
                err("postupgrade failed")

    for i in pkg.optdeps:
        info(i)

proc down_bin(package: string, binrepos: seq[string], root: string,
        offline: bool, forceDownload = false, ignoreDownloadErrors = false) =
    ## Downloads binaries.
    
    discard existsOrCreateDir("/var/")
    discard existsOrCreateDir("/var/cache")
    discard existsOrCreateDir("/var/cache/kpkg")
    discard existsOrCreateDir("/var/cache/kpkg/archives")
    discard existsOrCreateDir("/var/cache/kpkg/archives/arch")
    discard existsOrCreateDir("/var/cache/kpkg/archives/arch/"&hostCPU)

    setCurrentDir("/var/cache/kpkg/archives")
    var downSuccess: bool

    var binreposFinal = binrepos
    
    var override: Config
    
    if fileExists("/etc/kpkg/override/"&package&".conf"):
        override = loadConfig("/etc/kpkg/override/"&package&".conf")
    else:
        override = newConfig() # So we don't get storage access errors
    
    let binreposOverride = override.getSectionValue("Mirror", "binaryMirrors")

    if not isEmptyOrWhitespace(binreposOverride):
        binreposFinal = binreposOverride.split(" ")

    for binrepo in binreposFinal:
        var repo: string

        repo = findPkgRepo(package)
        var pkg: runFile

        try:
            pkg = parseRunfile(repo&"/"&package)
        except CatchableError:
            err("Unknown error while trying to parse package on repository, possibly broken repo?")

        if pkg.isGroup:
            return

        let tarball = "kpkg-tarball-"&package&"-"&pkg.versionString&".tar.gz"
        let chksum = tarball&".sum"

        if fileExists("/var/cache/kpkg/archives/arch/"&hostCPU&"/"&tarball) and
                (fileExists("/var/cache/kpkg/archives/arch/"&hostCPU&"/"&chksum) or fileExists("/var/cache/kpkg/archives/arch/"&hostCPU&"/"&chksum&".b2")) and (not forceDownload):
            echo "Tarball already exists for '"&package&"', not gonna download again"
            downSuccess = true
        elif not offline:
            echo "Downloading tarball for "&package
            try:
                download("https://"&binrepo&"/arch/"&hostCPU&"/"&tarball,
                    "/var/cache/kpkg/archives/arch/"&hostCPU&"/"&tarball)
                echo "Downloading checksums for "&package
                try:
                    download("https://"&binrepo&"/arch/"&hostCPU&"/"&chksum&".b2", "/var/cache/kpkg/archives/arch/"&hostCPU&"/"&chksum&".b2", raiseWhenFail = true)
                except Exception: 
                    download("https://"&binrepo&"/arch/"&hostCPU&"/"&chksum,
                        "/var/cache/kpkg/archives/arch/"&hostCPU&"/"&chksum)
                downSuccess = true
            except CatchableError:
                if ignoreDownloadErrors:
                    downSuccess = true
                discard
        else:
            err("attempted to download tarball from binary repository in offline mode")

    if not downSuccess:
        err("couldn't download the binary")

proc install_bin(packages: seq[string], binrepos: seq[string], root: string,
        offline: bool, downloadOnly = false, manualInstallList: seq[string], arch = hostCPU, forceDownload = false, ignoreDownloadErrors = false) =
    ## Downloads and installs binaries.

    var repo: string
    
    isKpkgRunning()
    checkLockfile()
    createLockfile()

    for i in packages:
        down_bin(i, binrepos, root, offline, forceDownload, ignoreDownloadErrors = ignoreDownloadErrors) # TODO: add arch

    if not downloadOnly:
        for i in packages:
            repo = findPkgRepo(i)
            install_pkg(repo, i, root, manualInstallList = manualInstallList, arch = arch)
            info "Installation for "&i&" complete"

    removeLockfile()

proc install*(promptPackages: seq[string], root = "/", yes: bool = false,
        no: bool = false, forceDownload = false, offline = false, downloadOnly = false, ignoreDownloadErrors = false, isUpgrade = false, arch = hostCPU): int =
    ## Download and install a package through a binary repository.
    if promptPackages.len == 0:
        err("please enter a package name", false)

    if not isAdmin():
        err("you have to be root for this action.", false)
    
    var deps: seq[string]
    let init = getInit(root)

    var packages: seq[string]

    let fullRootPath = expandFilename(root)

    for i in promptPackages:
        let currentPackage = lastPathPart(i)
        packages = packages&currentPackage
        if findPkgRepo(currentPackage&"-"&init) != "":
            packages = packages&(currentPackage&"-"&init) 

    try:
        deps = dephandler(packages, root = root)
    except CatchableError:
        err("Dependency detection failed", false)

    printReplacesPrompt(deps, root, true)
    printReplacesPrompt(packages, root)

    let binrepos = getConfigValue("Repositories", "binRepos").split(" ")

    deps = deduplicate(deps&packages)
    printPackagesPrompt(deps.join(" "), yes, no)

    if not (deps.len == 0 and deps == @[""]):
        install_bin(deps, binrepos, fullRootPath, offline,
                downloadOnly = downloadOnly, manualInstallList = promptPackages, arch = arch, forceDownload = forceDownload, ignoreDownloadErrors = ignoreDownloadErrors)

    info("done")
    return 0
