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
    
    tar -xf binutils-2.23.1.tar.bz2
    
    mkdir -v binutils-build
    
    (
	cd binutils-build
	
	../binutils-2.23.1/configure     \
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
    
    rm -rf binutils-2.23.1 binutils-build
)

################################################################################
### 5.5 GCC pass 1
################################################################################

[ -f ../tools/bin/x86_64-lfs-linux-gnu-gcc ] || (
    
    tar -xf gcc-4.7.2.tar.bz2
    
    (
	cd gcc-4.7.2
	
	tar -Jxf ../mpfr-3.1.1.tar.xz
	mv -v mpfr-3.1.1 mpfr
	tar -Jxf ../gmp-5.1.1.tar.xz
	mv -v gmp-5.1.1 gmp
	tar -zxf ../mpc-1.0.1.tar.gz
	mv -v mpc-1.0.1 mpc
	
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
	
	sed -i 's/BUILD_INFO=info/BUILD_INFO=/' gcc/configure
	
	mkdir -v ../gcc-build
	cd ../gcc-build
	
	../gcc-4.7.2/configure         \
	    --target=$LFS_TGT          \
	    --prefix=/tools            \
	    --with-sysroot=$LFS        \
	    --with-newlib              \
	    --without-headers          \
	    --with-local-prefix=/tools \
	    --with-native-system-header-dir=/tools/include \
	    --disable-nls              \
	    --disable-shared           \
	    --disable-multilib         \
	    --disable-decimal-float    \
	    --disable-threads          \
	    --disable-libmudflap       \
	    --disable-libssp           \
	    --disable-libgomp          \
	    --disable-libquadmath      \
	    --enable-languages=c       \
	    --with-mpfr-include=$(pwd)/../gcc-4.7.2/mpfr/src \
	    --with-mpfr-lib=$(pwd)/mpfr/src/.libs
	
	make
	
	make install
	
	ln -sv libgcc.a `$LFS_TGT-gcc -print-libgcc-file-name | sed 's/libgcc/&_eh/'`
    )
    
    rm -rf gcc-4.7.2 gcc-build
)

################################################################################
### 5.6 Linux API headers
################################################################################

