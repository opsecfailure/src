const kpkgTempDir1* = "/opt/kpkg"
const kpkgTempDir2* = "/tmp/kpkg"
const kpkgCacheDir* = "/var/cache/kpkg"
const kpkgLibDir* = "/var/lib/kpkg" 
const kpkgArchivesDir* = kpkgCacheDir&"/archives"
const kpkgSourcesDir* = kpkgCacheDir&"/sources"
const kpkgEnvPath* = kpkgCacheDir&"/env"
const kpkgOverlayPath* = kpkgTempDir1&"/overlay"
const kpkgMergedPath* = kpkgTempDir1&"/merged"
const kpkgDbPath* = kpkgLibDir&"/kpkg.sqlite"
const kpkgBuildRoot* = kpkgTempDir1&"/build"
const kpkgSrcDir* = kpkgTempDir1&"/srcdir"