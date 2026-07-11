FROM alpine:3.24 AS build

ARG BRIDGE_VERSION=3.25.0

RUN apk add --no-cache bash binutils go make pkgconf libcbor-dev libfido2-dev libsecret-dev

WORKDIR /root

ADD https://github.com/ProtonMail/proton-bridge/archive/refs/tags/v${BRIDGE_VERSION}.tar.gz /root

RUN tar xf v${BRIDGE_VERSION}.tar.gz && cd proton-bridge-${BRIDGE_VERSION} && make build-nogui && strip bridge proton-bridge

FROM alpine:3.24

ARG BRIDGE_VERSION
ENV BRIDGE_LAN_IP=127.0.0.1

RUN apk add --no-cache ca-certificates gpg gpg-agent libfido2 libsecret openssl pass socat

COPY --from=build /root/proton-bridge-${BRIDGE_VERSION}/bridge /usr/bin
COPY --from=build /root/proton-bridge-${BRIDGE_VERSION}/proton-bridge /usr/bin

WORKDIR /root

COPY entrypoint.sh /usr/local/bin
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
