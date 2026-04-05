FROM golang:1.20 AS builder

WORKDIR /tmp/torrentino

ADD https://github.com/rodiontsev/torrentino.git .

RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -o torrentino

FROM debian:trixie-slim

ARG PUID
ARG PGID

ENV DEBIAN_FRONTEND=noninteractive

COPY --from=builder /tmp/torrentino/torrentino /usr/local/bin/torrentino

## Install packages
RUN apt-get update \
    && apt-get install --no-install-recommends -y \
        adduser \
        ca-certificates \
        tini \
##
## Create torrentino user
    && addgroup --gid ${PGID} torrentino \
    && adduser --uid ${PUID} --gid ${PGID} --disabled-login --disabled-password --comment "" --no-create-home torrentino \
    && chmod +x /usr/local/bin/torrentino \
##
## Clean up
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /var/tmp/* \
    && rm -rf /tmp/*

## Run as torrentino user
USER torrentino

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/usr/local/bin/torrentino"]