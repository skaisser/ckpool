# ckpool container image
#
# Build:  docker build -t ckpool .
# Run:    docker run -v /path/to/ckpool.conf:/etc/ckpool/ckpool.conf:ro \
#                    -p 3333:3333 ckpool
#
# The pool reads /etc/ckpool/ckpool.conf by default. Pass any other ckpool
# options after the image name, e.g. `docker run ... ckpool -B` for solo mode.

FROM ubuntu:24.04 AS build

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        build-essential autoconf automake libtool pkg-config \
        libssl-dev libjansson-dev libzmq3-dev ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /src
COPY . .
RUN ./autogen.sh && ./configure && make -j"$(nproc)" && \
    install -m 0755 src/ckpool src/ckpmsg src/notifier /usr/local/bin/

FROM ubuntu:24.04

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        libzmq5 ca-certificates && \
    rm -rf /var/lib/apt/lists/* && \
    useradd --system --create-home --home-dir /var/lib/ckpool ckpool && \
    mkdir -p /etc/ckpool /var/log/ckpool && \
    chown ckpool:ckpool /var/log/ckpool

COPY --from=build /usr/local/bin/ckpool /usr/local/bin/ckpmsg /usr/local/bin/notifier /usr/local/bin/
COPY ckpool.conf /etc/ckpool/ckpool.conf.example

USER ckpool
WORKDIR /var/lib/ckpool
EXPOSE 3333

ENTRYPOINT ["ckpool", "-c", "/etc/ckpool/ckpool.conf"]
