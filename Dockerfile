FROM debian:bookworm-slim AS builder
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential bison flex texinfo \
    libmpc-dev libmpfr-dev libgmp-dev \
    libzstd-dev libexpat1-dev zlib1g-dev \
    xz-utils curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY /scripts/build-toolchain.sh /build/

ENV INSTALL_DIR=/opt/cross-mintelf \
    SOURCES_DIR=/build/sources \
    BUILD_DIR=/build/obj \
    JOBS=4

RUN chmod +x /build/build-toolchain.sh && /build/build-toolchain.sh all

FROM debian:bookworm-slim
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    make \
    libmpc3 libmpfr6 libgmp10 \
    libzstd1 libexpat1 \
    hatari \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /opt/cross-mintelf /opt/cross-mintelf
COPY /hatari/* /opt/hatari/
ENV PATH="/opt/cross-mintelf/bin:$PATH"

WORKDIR /workspace
