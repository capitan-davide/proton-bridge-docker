FROM alpine:latest AS build

RUN apk add --no-cache bash binutils go make pkgconf libcbor-dev libfido2-dev libsecret-dev

WORKDIR /root

ADD https://github.com/ProtonMail/proton-bridge/archive/refs/tags/v3.25.0.tar.gz /root

RUN tar xf v3.25.0.tar.gz && cd proton-bridge-3.25.0 && make build-nogui && strip bridge proton-bridge

FROM alpine:latest

ENV BRIDGE_LAN_IP=127.0.0.1

RUN apk add --no-cache ca-certificates gpg gpg-agent libfido2 libsecret openssl pass socat

COPY --from=build /root/proton-bridge-3.25.0/bridge /usr/bin
COPY --from=build /root/proton-bridge-3.25.0/proton-bridge /usr/bin

WORKDIR /root

COPY entrypoint.sh /usr/local/bin
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
