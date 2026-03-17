#!/bin/bash
# Build script for m68k-atari-mintelf cross-toolchain
# Order:
#   binutils->gcc-frontend->mintlib->gcc-libgcc->fdlibm->gcc-finish->libcmini->gemlib → gdb
#
# Usage:
#   ./build-toolchain.sh all
#   ./build-toolchain.sh download
#   ./build-toolchain.sh binutils
#   ./build-toolchain.sh gcc-frontend
#   ./build-toolchain.sh mintlib
#   ./build-toolchain.sh gcc-libgcc
#   ./build-toolchain.sh fdlibm
#   ./build-toolchain.sh gcc-finish
#   ./build-toolchain.sh libcmini
#   ./build-toolchain.sh gdb

set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${INSTALL_DIR:-$HOME/toolchains/cross-mintelf}"
SOURCES_DIR="${SOURCES_DIR:-$SCRIPT_DIR/sources}"
BUILD_DIR="${BUILD_DIR:-$SCRIPT_DIR/obj}"
TARGET="m68k-atari-mintelf"
JOBS="${JOBS:-$(nproc)}"

BINUTILS_VER="2.42"
BINUTILS_PATCH="mintelf-20240218"
GCC_VER="13.2.0"
GCC_PATCH="mintelf-20240130"
MINTLIB_VER="Git-20240114"
FDLIBM_VER="Git-20230207"
GDB_SRC_DIR="m68k-atari-mint-binutils-gdb-gdb-14-mintelf"
LIBCMINI_SRC_DIR="libcmini-master"
GEMLIB_SRC_DIR="gemlib-master"
# ──────────────────────────────────────────────────────────────────────────────

export PATH="$INSTALL_DIR/bin:$PATH"

log() { echo -e "\n\033[1;32m>>> $*\033[0m\n"; }
die() { echo -e "\033[1;31mBŁĄD: $*\033[0m" >&2; exit 1; }

