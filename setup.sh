#!/bin/sh

set -eu

# Download a small, reviewed set of repository tools. Versions and checksums are
# intentionally fixed; update both together after reviewing the upstream release.
MQTTX_VERSION=1.11.1
MC_VERSION=RELEASE.2025-08-13T08-35-41Z
EGCTL_VERSION=1.8.3
TALOSCTL_VERSION=1.13.6
ARGOCD_VERSION=3.4.5
LONGHORNCTL_VERSION=1.8.1
CROSSPLANE_VERSION=2.3.3

MQTTX_SHA256=c8f5560e48e28247a4a158a48ade4dfd6a7ed8ae31148edae29a6aeb7ff8e360
MC_SHA256=01f866e9c5f9b87c2b09116fa5d7c06695b106242d829a8bb32990c00312e891
EGCTL_SHA256=e8728c60455ad120290e32cc7ea95e98000fe225fbbd5bf8f377f42ec19d97c5
TALOSCTL_SHA256=540c5e7cb0d3fa3a9b2e1c717ced212727b73bcaf0cf9cf9ba2472ec381041d4
ARGOCD_SHA256=23303f05a58c1e041324d5645b0f9d6ea338b16bbf32f4a24508f388fcf9f9c0
LONGHORNCTL_SHA256=10f39809b1991920b052c5e6f3843f4595a21fc352e6e98d2be9a5dc9b925a11
CROSSPLANE_SHA256=fa2b4c15356677d38053f5821662045d6c1ecc00f39b148dfc4aacbf6e0b4721

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
BIN_DIR=${BIN_DIR:-"$SCRIPT_DIR/Meta/bin"}
TEMP_DIR=

cleanup() {
    if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
        rm -rf -- "$TEMP_DIR"
    fi
}
trap cleanup EXIT HUP INT TERM

fail() {
    printf 'setup.sh: %s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

verify_file() {
    file=$1
    expected=$2
    actual=$(sha256sum "$file" | awk '{print $1}')
    [ "$actual" = "$expected" ] || fail "checksum mismatch for $(basename -- "$file")"
}

download() {
    name=$1
    url=$2
    expected=$3
    destination=$4
    temporary="$TEMP_DIR/$name.download"

    printf 'Downloading %s\n' "$name"
    wget --https-only --secure-protocol=TLSv1_2 --timeout=30 --tries=3 \
        --output-document="$temporary" "$url"
    verify_file "$temporary" "$expected"
    chmod 0755 "$temporary"
    mv -f -- "$temporary" "$destination"
}

require_command awk
require_command mktemp
require_command sha256sum
require_command tar
require_command wget

[ "$(uname -s)" = Linux ] || fail 'only Linux is currently supported'
case $(uname -m) in
    x86_64 | amd64) ;;
    *) fail "unsupported architecture: $(uname -m) (only amd64 is currently pinned)" ;;
esac

mkdir -p -- "$BIN_DIR"
TEMP_DIR=$(mktemp -d "$BIN_DIR/.setup.XXXXXX")

download mqttx \
    "https://www.emqx.com/en/downloads/MQTTX/v${MQTTX_VERSION}/mqttx-cli-linux-x64" \
    "$MQTTX_SHA256" "$BIN_DIR/mqttx"

download mc \
    "https://dl.min.io/client/mc/release/linux-amd64/archive/mc.${MC_VERSION}" \
    "$MC_SHA256" "$BIN_DIR/mc"

printf 'Downloading egctl\n'
egctl_archive="$TEMP_DIR/egctl.tar.gz"
wget --https-only --secure-protocol=TLSv1_2 --timeout=30 --tries=3 \
    --output-document="$egctl_archive" \
    "https://github.com/envoyproxy/gateway/releases/download/v${EGCTL_VERSION}/egctl_v${EGCTL_VERSION}_linux_amd64.tar.gz"

# Reject absolute paths and parent traversal before reading the archive.
egctl_members=$(tar -tzf "$egctl_archive")
printf '%s\n' "$egctl_members" | awk '
    /^\// || /(^|\/)\.\.($|\/)/ { unsafe = 1 }
    END { exit unsafe }
' || fail 'egctl archive contains an unsafe path'
egctl_member=$(printf '%s\n' "$egctl_members" | awk '/(^|\/)egctl$/ { print }')
[ "$(printf '%s\n' "$egctl_member" | awk 'NF { count++ } END { print count + 0 }')" -eq 1 ] ||
    fail 'egctl archive must contain exactly one egctl binary'
egctl_binary="$TEMP_DIR/egctl.download"
tar -xOzf "$egctl_archive" -- "$egctl_member" >"$egctl_binary"
verify_file "$egctl_binary" "$EGCTL_SHA256"
chmod 0755 "$egctl_binary"
mv -f -- "$egctl_binary" "$BIN_DIR/egctl"

download talosctl \
    "https://github.com/siderolabs/talos/releases/download/v${TALOSCTL_VERSION}/talosctl-linux-amd64" \
    "$TALOSCTL_SHA256" "$BIN_DIR/talosctl"

download argocd \
    "https://github.com/argoproj/argo-cd/releases/download/v${ARGOCD_VERSION}/argocd-linux-amd64" \
    "$ARGOCD_SHA256" "$BIN_DIR/argocd"

download longhornctl \
    "https://github.com/longhorn/cli/releases/download/v${LONGHORNCTL_VERSION}/longhornctl-linux-amd64" \
    "$LONGHORNCTL_SHA256" "$BIN_DIR/longhornctl"

download crossplane \
    "https://releases.crossplane.io/v${CROSSPLANE_VERSION}/bin/linux_amd64/crank" \
    "$CROSSPLANE_SHA256" "$BIN_DIR/crossplane"

printf 'Installed tools in %s\n' "$BIN_DIR"
