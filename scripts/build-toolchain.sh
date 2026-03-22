#!/bin/bash
# Build script for m68k-atari-mintelf cross-toolchain
# Order: binutils -> gcc-frontend -> mintlib -> gcc-libgcc -> fdlibm -> gcc-finish -> libcmini -> gemlib -> gdb
# Usage: ./build-toolchain.sh all | download | binutils | gcc-frontend | mintlib | gcc-libgcc | fdlibm | gcc-finish | libcmini | gemlib | gdb

set -e
set -o pipefail

BUILD_START=$(date +%s)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${INSTALL_DIR:-$HOME/toolchains/cross-mintelf}"
SOURCES_DIR="${SOURCES_DIR:-$SCRIPT_DIR/sources}"
BUILD_DIR="${BUILD_DIR:-$SCRIPT_DIR/obj}"
TARGET="m68k-atari-mintelf"
JOBS="${JOBS:-$(nproc)}"

BINUTILS_VER="2.42";      BINUTILS_PATCH="mintelf-20240218"
GCC_VER="13.2.0";         GCC_PATCH="mintelf-20240130"
MINTLIB_VER="Git-20240114"
FDLIBM_VER="Git-20230207"
GDB_SRC_DIR="m68k-atari-mint-binutils-gdb-gdb-14-mintelf"
LIBCMINI_SRC_DIR="libcmini-master"
GEMLIB_SRC_DIR="gemlib-master"

export PATH="$INSTALL_DIR/bin:$PATH"

log() { echo -e "\n\033[1;32m>>> $*\033[0m\n"; }
die() { echo -e "\033[1;31mERROR: $*\033[0m" >&2; exit 1; }
elapsed() { local s=$(( $(date +%s) - BUILD_START )); printf "%02d:%02d" $((s/60)) $((s%60)); }

download_sources() {
    log "STEP 0: downloading sources"
    mkdir -p "$SOURCES_DIR"

    local VR="http://vincent.riviere.free.fr/soft/m68k-atari-mintelf/archives"
    local GNU="https://ftp.gnu.org/gnu"
    local GH="https://github.com"

    dl() {
        local file="$SOURCES_DIR/$1"
        if [ -f "$file" ]; then
            echo "exists: $1"
        else
            echo "downloading: $1"
            curl -L --fail -o "$file" "$2"
        fi
    }

    dl "binutils-$BINUTILS_VER.tar.xz"                   "$GNU/binutils/binutils-$BINUTILS_VER.tar.xz"
    dl "binutils-$BINUTILS_VER-$BINUTILS_PATCH.patch.xz" "$VR/binutils-$BINUTILS_VER-$BINUTILS_PATCH.patch.xz"
    dl "gcc-$GCC_VER.tar.xz"                             "$GNU/gcc/gcc-$GCC_VER/gcc-$GCC_VER.tar.xz"
    dl "gcc-$GCC_VER-$GCC_PATCH.patch.xz"                "$VR/gcc-$GCC_VER-$GCC_PATCH.patch.xz"
    dl "mintlib-$MINTLIB_VER.tar.xz"                     "$VR/mintlib-$MINTLIB_VER.tar.xz"
    dl "fdlibm-$FDLIBM_VER.tar.xz"                      "$VR/fdlibm-$FDLIBM_VER.tar.xz"
    dl "libcmini-master.tar.gz"  "$GH/freemint/libcmini/archive/refs/heads/master.tar.gz"
    dl "gemlib-master.tar.gz"    "$GH/freemint/gemlib/archive/refs/heads/master.tar.gz"
    dl "gdb-14-mintelf.tar.gz"   "$GH/vinriviere/m68k-atari-mint-binutils-gdb/archive/refs/heads/gdb-14-mintelf.tar.gz"

    log "Sources ready in $SOURCES_DIR"
}