#0. Download
download_sources() {
    log "STEP 0: pobieranie źródeł"
    mkdir -p "$SOURCES_DIR"

    local VR="http://vincent.riviere.free.fr/soft/m68k-atari-mintelf/archives"
    local GNU="https://ftp.gnu.org/gnu"
    local GH="https://github.com"

    dl() {
        local file="$SOURCES_DIR/$1"
        local url="$2"
        if [ -f "$file" ]; then
            echo "OK (już istnieje): $1"
        else
            echo "Pobieranie: $1"
            curl -L --fail -o "$file" "$url"
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

    log "Done src in $SOURCES_DIR"
}

check_deps() {
    log "Check dependencies..."
    local missing=()
    for cmd in gcc g++ make patch tar xz bison flex makeinfo curl; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    for lib in libmpc-dev libmpfr-dev libgmp-dev libzstd-dev libexpat1-dev; do
        dpkg -s "$lib" &>/dev/null 2>&1 || missing+=("$lib")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        echo "Brakuje: ${missing[*]}"
        echo "Zainstaluj: sudo apt install build-essential bison flex texinfo libmpc-dev libmpfr-dev libgmp-dev libzstd-dev libexpat1-dev curl"
        die "Brakujące zależności"
    fi
    echo "OK"
}

# helper: patch GCC (idempotent)
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

#1. BINUTILS
build_binutils() {
    log "STEP 1/8: binutils $BINUTILS_VER"

    local src="binutils-$BINUTILS_VER"
    local patch="binutils-$BINUTILS_VER-$BINUTILS_PATCH"
    local bld="$BUILD_DIR/$patch.obj"

    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"

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
        --with-system-zlib

    make -j$JOBS
    make install

    log "binutils zainstalowane"
}

#2. GCC FRONTEND
# libgcc needs libc header
build_gcc_frontend() {
    log "STEP 2/8: GCC $GCC_VER — frontend (bez libgcc)"

    local patch="gcc-$GCC_VER-$GCC_PATCH"
    local bld="$BUILD_DIR/$patch.obj"

    mkdir -p "$BUILD_DIR"
    _gcc_prepare

    mkdir -p "$bld" && cd "$bld"

    # only once
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
        CFLAGS_FOR_TARGET="-O2 -fomit-frame-pointer" \
        CXXFLAGS_FOR_TARGET="-O2 -fomit-frame-pointer"

    make -j$JOBS all-gcc
    make install-gcc

    log "GCC frontend installed"
}

#3. MINTLIB
build_mintlib() {
    log "STEP 3/8: MiNTLib $MINTLIB_VER"

    local src="mintlib-$MINTLIB_VER"
    local sysroot="$INSTALL_DIR/$TARGET/sys-root"

    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"
    [ -d "$src" ] || tar -xJf "$SOURCES_DIR/mintlib-$MINTLIB_VER.tar.xz"
    cd "$src"

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

#4. FDLIBM (math.h + libm)
build_fdlibm() {
    log "STEP 4/8: FDLIBM $FDLIBM_VER"

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

#5. GCC LIBGCC
build_gcc_libgcc() {
    log "STEP 5/8: GCC $GCC_VER — libgcc (sysroot ma już nagłówki MiNTLib)"

    local patch="gcc-$GCC_VER-$GCC_PATCH"
    local bld="$BUILD_DIR/$patch.obj"

    [ -d "$bld" ] || die "Missing build GCC directiry — first use: gcc-frontend"
    cd "$bld"

    make -j$JOBS all-target-libgcc
    make install-target-libgcc

    log "libgcc installed"
}

#6. GCC FINISH (libstdc++ i reszta)
build_gcc_finish() {
    log "STEP 6/8: GCC $GCC_VER — finish (libstdc++ i reszta)"

    local patch="gcc-$GCC_VER-$GCC_PATCH"
    local bld="$BUILD_DIR/$patch.obj"

    [ -d "$bld" ] || die "Missing build GCC directiry — first use: gcc-frontend"
    cd "$bld"

    make -j$JOBS
    make install

    log "GCC fully installed"
}

#7. LIBCMINI
build_libcmini() {
    log "STEP 7/8: libcmini"

    local src="$LIBCMINI_SRC_DIR"
    local dest="$INSTALL_DIR/libcmini"

    cd "$BUILD_DIR"
    [ -d "$src" ] || tar -xzf "$SOURCES_DIR/libcmini-master.tar.gz"
    cd "$src"

    # Budujemy tylko biblioteki i pliki startowe — pomijamy tests (używają starego m68k-atari-mint-gcc)
    make -j$JOBS CROSSPREFIX="$TARGET-" dirs libs startups

    mkdir -p "$dest/include" "$dest/lib"
    make CROSSPREFIX="$TARGET-" \
        PREFIX="$dest" \
        PREFIX_FOR_INCLUDE="$dest/include" \
        PREFIX_FOR_LIB="$dest/lib" \
        PREFIX_FOR_STARTUP="$dest/lib" \
        install-include install-libs install-startup

    log "libcmini installed $dest"
}

#8. GEMLIB
build_gemlib() {
    log "STEP 8/9: gemlib (GEM headers + library)"

    local src="$GEMLIB_SRC_DIR"
    local sysroot="$INSTALL_DIR/$TARGET/sys-root"

    cd "$BUILD_DIR"
    [ -d "$src" ] || tar -xzf "$SOURCES_DIR/gemlib-master.tar.gz"
    cd "$src"

    make -j$JOBS CROSSPREFIX="$TARGET-"
    make install CROSSPREFIX="$TARGET-" PREFIX="$sysroot/usr"

    log "gemlib installed (gem.h w $sysroot/usr/include)"
}

#9. GDB
build_gdb() {
    log "STEP 9/9: GDB (gdb-14-mintelf)"

    local src="$GDB_SRC_DIR"
    local bld="$BUILD_DIR/gdb-14-mintelf.obj"

    cd "$BUILD_DIR"
    [ -d "$src" ] || tar -xzf "$SOURCES_DIR/gdb-14-mintelf.tar.gz"

    mkdir -p "$bld" && cd "$bld"
    ../$src/configure \
        --target=$TARGET \
        --prefix="$INSTALL_DIR" \
        --disable-nls \
        --with-expat \
        --with-system-zlib \
        --disable-binutils \
        --disable-gas \
        --disable-gold \
        --disable-ld \
        --disable-sim \
        --disable-gprof \
        --disable-werror

    make -j$JOBS all-gdb
    make install-gdb

    log "GDB installed"
}

# MAIN
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
        log "Ready! Toolchain in $INSTALL_DIR"
        ;;
    download)      download_sources ;;
    binutils)      check_deps; build_binutils ;;
    gcc-frontend)  build_gcc_frontend ;;
    mintlib)       build_mintlib ;;
    fdlibm)        build_fdlibm ;;
    gcc-libgcc)    build_gcc_libgcc ;;
    gcc-finish)    build_gcc_finish ;;
    libcmini)      build_libcmini ;;
    gemlib)        build_gemlib ;;
    gdb)           build_gdb ;;
    *)             die "Nieznany STEP: $STEP. use: all | download | binutils | gcc-frontend | mintlib | fdlibm | gcc-libgcc | gcc-finish | libcmini | gemlib | gdb" ;;
esac
