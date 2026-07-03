#!/bin/sh

set -euo pipefail

# =========================================================
# Proton Bridge container entrypoint
#
# First run (empty volumes):
#   1. generates a passphrase-less GPG key + initializes password-store
#   2. generates a SAN-correct TLS cert into /certs
# Every run:
#   3. starts socat relays (LAN -> Bridge loopback)
#   4. runs Bridge CLI kept alive via faketty FIFO
#
# Volumes expected:
#   /root   -> vault, GPG keyring, password store (protonmail-vault)
#   /certs  -> TLS cert + key                     (bridge-certs)
# Env:
#   BRIDGE_LAN_IP -> router LAN IP baked into the cert SAN
# =========================================================

# --- 0. clear stale GnuPG locks (PIDs are reused across container runs, so
#        locks from a previous unclean shutdown look "held") ---
find /root/.gnupg -name '*.lock' -type f -delete 2>/dev/null || true

# --- 1. GPG key + password store: generate only if missing ---
if [ ! -d /root/.password-store ]; then
    echo ">> First run: Generating GPG key for pass..."
    gpg --batch --passphrase '' \
        --quick-generate-key "Proton Bridge" future-default default 0

    echo ">> First run: Initializing password store..."
    pass init "Proton Bridge"
fi

# --- 2. TLS cert: generate into the cert volume only if missing ---
if [ ! -f /certs/cert.pem ]; then
    echo ">> First run: Generating TLS certificate (SAN: ${BRIDGE_LAN_IP:-127.0.0.1})..."
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
        -keyout /certs/key.pem -out /certs/cert.pem -days 36500 -nodes \
        -subj "/CN=bridge.lan" \
        -addext "subjectAltName=IP:${BRIDGE_LAN_IP:-127.0.0.1},DNS:bridge.lan,IP:127.0.0.1,DNS:localhost" \
        -addext "basicConstraints=critical,CA:FALSE" \
        -addext "keyUsage=critical,digitalSignature,keyEncipherment" \
        -addext "extendedKeyUsage=serverAuth"
    chmod 600 /certs/key.pem
fi

# --- 3. socat relays: LAN-facing ports -> Bridge's loopback ports ---
# Real ports (143/25) inside the container avoid colliding with
# Bridge's own defaults (1143/1025), which would push Bridge to
# auto-increment to 1144/1026 and break the relay.
socat TCP-LISTEN:143,fork,reuseaddr TCP:127.0.0.1:1143 &
socat TCP-LISTEN:25,fork,reuseaddr TCP:127.0.0.1:1025 &

# --- 4. Bridge CLI, kept alive by the FIFO (never sees stdin EOF) ---
if [ -t 0 ]; then
    # Interactive run (-it): real TTY, use it directly for setup sessions
    exec proton-bridge --cli "$@"
else
    # Detached run (-d): keep CLI alive via FIFO, never sees EOF
    rm -f /tmp/faketty
    mkfifo /tmp/faketty
    exec sh -c 'cat /tmp/faketty | proton-bridge --cli "$@"' -- "$@"
fi
