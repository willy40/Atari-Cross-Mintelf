FROM debian:bookworm-slim AS builder
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential bison flex texinfo \
    libmpc-dev libmpfr-dev libgmp-dev \
    libzstd-dev zlib1g-dev \
    xz-utils curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY /scripts/build-toolchain.sh /build/

ENV INSTALL_DIR=/opt/cross-mintelf \
    SOURCES_DIR=/build/sources \
    BUILD_DIR=/build/obj \
    JOBS=4

RUN chmod +x /build/build-toolchain.sh && /build/build-toolchain.sh all

# Remove unused tools before copying to final stage
RUN GCC_LIB=/opt/cross-mintelf/libexec/gcc/m68k-atari-mintelf/13.2.0 && \
    rm -f  /opt/cross-mintelf/bin/m68k-atari-mintelf-lto-dump \
           /opt/cross-mintelf/bin/m68k-atari-mintelf-gprof \
           /opt/cross-mintelf/bin/m68k-atari-mintelf-gcov \
           /opt/cross-mintelf/bin/m68k-atari-mintelf-gcov-tool \
           /opt/cross-mintelf/bin/m68k-atari-mintelf-gcov-dump \
           $GCC_LIB/lto1 \
           $GCC_LIB/lto-wrapper && \
    rm -rf $GCC_LIB/plugin \
           $GCC_LIB/install-tools \
           /opt/cross-mintelf/share/info \
           /opt/cross-mintelf/share/man && \
    find /opt/cross-mintelf -name "*.la" -delete && \
    find /opt/cross-mintelf/bin -type f | xargs strip --strip-unneeded 2>/dev/null || true && \
    find /opt/cross-mintelf/libexec -type f | xargs strip --strip-unneeded 2>/dev/null || true && \
    find /opt/cross-mintelf -name "*.so*" -type f | xargs strip --strip-unneeded 2>/dev/null || true && \
    find /opt/cross-mintelf -name "*.a" | xargs strip --strip-debug 2>/dev/null || true

FROM debian:bookworm-slim
ENV DEBIAN_FRONTEND=noninteractive

# GCC runtime libs + SDL2/X11 for custom Hatari binary (replaces heavy hatari package)
RUN apt-get update && apt-get install -y --no-install-recommends \
    make \
    libmpc3 libmpfr6 libgmp10 \
    libzstd1 zlib1g \
    libsdl2-2.0-0 libpng16-16 libudev1 libx11-6 libreadline8 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /opt/cross-mintelf /opt/cross-mintelf
COPY /hatari/* /opt/hatari/
ENV PATH="/opt/cross-mintelf/bin:$PATH"

WORKDIR /workspace
