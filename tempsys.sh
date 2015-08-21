#! /bin/bash

set -e

################################################################################
### 4.5
################################################################################

export MAKEFLAGS='-j 4'

################################################################################
### 5.3
################################################################################

cd $LFS/sources

################################################################################
### 5.4 Binutils pass 1
################################################################################

[ -f ../tools/bin/x86_64-lfs-linux-gnu-ld ] || (

    tar -xf binutils-2.25.tar.bz2

    (
        cd binutils-2.25

        mkdir -v ../binutils-build
        cd ../binutils-build

        ../binutils-2.25/configure     \
            --prefix=/tools            \
            --with-sysroot=$LFS        \
            --with-lib-path=/tools/lib \
            --target=$LFS_TGT          \
            --disable-nls              \
            --disable-werror

        make

        case $(uname -m) in
          x86_64) mkdir -v /tools/lib && ln -sv lib /tools/lib64 ;;
        esac

        make install
    )

    rm -rf binutils-2.25 binutils-build
)

################################################################################
### 5.5 GCC pass 1
################################################################################

[ -f ../tools/bin/x86_64-lfs-linux-gnu-gcc ] || (

    tar -xf gcc-4.9.2.tar.bz2

    (
        cd gcc-4.9.2

        tar -xf ../mpfr-3.1.2.tar.xz
        mv -v mpfr-3.1.2 mpfr
        tar -xf ../gmp-6.0.0a.tar.xz
        mv -v gmp-6.0.0 gmp
        tar -xf ../mpc-1.0.2.tar.gz
        mv -v mpc-1.0.2 mpc

        for file in \
         $(find gcc/config -name linux64.h -o -name linux.h -o -name sysv4.h)
        do
          cp -uv $file{,.orig}
          sed -e 's@/lib\(64\)\?\(32\)\?/ld@/tools&@g' \
              -e 's@/usr@/tools@g' $file.orig > $file
          echo '
#undef STANDARD_STARTFILE_PREFIX_1
#undef STANDARD_STARTFILE_PREFIX_2
#define STANDARD_STARTFILE_PREFIX_1 "/tools/lib/"
#define STANDARD_STARTFILE_PREFIX_2 ""' >> $file
          touch $file.orig
        done

        sed -i '/k prot/agcc_cv_libc_provides_ssp=yes' gcc/configure

        mkdir -v ../gcc-build
        cd ../gcc-build

        ../gcc-4.9.2/configure                               \
            --target=$LFS_TGT                                \
            --prefix=/tools                                  \
            --with-sysroot=$LFS                              \
            --with-newlib                                    \
            --without-headers                                \
            --with-local-prefix=/tools                       \
            --with-native-system-header-dir=/tools/include   \
            --disable-nls                                    \
            --disable-shared                                 \
            --disable-multilib                               \
            --disable-decimal-float                          \
            --disable-threads                                \
            --disable-libatomic                              \
            --disable-libgomp                                \
            --disable-libitm                                 \
            --disable-libquadmath                            \
            --disable-libsanitizer                           \
            --disable-libssp                                 \
            --disable-libvtv                                 \
            --disable-libcilkrts                             \
            --disable-libstdc++-v3                           \
            --enable-languages=c,c++

        make

        make install
    )

    rm -rf gcc-4.9.2 gcc-build
)

################################################################################
### 5.6 Linux API headers
################################################################################

