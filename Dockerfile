FROM ubuntu:bionic as build

ARG VERSION="1.17.0"
ARG REQUIRED_PACKAGES="libgflags2.2"

ENV ROOTFS /build/rootfs
ENV BUILD_DEBS /build/debs
ENV DEBIAN_FRONTEND=noninteractive
ENV APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=true

SHELL ["bash", "-ec"]

# Build pre-requisites
RUN mkdir -p ${BUILD_DEBS} ${ROOTFS}/{opt,sbin,usr/bin,usr/local/bin,opt/grpc}

# Fix permissions
RUN chown -Rv 100:root $BUILD_DEBS

# Install pre-requisites
RUN apt-get update \
        && apt-get -y install apt-utils git build-essential autoconf libtool pkg-config libgflags-dev curl gpg ca-certificates

# Unpack required packges to rootfs
RUN set -Eeuo pipefail; \
    cd ${BUILD_DEBS} \
      && for pkg in $REQUIRED_PACKAGES; do \
           apt-get download $pkg \
              && apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances --no-pre-depends -i $pkg | grep '^[a-zA-Z0-9]' | xargs apt-get download ; \
         done; \
         if [ "x$(ls ${BUILD_DEBS}/)" = "x" ]; then \
           echo No required packages specified; \
         else \
           for pkg in ${BUILD_DEBS}/*.deb; do \
             echo Unpacking $pkg; \
             dpkg-deb -X $pkg ${ROOTFS}; \
           done; \
         fi

RUN git clone -b v${VERSION} --depth 50 https://github.com/grpc/grpc \
      && cd grpc \
      && git submodule update --init --recursive \
      && make grpc_cli \
      && find bins -executable -type f -exec cp "{}" ${ROOTFS}/opt/grpc \; \
      && cd ${ROOTFS}/opt/grpc \
      && for grpcbin in *; do \
           ln -s /opt/grpc/$grpcbin ${ROOTFS}/usr/bin/$grpcbin; \
         done

# Move /sbin out of the way
RUN mv ${ROOTFS}/sbin ${ROOTFS}/sbin.orig \
      && mkdir -p ${ROOTFS}/sbin \
      && for b in ${ROOTFS}/sbin.orig/*; do \
           echo 'cmd=$(basename ${BASH_SOURCE[0]}); exec /sbin.orig/$cmd "$@"' > ${ROOTFS}/sbin/$(basename $b); \
           chmod +x ${ROOTFS}/sbin/$(basename $b); \
         done

COPY entrypoint.sh ${ROOTFS}/usr/local/bin/entrypoint.sh
RUN chmod +x ${ROOTFS}/usr/local/bin/entrypoint.sh

FROM actions/bash:4.4.18-8
LABEL maintainer = "ilja+docker@bobkevic.com"

ARG ROOTFS=/build/rootfs

ENV LC_ALL=C.UTF-8
ENV LANG=C.UTF-8

COPY --from=build ${ROOTFS} /

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]