import os
import posix
import config
import logger
import strutils
import parsecfg
import runparser

proc getInit*(root: string): string =
  ## Returns the init system.
  try:
    return loadConfig(root&"/etc/kreato-release").getSectionValue("Core", "init")
  except CatchableError:
    err("couldn't load "&root&"/etc/kreato-release")



proc copyFileWithPermissionsAndOwnership(f: string, t: string) =
  # Copies file with permissions and ownership.
  if not isAdmin():
    err "You need to be root for this action."

  let fc: cstring = f
  var s: Stat

  discard stat(fc, s)
  copyFileWithPermissions(f, t, options = {cfSymlinkAsIs})

  discard chown(f, s.st_uid, s.st_gid)

proc copyDirWithPermissionsAndOwnership(f: string, t: string) =
  # Copies file with permissions and ownership.
  if not isAdmin():
    err "You need to be root for this action."

  let fc: cstring = f
  var s: Stat

  discard stat(fc, s)
  copyDirWithPermissions(f, t)

  discard chown(f, s.st_uid, s.st_gid)



proc cp*(f: string, t: string) =
  ## Moves files and directories.
  var d: string

  setCurrentDir(f)

  for i in walkFiles("."):
    debug "copying "&i&" to "&t&"/"&i
    copyFileWithPermissionsAndOwnership(i, t&"/"&i)

  for i in walkDirRec(".", {pcFile, pcLinkToFile, pcDir, pcLinkToDir}):
    d = t&"/"&splitFile(i).dir

    if dirExists(i) and not dirExists(t&"/"&i):
      debug "going to copy dir "&i&" to "&t&"/"&i
      copyDirWithPermissionsAndOwnership(i, t&"/"&i)

    debug "creating directory to "&d
    createDir(d)

    if fileExists(i) or symlinkExists(i):
      debug i&" is a symlink or a file"

      if fileExists(t&"/"&i) or symlinkExists(t&"/"&i):
        debug t&"/"&i&" exists as a symlink/file, removing"
        removeFile(t&"/"&i)
      elif dirExists(t&"/"&i):
        debug t&"/"&i&" exists as a directory, removing"
        removeDir(t&"/"&i)

      debug "copying "&i&" to "&t&"/"&i
      copyFileWithPermissionsAndOwnership(i, t&"/"&i)

proc printPackagesPrompt*(packages: string, yes: bool, no: bool) =
  ## Prints the packages summary prompt.

  echo "Packages: "&packages

  var output: string

  if yes:
    output = "y"
  elif no:
    output = "n"
  else:
    stdout.write "Do you want to continue? (y/N) "
    output = readLine(stdin)

  if output.toLower() != "y":
    info("exiting", true)

proc ctrlc*() {.noconv.} =
  for path in walkFiles("/var/cache/kpkg/archives/arch/"&hostCPU&"/*.partial"):
    removeFile(path)

  echo ""
  info "ctrl+c pressed, shutting down"
  quit(130)

proc printReplacesPrompt*(pkgs: seq[string], root: string, isDeps = false) =
  ## Prints a replacesPrompt.
  for i in pkgs:
    for p in parse_runfile(findPkgRepo(i)&"/"&i).replaces:
      if isDeps and dirExists(root&"/var/cache/kpkg/installed/"&p):
        continue
      if dirExists(root&"/var/cache/kpkg/installed/"&p) and not symlinkExists(
          root&"/var/cache/installed/"&p):
        info "'"&i&"' replaces '"&p&"'"

