# Build environment for PocketBook InkView applications.
#
# Uses Debian's stock ARM cross compilers (GCC 12, glibc 2.36). The resulting
# binaries only reference glibc symbol versions <= 2.36 and therefore run on
# any newer firmware libc (6.x firmwares ship glibc 2.3x-2.41).
FROM debian:bookworm-slim

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        binutils-arm-linux-gnueabi \
        binutils-arm-linux-gnueabihf \
        ca-certificates \
        cmake \
        file \
        g++-arm-linux-gnueabi \
        g++-arm-linux-gnueabihf \
        gcc-arm-linux-gnueabi \
        gcc-arm-linux-gnueabihf \
        git \
        make \
        ninja-build \
        pkg-config && \
    rm -rf /var/lib/apt/lists/*

# inkview.h includes <zlib.h>. Extract just the zlib headers for each ABI
# rather than co-installing two foreign dpkg architectures (which conflicts).
RUN dpkg --add-architecture armel && \
    dpkg --add-architecture armhf && \
    apt-get update && \
    cd /tmp && apt-get download zlib1g-dev:armel zlib1g-dev:armhf && \
    for pair in armel:arm-linux-gnueabi armhf:arm-linux-gnueabihf; do \
        arch=${pair%%:*}; triple=${pair#*:}; \
        dpkg -x zlib1g-dev_*_${arch}.deb /tmp/z && \
        cp /tmp/z/usr/include/zlib.h /tmp/z/usr/include/zconf.h /usr/${triple}/include/ && \
        rm -rf /tmp/z || exit 1; \
    done && \
    rm -f /tmp/*.deb && rm -rf /var/lib/apt/lists/*

WORKDIR /src
