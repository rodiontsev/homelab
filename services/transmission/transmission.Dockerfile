## Build image
FROM debian:trixie-slim AS builder

#ARG TRANSMISSION_VERSION=4.1.1

ENV DEBIAN_FRONTEND=noninteractive

WORKDIR /tmp/transmission

ADD https://github.com/transmission/transmission/releases/download/4.1.1/transmission-4.1.1.tar.xz .

## Install packages
RUN apt-get update \
    && apt-get install --no-install-recommends -y \
        build-essential \
        cmake \
        libb64-dev \
        libcurl4-openssl-dev \
        libdeflate-dev \
        libevent-dev \
        libminiupnpc-dev \
        libnatpmp-dev \
        libpsl-dev \
        libssl-dev \
        libsystemd-dev \
        xz-utils \
##
## Extract the archive
    && tar -Jxpf transmission-4.1.1.tar.xz \
    && cd transmission-4.1.1 \
## 
## Build Transmission Daemon
## Make some tea - Raspberry Pi Model B takes about 5 hours to complete a build.
## Raspberry Pi 4 Model B builds in 30 minutes, so there is still time for a cup of tea.
    && cmake -B build -DCMAKE_BUILD_TYPE=Release \
        -DENABLE_DAEMON=ON \
        -DENABLE_UTILS=ON \
        -DENABLE_CLI=OFF \
        -DENABLE_GTK=OFF \
        -DENABLE_QT=OFF \
        -DENABLE_TESTS=OFF \
        -DINSTALL_DOC=OFF \
    && cmake --build build \
    && cmake --install build \
##
## Clean up
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /var/tmp/* \
    && rm -rf /tmp/*

## Transmission image
FROM debian:trixie-slim

ARG PUID
ARG PGID

ENV DEBIAN_FRONTEND=noninteractive
ENV TRANSMISSION_HOME=/home/transmission/config
ENV TRANSMISSION_WEB_HOME=/usr/local/share/transmission/web

# Copy transmission daemon
COPY --from=builder /usr/local/bin/transmission-daemon /usr/local/bin/transmission-daemon

# Copy transmission utils
COPY --from=builder /usr/local/bin/transmission-remote /usr/local/bin/transmission-remote
COPY --from=builder /usr/local/bin/transmission-create /usr/local/bin/transmission-create
COPY --from=builder /usr/local/bin/transmission-edit /usr/local/bin/transmission-edit
COPY --from=builder /usr/local/bin/transmission-show /usr/local/bin/transmission-show

# Copy web interface
COPY --from=builder /usr/local/share/transmission/public_html /usr/local/share/transmission/web

WORKDIR /home/transmission

## Install packages
RUN apt-get update \
    && apt-get install --no-install-recommends -y \
        adduser \
        ca-certificates \
        curl \
        libb64-0d \
        libcurl4 \
        libdeflate0 \
        libevent-2.1-7 \
        libminiupnpc18 \
        libnatpmp1 \
        libpsl5 \
        tini \
##
## Create transmission user
    && addgroup --gid ${PGID} transmission \
    && adduser --uid ${PUID} --gid ${PGID} --disabled-login --disabled-password --comment "" --home /home/transmission transmission \
    && mkdir -p \
        config \
        downloads \
        incomplete \
        scripts \
        watch \
    && chown -R ${PUID}:${PGID} /home/transmission \
##
## Clean up
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /var/tmp/* \
    && rm -rf /tmp/*

## Run as transmission user
USER transmission

VOLUME /home/transmission/config
VOLUME /home/transmission/downloads
VOLUME /home/transmission/incomplete
VOLUME /home/transmission/scripts
VOLUME /home/transmission/watch

EXPOSE 9091
EXPOSE 51413 51413/udp

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/usr/local/bin/transmission-daemon", "-f"]
