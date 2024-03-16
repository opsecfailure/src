#!/bin/sh
# CI build script
#

e() {
    sqlite3 /var/cache/kpkg/kpkg.sqlite .dump
    sqlite3 /var/cache/kpkg/env/var/cache/kpkg/kpkg.sqlite .dump
    sqlite3 /opt/kpkg/overlay/upperDir/var/cache/kpkg/kpkg.sqlite .dump
    exit 1
}

case $1 in
        "init")
                if [ "$IS_ACTIONS" = "y" ]; then
                        ln -s "$GITHUB_WORKSPACE" /work
                        git config --global --add safe.directory $GITHUB_WORKSPACE
                fi
                
		            mkdir /out
                ln -s /out /work/out
                cd /work || exit 1
                
  	            kpkg # Initializes configs
		            sed -i s/stable/master/g /etc/kpkg/kpkg.conf # Switch to master repos
		            kpkg update
                kpkg build bzip2 -y || exit 1
    
                kpkg build python -y || exit 1

		            kpkg build ninja -y
                kpkg build llvm -y # Required by futhark

                #rm -r /var/cache/kpkg/archives/x86_64-linux-gnu-systemd-openssl
                #cp -r /var/cache/kpkg/archives/system/x86_64-linux-gnu-jumpstart-openssl /var/cache/kpkg/archives/system/x86_64-linux-gnu-systemd-openssl # temp, see #100

                
                export PATH=$PATH:$HOME/.nimble/bin # Add nimble path so opir can run
                
  	            ./build.sh -i
                nim c --deepcopy:on scripts/sqlite.nim
                scripts/sqlite || true

		            nim c -d:branch=master --deepcopy:on --passL:-larchive --passC:-no-pie --threads:on -d:ssl -o=kreastrap/kreastrap kreastrap/kreastrap.nim
                
		            cat /etc/group | grep tty || addgroup tty
        ;;

        "build")
                git config --global --add safe.directory /etc/kpkg/repos/main
                rm -rf /out/*
                cd /work || exit 1				

  		if [ -z "$3" ]; then
			arch="amd64"
		else
			arch="$3"
		fi
  
                ./kreastrap/kreastrap --buildType="$2" --arch="$arch" || e
                cd /out || exit 1
                tar -czvf /work/kreato-linux-"$2"-glibc-"$(date +%d-%m-%Y)"-amd64.tar.gz *
        ;;
esac