[ -f ../tools/include/linux/kernel.h ] || (

    tar -xf linux-3.19.tar.xz

    (
        cd linux-3.19

        make mrproper

        make INSTALL_HDR_PATH=dest headers_install
        cp -rv dest/include/* /tools/include
    )

    rm -rf linux-3.19
)

################################################################################
### 5.7 Glibc
################################################################################

[ -f ../tools/lib/libc.so ] || (

    tar -xf glibc-2.21.tar.xz

    (
        cd glibc-2.21

        sed -e '/ia32/s/^/1:/' \
            -e '/SSE2/s/^1://' \
            -i  sysdeps/i386/i686/multiarch/mempcpy_chk.S

        mkdir -v ../glibc-build
        cd ../glibc-build

        ../glibc-2.21/configure                             \
              --prefix=/tools                               \
              --host=$LFS_TGT                               \
              --build=$(../glibc-2.21/scripts/config.guess) \
              --disable-profile                             \
              --enable-kernel=2.6.32                        \
              --with-headers=/tools/include                 \
              libc_cv_forced_unwind=yes                     \
              libc_cv_ctors_header=yes                      \
              libc_cv_c_cleanup=yes

        make

        make install
    )

    rm -rf glibc-2.21 glibc-build
)

################################################################################
### 5.8 Libstdc++
################################################################################

[ -f ../tools/lib/libstdc++.a ] || (

    tar -xf gcc-4.9.2.tar.bz2

    (
        cd gcc-4.9.2

        mkdir -pv ../gcc-build
        cd ../gcc-build

        ../gcc-4.9.2/libstdc++-v3/configure \
            --host=$LFS_TGT                 \
            --prefix=/tools                 \
            --disable-multilib              \
            --disable-shared                \
            --disable-nls                   \
            --disable-libstdcxx-threads     \
            --disable-libstdcxx-pch         \
            --with-gxx-include-dir=/tools/$LFS_TGT/include/c++/4.9.2

        make

        make install
    )

    rm -rf gcc-4.9.2 gcc-build
)

################################################################################
### 5.9 Binutils pass 2
################################################################################

[ -f ../tools/bin/ld ] || (

    tar -xf binutils-2.25.tar.bz2

    (
        cd binutils-2.25

        mkdir -v ../binutils-build
        cd ../binutils-build

        CC=$LFS_TGT-gcc                \
        AR=$LFS_TGT-ar                 \
        RANLIB=$LFS_TGT-ranlib         \
        ../binutils-2.25/configure     \
            --prefix=/tools            \
            --disable-nls              \
            --disable-werror           \
            --with-lib-path=/tools/lib \
            --with-sysroot

        make

        make install

        make -C ld clean
        make -C ld LIB_PATH=/usr/lib:/lib
        cp -v ld/ld-new /tools/bin
    )

    rm -rf binutils-2.25 binutils-build
)

################################################################################
### 5.10 GCC pass 2
################################################################################

[ -f ../tools/bin/gcc ] || (

    tar -xf gcc-4.9.2.tar.bz2

    (
        cd gcc-4.9.2

        cat gcc/limitx.h gcc/glimits.h gcc/limity.h > \
          `dirname $($LFS_TGT-gcc -print-libgcc-file-name)`/include-fixed/limits.h

        for file in \
         $(find gcc/config -name linux64.h -o -name linux.h -o -name sysv4.h)
        do
          cp -uv $file{,.orig}
          sed -e 's@/lib\(64\)\?\(32\)\?/ld@/tools&@g' \
              -e 's@/usr@/tools@g' $file.orig > $file
          echo '
#undef STANDARD_STARTFILE_PREFIX_1
#undef STANDARD_STARTFILE_PREFIX_2
#define STANDARD_STARTFILE_PREFIX_1 "/tools/lib/"
#define STANDARD_STARTFILE_PREFIX_2 ""' >> $file
          touch $file.orig
        done

        tar -xf ../mpfr-3.1.2.tar.xz
        mv -v mpfr-3.1.2 mpfr
        tar -xf ../gmp-6.0.0a.tar.xz
        mv -v gmp-6.0.0 gmp
        tar -xf ../mpc-1.0.2.tar.gz
        mv -v mpc-1.0.2 mpc

        mkdir -v ../gcc-build
        cd ../gcc-build

        CC=$LFS_TGT-gcc                                      \
        CXX=$LFS_TGT-g++                                     \
        AR=$LFS_TGT-ar                                       \
        RANLIB=$LFS_TGT-ranlib                               \
        ../gcc-4.9.2/configure                               \
            --prefix=/tools                                  \
            --with-local-prefix=/tools                       \
            --with-native-system-header-dir=/tools/include   \
            --enable-languages=c,c++                         \
            --disable-libstdcxx-pch                          \
            --disable-multilib                               \
            --disable-bootstrap                              \
            --disable-libgomp

        make

        make install

        ln -sv gcc /tools/bin/cc
    )

    rm -rf gcc-4.9.2 gcc-build
)

################################################################################
### 5.11 Tcl
################################################################################

[ -f ../tools/bin/tclsh8.6 ] || (

    tar -xf tcl8.6.3-src.tar.gz

    (
        cd tcl8.6.3

        cd unix
        ./configure --prefix=/tools

        make

        make install

        chmod -v u+w /tools/lib/libtcl8.6.so

        make install-private-headers

        ln -sv tclsh8.6 /tools/bin/tclsh
    )
    
    rm -rf tcl8.6.3
)

################################################################################
### 5.12 Expect
################################################################################

[ -f ../tools/bin/expect ] || (

    tar -xf expect5.45.tar.gz

    (
        cd expect5.45

        cp -v configure{,.orig}
        sed 's:/usr/local/bin:/bin:' configure.orig > configure

        ./configure --prefix=/tools       \
                    --with-tcl=/tools/lib \
                    --with-tclinclude=/tools/include

        make

        make SCRIPTS="" install
    )

    rm -rf expect5.45
)

################################################################################
### 5.13 DejaGNU
################################################################################

[ -f ../tools/bin/runtest ] || (

    tar -xf dejagnu-1.5.2.tar.gz

    (
        cd dejagnu-1.5.2

        ./configure --prefix=/tools

        make install

        make check
    )

    rm -rf dejagnu-1.5.2
)

################################################################################
### 5.14 Check
################################################################################

[ -f ../tools/bin/checkmk ] || (

    tar -xf check-0.9.14.tar.gz

    (
        cd check-0.9.14

        PKG_CONFIG= ./configure --prefix=/tools

        make

        make install
    )

    rm -rf check-0.9.14
)

################################################################################
### 5.15 Ncurses
################################################################################

[ -f ../tools/lib/libncursesw.so ] || (

    tar -xf ncurses-5.9.tar.gz

    (
        cd ncurses-5.9

        ./configure --prefix=/tools \
                    --with-shared   \
                    --without-debug \
                    --without-ada   \
                    --enable-widec  \
                    --enable-overwrite

        make

        make install
    )

    rm -rf ncurses-5.9
)

################################################################################
### 5.16 Bash
################################################################################

[ -f ../tools/bin/bash ] || (

    tar -xf bash-4.3.30.tar.gz

    (
        cd bash-4.3.30

        ./configure --prefix=/tools --without-bash-malloc

        make

        make install

        ln -sv bash /tools/bin/sh
    )

    rm -rf bash-4.3.30
)

################################################################################
### 5.17 Bzip
################################################################################

[ -f ../tools/bin/bzip2 ] || (

    tar -xf bzip2-1.0.6.tar.gz

    (
        cd bzip2-1.0.6

        make

        make PREFIX=/tools install
    )

    rm -rf bzip2-1.0.6
)

################################################################################
### 5.18 Coreutils
################################################################################

[ -f ../tools/bin/ls ] || (

    tar -xf coreutils-8.23.tar.xz

    (
        cd coreutils-8.23

        ./configure --prefix=/tools --enable-install-program=hostname

        make

        make install
    )

    rm -rf coreutils-8.23
)

################################################################################
### 5.19 Diffutils
################################################################################

[ -f ../tools/bin/diff ] || (

    tar -xf diffutils-3.3.tar.xz

    (
        cd diffutils-3.3

        ./configure --prefix=/tools

        make

        make install
    )

    rm -rf diffutils-3.3
)

################################################################################
### 5.20 File
################################################################################

[ -f ../tools/bin/file ] || (

    tar -xf file-5.22.tar.gz

    (
        cd file-5.22

        ./configure --prefix=/tools

        make

        make install
    )

    rm -rf file-5.22
)

################################################################################
### 5.21 Findutils
################################################################################

[ -f ../tools/bin/find ] || (

    tar -xf findutils-4.4.2.tar.gz

    (
        cd findutils-4.4.2

        ./configure --prefix=/tools

        make

        make install
)

    rm -rf findutils-4.4.2
)

################################################################################
### 5.22 Gawk
################################################################################

[ -f ../tools/bin/gawk ] || (

    tar -xf gawk-4.1.1.tar.xz

    (
        cd gawk-4.1.1

        ./configure --prefix=/tools

        make

        make install
    )

    rm -rf gawk-4.1.1
)

################################################################################
### 5.23 Gettext
################################################################################

[ -f ../tools/bin/msgfmt ] || (

    tar -xf gettext-0.19.4.tar.xz

    (
        cd gettext-0.19.4

        cd gettext-tools
        EMACS="no" ./configure --prefix=/tools --disable-shared

        make -C gnulib-lib
        make -C intl pluralx.c
        make -C src msgfmt
        make -C src msgmerge
        make -C src xgettext

        cp -v src/{msgfmt,msgmerge,xgettext} /tools/bin

    )

    rm -rf gettext-0.19.4
)

################################################################################
### 5.24 Grep
################################################################################

[ -f ../tools/bin/grep ] || (

    tar -xf grep-2.21.tar.xz

    (
        cd grep-2.21

        ./configure --prefix=/tools

        make

        make install
    )

    rm -rf grep-2.21
)

################################################################################
### 5.25 Gzip
################################################################################

[ -f ../tools/bin/gzip ] || (

    tar -xf gzip-1.6.tar.xz

    (
        cd gzip-1.6

        ./configure --prefix=/tools

        make

        make install
    )

    rm -rf gzip-1.6
)

################################################################################
### 5.26 M4
################################################################################

[ -f ../tools/bin/m4 ] || (

    tar -xf m4-1.4.17.tar.xz

    (
        cd m4-1.4.17

        ./configure --prefix=/tools

        make

        make install
    )

    rm -rf m4-1.4.17
)

################################################################################
### 5.27 Make
################################################################################

[ -f ../tools/bin/make ] || (

    tar -xf make-4.1.tar.bz2

    (
        cd make-4.1

        ./configure --prefix=/tools --without-guile

        make

        make install
    )

    rm -rf make-4.1
)

################################################################################
### 5.28 Patch
################################################################################

[ -f ../tools/bin/patch ] || (

    tar -xf patch-2.7.4.tar.xz

    (
        cd patch-2.7.4

        ./configure --prefix=/tools

        make

        make install
    )

    rm -rf patch-2.7.4
)

################################################################################
### 5.29 Perl
################################################################################

[ -f ../tools/bin/perl ] || (

    tar -xf perl-5.20.2.tar.bz2

    (
        cd perl-5.20.2

        sh Configure -des -Dprefix=/tools -Dlibs=-lm

        make

        cp -v perl cpan/podlators/pod2man /tools/bin
        mkdir -pv /tools/lib/perl5/5.20.2
        cp -Rv lib/* /tools/lib/perl5/5.20.2
    )

    rm -rf perl-5.20.2
)

################################################################################
### 5.30 Sed
################################################################################

[ -f ../tools/bin/sed ] || (

    tar -xf sed-4.2.2.tar.bz2

    (
        cd sed-4.2.2

        ./configure --prefix=/tools

        make

        make install
    )

    rm -rf sed-4.2.2
)

################################################################################
### 5.31 Tar
################################################################################

[ -f ../tools/bin/tar ] || (

    tar -xf tar-1.28.tar.xz

    (
        cd tar-1.28

        ./configure --prefix=/tools

        make

        make install
    )

    rm -rf tar-1.28
)

################################################################################
### 5.32 Texinfo
################################################################################

[ -f ../tools/bin/makeinfo ] || (

    tar -xf texinfo-5.2.tar.xz

    (
        cd texinfo-5.2

        ./configure --prefix=/tools

        make

        make install
    )

    rm -rf texinfo-5.2
)

################################################################################
### 5.33 Util-linux
################################################################################

[ -f ../tools/bin/mount ] || (

    tar -xf util-linux-2.26.tar.xz

    (
        cd util-linux-2.26

        ./configure --prefix=/tools                \
                    --without-python               \
                    --disable-makeinstall-chown    \
                    --without-systemdsystemunitdir \
                    PKG_CONFIG=""

        make

        make install
    )

    rm -rf util-linux-2.26
)

################################################################################
### 5.34 Xz
################################################################################

[ -f ../tools/bin/xz ] || (

    tar -xf xz-5.2.0.tar.xz

    (
        cd xz-5.2.0

        ./configure --prefix=/tools

        make

        make install
    )

    rm -rf xz-5.2.0
)