[ -f ../tools/include/linux/kernel.h ] || (
    
    tar -xf linux-3.8.13.tar.xz

    (
	cd linux-3.8.13
	
	make mrproper
	
	make headers_check
	make INSTALL_HDR_PATH=dest headers_install
	cp -rv dest/include/* /tools/include
    )
    
    rm -rf linux-3.8.13
)

################################################################################
### 5.7 Glibc
################################################################################

[ -f ../tools/lib/libc.so ] || (
    
    tar -xf glibc-2.17.tar.xz
    
    mkdir -v glibc-build
    
    (
	cd glibc-build
	
	../glibc-2.17/configure                             \
	    --prefix=/tools                                 \
	    --host=$LFS_TGT                                 \
	    --build=$(../glibc-2.17/scripts/config.guess) \
	    --disable-profile                               \
	    --enable-kernel=2.6.25                          \
	    --with-headers=/tools/include                   \
	    libc_cv_forced_unwind=yes                       \
	    libc_cv_ctors_header=yes                        \
	    libc_cv_c_cleanup=yes	
	make
	
	make install
    )
    
    rm -rf glibc-2.17 glibc-build
)

################################################################################
### 5.8 Binutils pass 2
################################################################################

[ -f ../tools/bin/ld ] || (

    tar -xf binutils-2.23.1.tar.bz2

    mkdir -v binutils-build
    
    (
	cd binutils-build
	
	CC=$LFS_TGT-gcc            \
	AR=$LFS_TGT-ar             \
	RANLIB=$LFS_TGT-ranlib     \
	../binutils-2.23.1/configure \
	    --prefix=/tools        \
	    --disable-nls          \
	    --with-lib-path=/tools/lib	
	
	make
	
	make install
	
	make -C ld clean
	make -C ld LIB_PATH=/usr/lib:/lib
	cp -v ld/ld-new /tools/bin
    )
    
    rm -rf binutils-2.23.1 binutils-build
)

################################################################################
### 5.9 GCC pass 2
################################################################################

[ -f ../tools/bin/gcc ] || (
    
    tar -xf gcc-4.7.2.tar.bz2

    (
	cd gcc-4.7.2
	
	cat gcc/limitx.h gcc/glimits.h gcc/limity.h > \
	    `dirname $($LFS_TGT-gcc -print-libgcc-file-name)`/include-fixed/limits.h
	
	cp -v gcc/Makefile.in{,.tmp}
	sed 's/^T_CFLAGS =$/& -fomit-frame-pointer/' gcc/Makefile.in.tmp \
	    > gcc/Makefile.in
	
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
	
	tar -Jxf ../mpfr-3.1.1.tar.xz
	mv -v mpfr-3.1.1 mpfr
	tar -Jxf ../gmp-5.1.1.tar.xz
	mv -v gmp-5.1.1 gmp
	tar -zxf ../mpc-1.0.1.tar.gz
	mv -v mpc-1.0.1 mpc
	
	sed -i 's/BUILD_INFO=info/BUILD_INFO=/' gcc/configure
	
	mkdir -v ../gcc-build
	cd ../gcc-build
	
	CC=$LFS_TGT-gcc \
	AR=$LFS_TGT-ar                  \
	RANLIB=$LFS_TGT-ranlib          \
	../gcc-4.7.2/configure          \
	    --prefix=/tools             \
	    --with-local-prefix=/tools  \
	    --with-native-system-header-dir=/tools/include \
	    --enable-clocale=gnu        \
	    --enable-shared             \
	    --enable-threads=posix      \
	    --enable-__cxa_atexit       \
	    --enable-languages=c,c++    \
	    --disable-libstdcxx-pch     \
	    --disable-multilib          \
	    --disable-bootstrap         \
	    --disable-libgomp           \
	    --with-mpfr-include=$(pwd)/../gcc-4.7.2/mpfr/src \
	    --with-mpfr-lib=$(pwd)/mpfr/src/.libs
	
	make
	
	make install
	
	ln -sv gcc /tools/bin/cc
    )
    
    rm -rf gcc-4.7.2 gcc-build
)

################################################################################
### 5.10 Tcl
################################################################################

[ -f ../tools/bin/tclsh8.6 ] || (

    tar -xf tcl8.6.0-src.tar.gz
    
    (
	cd tcl8.6.0
	
	cd unix
	./configure --prefix=/tools
	
	make
	
	make install
	
	chmod -v u+w /tools/lib/libtcl8.6.so
	
	make install-private-headers
	
	ln -sv tclsh8.6 /tools/bin/tclsh
    )
    
    rm -rf tcl8.6.0
)

################################################################################
### 5.11 Expect
################################################################################

[ -f ../tools/bin/expect ] || (

    tar -xf expect5.45.tar.gz
    
    (
	cd expect5.45
	
	cp -v configure{,.orig}
	sed 's:/usr/local/bin:/bin:' configure.orig > configure
	
	./configure --prefix=/tools --with-tcl=/tools/lib \
	    --with-tclinclude=/tools/include
	
	make
	
	make SCRIPTS="" install
    )
    
    rm -rf expect5.45
)

################################################################################
### 5.12 DejaGNU
################################################################################

[ -f ../tools/bin/runtest ] || (

    tar -xf dejagnu-1.5.tar.gz
    
    (
	cd dejagnu-1.5
	
	./configure --prefix=/tools
	
	make install
	
	make check
    )
    
    rm -rf dejagnu-1.5
)

################################################################################
### 5.13 Check
################################################################################

[ -f ../tools/bin/checkmk ] || (

    tar -xf check-0.9.9.tar.gz

    (
	cd check-0.9.9
	
# see http://www.linuxfromscratch.org/lfs/errata/stable/
	
	CFLAGS="-L/tools/lib -lpthread" ./configure --prefix=/tools
	
	CFLAGS="-L/tools/lib -lpthread" make
	
	make install
    )
    
    rm -rf check-0.9.9
)

################################################################################
### 5.14 Ncurses
################################################################################

[ -f ../tools/lib/libncurses.so ] || (

    tar -xf ncurses-5.9.tar.gz
    
    (
	cd ncurses-5.9
	
	./configure --prefix=/tools --with-shared \
	    --without-debug --without-ada --enable-overwrite
	
	make
	
	make install
    )

    rm -rf ncurses-5.9
)

################################################################################
### 5.15 Bash
################################################################################

[ -f ../tools/bin/bash ] || (
    
    tar -xf bash-4.2.tar.gz
    
    (
	cd bash-4.2
	
	patch -Np1 -i ../bash-4.2-fixes-11.patch
	
	./configure --prefix=/tools --without-bash-malloc
	
	make
	
	make install
	
	ln -sv bash /tools/bin/sh
    )
    
    rm -rf bash-4.2
)

################################################################################
### 5.16 Bzip
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
### 5.17 Coreutils
################################################################################

[ -f ../tools/bin/ls ] || (
    
    tar -xf coreutils-8.21.tar.xz
    
    (
	cd coreutils-8.21
	
	./configure --prefix=/tools --enable-install-program=hostname
	
	make
	
	make install
    )
    
    rm -rf coreutils-8.21
)

################################################################################
### 5.18 Diffutils
################################################################################

[ -f ../tools/bin/diff ] || (
    
    tar -xf diffutils-3.2.tar.gz
    
    (
	cd diffutils-3.2
	
	sed -i -e '/gets is a/d' lib/stdio.in.h
	
	./configure --prefix=/tools
	
	make
	
	make install
    )
    
    rm -rf diffutils-3.2
)

################################################################################
### 5.19 File
################################################################################

[ -f ../tools/bin/file ] || (
    
    tar -xf file-5.13.tar.gz
    
    (
	cd file-5.13
	
	./configure --prefix=/tools
	
	make
	
	make install
    )
    
    rm -rf file-5.13
)

################################################################################
### 5.20 Findutils
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
### 5.21 Gawk
################################################################################

[ -f ../tools/bin/gawk ] || (

    tar -xf gawk-4.0.2.tar.xz

    (
	cd gawk-4.0.2
	
	./configure --prefix=/tools
	
	make
	
	make install
    )
    
    rm -rf gawk-4.0.2
)

################################################################################
### 5.22 Gettext
################################################################################

[ -f ../tools/bin/msgfmt ] || (
    
    tar -xf gettext-0.18.2.tar.gz

    (
	cd gettext-0.18.2
	
	cd gettext-tools
	EMACS="no" ./configure --prefix=/tools --disable-shared
	
	make -C gnulib-lib
	make -C src msgfmt
	
	cp -v src/msgfmt /tools/bin
    )
    
    rm -rf gettext-0.18.2
)

################################################################################
### 5.23 Grep
################################################################################

[ -f ../tools/bin/grep ] || (
    
    tar -xf grep-2.14.tar.xz
    
    (
	cd grep-2.14
	
	./configure --prefix=/tools
	
	make
	
	make install
    )

    rm -rf grep-2.14
)

################################################################################
### 5.24 Gzip
################################################################################

[ -f ../tools/bin/gzip ] || (
    
    tar -xf gzip-1.5.tar.xz
    
    (
	cd gzip-1.5
	
	./configure --prefix=/tools
	
	make
	
	make install
    )
    
    rm -rf gzip-1.5
)

################################################################################
### 5.25 M4
################################################################################

[ -f ../tools/bin/m4 ] || (
    
    tar -xf m4-1.4.16.tar.bz2
    
    (
	cd m4-1.4.16
	
	sed -i -e '/gets is a/d' lib/stdio.in.h
	
	./configure --prefix=/tools
	
	make
	
	make install
    )
    
    rm -rf m4-1.4.16
)

################################################################################
### 5.26 Make
################################################################################

[ -f ../tools/bin/make ] || (
    
    tar -xf make-3.82.tar.bz2
    
    (
	cd make-3.82
	
	./configure --prefix=/tools
	
	make
	
	make install
    )
    
    rm -rf make-3.82
)

################################################################################
### 5.27 Patch
################################################################################

[ -f ../tools/bin/patch ] || (

    tar -xf patch-2.7.1.tar.xz

    (
	cd patch-2.7.1
	
	./configure --prefix=/tools
	
	make
	
	make install
    )

    rm -rf patch-2.7.1
)

################################################################################
### 5.28 Perl
################################################################################

[ -f ../tools/bin/perl ] || (
    
    tar -xf perl-5.16.2.tar.bz2
    
    (
	cd perl-5.16.2
	
	patch -Np1 -i ../perl-5.16.2-libc-1.patch
	
	sh Configure -des -Dprefix=/tools
	
	make
	
	cp -v perl cpan/podlators/pod2man /tools/bin
	mkdir -pv /tools/lib/perl5/5.16.2
	cp -Rv lib/* /tools/lib/perl5/5.16.2
    )
    
    rm -rf perl-5.16.2
)

################################################################################
### 5.29 Sed
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
### 5.30 Tar
################################################################################

[ -f ../tools/bin/tar ] || (
    
    tar -xf tar-1.26.tar.bz2
    
    (
	cd tar-1.26
	
	sed -i -e '/gets is a/d' gnu/stdio.in.h
	
	./configure --prefix=/tools
	
	make
	
	make install
    )
    
    rm -rf tar-1.26
)

################################################################################
### 5.31 Texinfo
################################################################################

[ -f ../tools/bin/info ] || (
    
    tar -xf texinfo-5.0.tar.xz
    
    (
	cd texinfo-5.0
	
	./configure --prefix=/tools
	
	make
	
	make install
    )
    
    rm -rf texinfo-5.0
)

################################################################################
### 5.32 Xz
################################################################################

[ -f ../tools/bin/xz ] || (
    
    tar -xf xz-5.0.4.tar.xz
    
    (
	cd xz-5.0.4
	
	./configure --prefix=/tools
	
	make
	
	make install
    )
    
    rm -rf xz-5.0.4
)
