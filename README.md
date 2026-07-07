# proton-bridge-docker

Headless [Proton Mail Bridge](https://proton.me/mail/bridge), built from source
(no GUI/Qt), running in a minimal Alpine container. Designed for routers/servers
(e.g., OpenWrt on aarch64) so LAN clients can use Proton Mail over plain
IMAP/SMTP.

## How it works

- **Dockerfile** — multi-stage build: compiles the Proton Bridge with
  `make build-nogui`, ships only the stripped binaries plus runtime deps.
- **entrypoint.sh** — on first run, initializes a passphrase-less GPG key +
  password-store and generates a TLS cert with a SAN for your LAN IP. On every
  run, starts `socat` relays (container ports `143`/`25` -> Bridge's
  loopback-only `1143`/`1025`) and keeps the Bridge CLI alive via a FIFO.

State lives in two volumes: `/root` (vault, keyring, password-store) and
`/certs` (TLS cert + key).

A `compose.yaml` is included for running the Bridge as a daemon; it reuses the
existing named volumes (declared `external`), so it can take over from a
container previously started with `docker run` without losing the session.

## Usage

Build:

```sh
docker build -t proton-bridge .
```

One-time setup (interactive: `login`, then `cert import` with `/certs/cert.pem`
and `/certs/key.pem`):

```sh
docker run --rm -it \
  -e BRIDGE_LAN_IP=192.168.2.1 \
  -v proton-bridge-data:/root \
  -v proton-bridge-certs:/certs \
  proton-bridge
```

Run as daemon (Compose, recommended):

```sh
docker compose up -d
```

The provided `compose.yaml` expects the `proton-bridge-data` and
`proton-bridge-certs` volumes to already exist (they are created by the
one-time setup above). If a container named `proton-bridge` from a previous
`docker run` is still around, remove it first: `docker rm -f proton-bridge`.

Equivalent plain `docker run`:

```sh
docker run -d --name proton-bridge \
  -e BRIDGE_LAN_IP=192.168.2.1 \
  -p 1143:143 -p 1025:25 \
  -v proton-bridge-data:/root \
  -v proton-bridge-certs:/certs \
  --restart=unless-stopped \
  proton-bridge
```

Clients connect to `<host-ip>:1143` (IMAP) / `<host-ip>:1025` (SMTP) with
STARTTLS, using the credentials shown by the `info` command in the Bridge CLI.

## Notes

- `BRIDGE_LAN_IP` is only read on first run, when the cert is generated.
- Injecting commands into the detached CLI:
  `docker exec proton-bridge sh -c 'printf "info\n" > /tmp/faketty'`
- Requires a paid Proton Mail plan.
