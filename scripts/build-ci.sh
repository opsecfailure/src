#!/bin/sh
# CI build script
case $1 in
        "init")
                if [ "$IS_ACTIONS" = "y" ]; then
                        ln -s "$GITHUB_WORKSPACE" /work
                        git config --global --add safe.directory $GITHUB_WORKSPACE
                fi
                mkdir /out
                ln -s /out /work/out
                cd /work || exit 1
                #echo "https://dl-cdn.alpinelinux.org/alpine/v$(cut -d'.' -f1,2 /etc/alpine-release)/main/" > /etc/apk/repositories
                #echo "https://dl-cdn.alpinelinux.org/alpine/v$(cut -d'.' -f1,2 /etc/alpine-release)/community/" >> /etc/apk/repositories
                #echo "https://dl-cdn.alpinelinux.org/alpine/edge/testing/" >> /etc/apk/repositories
                #apk update
                #apk add build-base llvm-libunwind-dev compiler-rt libc++-dev alpine-sdk nimble shadow libarchive-tools perl zlib-dev llvm clang linux-headers openssl-dev binutils-dev gettext-dev xz libgcc gcc
                #make kpkg 
                #rm -f /var/cache/kpkg/archives/*kpkg*
	
  		# Temporary
   		wget https://github.com/kreatolinux/src/archive/refs/tags/v6.0.1.tar.gz
     		tar -xvf v6.0.1.tar.gz
       		cd src-v6.0.1 || exit 1
	 	wget https://github.com/kreatolinux/src/commit/810318f50a446650e263744d8ba34a86a596117e.patch
   		patch -p1 < 810318f50a446650e263744d8ba34a86a596117e.patch || exit 1
	 	make deps kpkg
		./out/kpkg update
  		./out/kpkg install xz-utils -y
    
		./out/kpkg build llvm -y
  		make deps
                rm -vf /etc/kpkg/kpkg.conf
                rm -rf /tmp/kpkg
                nim c -d:branch=master --passC:-no-pie --threads:on -d:ssl -o=kreastrap/kreastrap kreastrap/kreastrap.nim
                cat /etc/group | grep tty || addgroup tty
		#make kreastrap
        ;;

        "build")
                git config --global --add safe.directory /etc/kpkg/repos/main
                rm -rf /out/*
                cd /work || exit 1
                ./kreastrap/kreastrap --buildType="$2" --arch=amd64 || exit 1
                cd /out || exit 1
                tar -czvf /work/kreato-linux-"$2"-glibc-"$(date +%d-%m-%Y)"-amd64.tar.gz *
        ;;
esac