check_deps() {
    log "Checking dependencies..."
    local missing=()
    for cmd in gcc g++ make patch tar xz bison flex makeinfo curl; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    for lib in libmpc-dev libmpfr-dev libgmp-dev libzstd-dev; do
        dpkg -s "$lib" &>/dev/null 2>&1 || missing+=("$lib")
    done
    [ ${#missing[@]} -eq 0 ] || die "Missing: ${missing[*]}"
    echo "OK"
}

_gcc_prepare() {
    local src="gcc-$GCC_VER"
    local patch="gcc-$GCC_VER-$GCC_PATCH"

    cd "$BUILD_DIR"
    [ -d "$src" ] || tar -xJf "$SOURCES_DIR/gcc-$GCC_VER.tar.xz"
    [ -d "$patch" ] || {
        cp -a "$src" "$patch"
        cd "$patch"
        xzcat "$SOURCES_DIR/gcc-$GCC_VER-$GCC_PATCH.patch.xz" | patch -p1
        cd ..
    }

    mkdir -p "$INSTALL_DIR/$TARGET/sys-root/usr/include"
    mkdir -p "$INSTALL_DIR/$TARGET/sys-root/usr/lib"
}

build_binutils() {
    log "STEP 1/9: binutils $BINUTILS_VER"

    local src="binutils-$BINUTILS_VER"
    local patch="binutils-$BINUTILS_VER-$BINUTILS_PATCH"
    local bld="$BUILD_DIR/$patch.obj"

    mkdir -p "$BUILD_DIR" && cd "$BUILD_DIR"
    [ -d "$src" ] || tar -xJf "$SOURCES_DIR/binutils-$BINUTILS_VER.tar.xz"
    [ -d "$patch" ] || {
        cp -a "$src" "$patch"
        cd "$patch"
        xzcat "$SOURCES_DIR/binutils-$BINUTILS_VER-$BINUTILS_PATCH.patch.xz" | patch -p1
        cd ..
    }

    mkdir -p "$bld" && cd "$bld"
    ../$patch/configure \
        --target=$TARGET \
        --prefix="$INSTALL_DIR" \
        --disable-nls \
        --disable-libctf \
        --with-system-zlib \
        CFLAGS="-O2" \
        CXXFLAGS="-O2"

    make -j$JOBS
    make install
    log "binutils installed"
}

build_gcc_frontend() {
    log "STEP 2/9: GCC $GCC_VER frontend (no libgcc)"

    local patch="gcc-$GCC_VER-$GCC_PATCH"
    local bld="$BUILD_DIR/$patch.obj"

    mkdir -p "$BUILD_DIR"
    _gcc_prepare
    mkdir -p "$bld" && cd "$bld"

    [ -f Makefile ] || \
    ../$patch/configure \
        --target=$TARGET \
        --prefix="$INSTALL_DIR" \
        --with-sysroot="$INSTALL_DIR/$TARGET/sys-root" \
        --enable-languages="c,c++" \
        --disable-nls \
        --disable-libstdcxx-pch \
        --disable-libcc1 \
        --disable-sjlj-exceptions \
        --disable-fixincludes \
        CFLAGS="-O2" \
        CXXFLAGS="-O2" \
        CFLAGS_FOR_TARGET="-O2 -fomit-frame-pointer" \
        CXXFLAGS_FOR_TARGET="-O2 -fomit-frame-pointer"

    make -j$JOBS all-gcc
    make install-gcc
    log "GCC frontend installed"
}

build_mintlib() {
    log "STEP 3/9: MiNTLib $MINTLIB_VER"

    local src="mintlib-$MINTLIB_VER"
    local sysroot="$INSTALL_DIR/$TARGET/sys-root"

    mkdir -p "$BUILD_DIR" && cd "$BUILD_DIR"
    [ -d "$src" ] || tar -xJf "$SOURCES_DIR/mintlib-$MINTLIB_VER.tar.xz"
    cd "$src"

    # tz/ and sunrpc/ build Atari target programs that link with -lgcc (not yet built)
    sed -i 's/\btz\b//g; s/\bsunrpc\b//g' Makefile

    make -j$JOBS SHELL=/bin/bash \
        CROSS_TOOL=$TARGET \
        prefix="$sysroot/usr" \
        includedir="$sysroot/usr/include" \
        libdir="$sysroot/usr/lib"

    make install SHELL=/bin/bash \
        CROSS_TOOL=$TARGET \
        prefix="$sysroot/usr" \
        includedir="$sysroot/usr/include" \
        libdir="$sysroot/usr/lib"

    log "MiNTLib installed"
}

build_gcc_libgcc() {
    log "STEP 4/9: GCC $GCC_VER libgcc"

    local bld="$BUILD_DIR/gcc-$GCC_VER-$GCC_PATCH.obj"
    [ -d "$bld" ] || die "Run gcc-frontend first"
    cd "$bld"

    make -j$JOBS all-target-libgcc
    make install-target-libgcc
    log "libgcc installed"
}

build_fdlibm() {
    log "STEP 5/9: FDLIBM $FDLIBM_VER"

    local src="fdlibm-$FDLIBM_VER"
    local bld="$BUILD_DIR/$src.obj"
    local sysroot="$INSTALL_DIR/$TARGET/sys-root"

    cd "$BUILD_DIR"
    [ -d "$src" ] || tar -xJf "$SOURCES_DIR/fdlibm-$FDLIBM_VER.tar.xz"
    mkdir -p "$bld" && cd "$bld"

    ../$src/configure \
        --host=$TARGET \
        --prefix="$sysroot/usr"

    sed -i 's/cp -a /cp /' Makefile
    make -j$JOBS
    make install
    log "FDLIBM installed"
}

build_gcc_finish() {
    log "STEP 6/9: GCC $GCC_VER finish (libstdc++ etc.)"

    local bld="$BUILD_DIR/gcc-$GCC_VER-$GCC_PATCH.obj"
    [ -d "$bld" ] || die "Run gcc-frontend first"
    cd "$bld"

    make -j$JOBS
    make install
    log "GCC fully installed"
}

build_libcmini() {
    log "STEP 7/9: libcmini"

    local src="$LIBCMINI_SRC_DIR"
    local dest="$INSTALL_DIR/libcmini"

    cd "$BUILD_DIR"
    [ -d "$src" ] || tar -xzf "$SOURCES_DIR/libcmini-master.tar.gz"
    cd "$src"

    # skip tests — they use the old m68k-atari-mint-gcc (a.out)
    make -j$JOBS CROSSPREFIX="$TARGET-" dirs libs startups

    mkdir -p "$dest/include" "$dest/lib"
    make CROSSPREFIX="$TARGET-" \
        PREFIX="$dest" \
        PREFIX_FOR_INCLUDE="$dest/include" \
        PREFIX_FOR_LIB="$dest/lib" \
        PREFIX_FOR_STARTUP="$dest/lib" \
        install-include install-libs install-startup

    log "libcmini installed in $dest"
}

build_gemlib() {
    log "STEP 8/9: gemlib"

    local src="$GEMLIB_SRC_DIR"
    local sysroot="$INSTALL_DIR/$TARGET/sys-root"

    cd "$BUILD_DIR"
    [ -d "$src" ] || tar -xzf "$SOURCES_DIR/gemlib-master.tar.gz"
    cd "$src"

    make -j$JOBS CROSSPREFIX="$TARGET-"
    make install CROSSPREFIX="$TARGET-" PREFIX="$sysroot/usr"
    log "gemlib installed"
}

build_gdb() {
    log "STEP 9/9: GDB"

    local src="$GDB_SRC_DIR"
    local bld="$BUILD_DIR/gdb-14-mintelf.obj"

    cd "$BUILD_DIR"
    [ -d "$src" ] || tar -xzf "$SOURCES_DIR/gdb-14-mintelf.tar.gz"
    mkdir -p "$bld" && cd "$bld"

    ../$src/configure \
        --host=x86_64-pc-linux-gnu \
        --target=$TARGET \
        --enable-targets=x86_64-pc-linux-gnu,m68k-atari-mint \
        --prefix="$INSTALL_DIR" \
        --with-sysroot="$INSTALL_DIR/$TARGET/sys-root" \
        --disable-nls \
        --disable-binutils \
        --disable-gas \
        --disable-gold \
        --disable-ld \
        --disable-sim \
        --disable-gprof \
        --disable-source-highlight \
        --disable-threading \
        --disable-tui \
        --disable-werror \
        --without-curses \
        --without-expat \
        --without-libunwind-ia64 \
        --without-lzma \
        --without-babeltrace \
        --without-intel-pt \
        --without-xxhash \
        --without-python \
        --without-python-libdir \
        --without-debuginfod \
        --without-guile \
        --without-amd-dbgapi \
        --without-system-readline \
        CFLAGS="-O2 -D__LIBC_CUSTOM_BINDINGS_H__" \
        CXXFLAGS="-O2 -D__LIBC_CUSTOM_BINDINGS_H__" \
        LDFLAGS="-s"

    make -j$JOBS all-gdb
    make install-gdb
    log "GDB installed"
}

STEP="${1:-all}"

case "$STEP" in
    all)
        check_deps
        download_sources
        build_binutils
        build_gcc_frontend
        build_mintlib
        build_gcc_libgcc
        build_fdlibm
        build_gcc_finish
        build_libcmini
        build_gemlib
        build_gdb
        log "Done! Toolchain in $INSTALL_DIR  [total time: $(elapsed)]"
        ;;
    download)      download_sources ;;
    binutils)      check_deps; build_binutils ;;
    gcc-frontend)  build_gcc_frontend ;;
    mintlib)       build_mintlib ;;
    gcc-libgcc)    build_gcc_libgcc ;;
    fdlibm)        build_fdlibm ;;
    gcc-finish)    build_gcc_finish ;;
    libcmini)      build_libcmini ;;
    gemlib)        build_gemlib ;;
    gdb)           build_gdb ;;
    *)             die "Unknown step: $STEP. Use: all | download | binutils | gcc-frontend | mintlib | gcc-libgcc | fdlibm | gcc-finish | libcmini | gemlib | gdb" ;;
esac
