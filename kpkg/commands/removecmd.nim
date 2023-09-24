import os
import strutils
import ../modules/logger
import ../modules/removeInternal

proc remove*(packages: seq[string], yes = false, root = "",
        force = false, autoRemove = false): string =
    # Remove packages

    # bail early if user isn't admin
    if not isAdmin():
        err("you have to be root for this action.", false)

    if packages.len == 0:
        err("please enter a package name", false)

    var output: string
    var packagesFinal = packages
    
    if autoRemove:
      for package in packages:
        if not dirExists(root&"/var/cache/kpkg/installed/"&package):
          err("package "&package&" is not installed", false)
        packagesFinal = bloatDepends(package, root&"/var/cache/kpkg/installed", root)&packagesFinal

    if not yes:
        echo "Removing: "&packagesFinal.join(" ")
        stdout.write "Do you want to continue? (y/N) "
        output = readLine(stdin)
    else:
        output = "y"

    if output.toLower() == "y":
        for i in packagesFinal:
            removeInternal(i, root, force = force, depCheck = true, fullPkgList = packages)
            success("package "&i&" removed")
        success("done", true)

    info("exiting", true)
