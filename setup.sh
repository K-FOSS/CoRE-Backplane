#!/bin/sh

set -eu

# Download a small, reviewed set of repository tools. Versions and checksums are
# intentionally fixed; update both together after reviewing the upstream release.
MQTTX_VERSION=1.11.1
EGCTL_VERSION=1.9.3
TALOSCTL_VERSION=1.14.5
ARGOCD_VERSION=3.5.7
LONGHORNCTL_VERSION=1.13.0
CROSSPLANE_VERSION=2.3.3

MQTTX_SHA256=c8f5560e48e28247a4a158a48ade4dfd6a7ed8ae31148edae29a6aeb7ff8e360
EGCTL_SHA256=82b6164a6cd966fcb6e244a5931c6c3e46193816714a0b69043db1606098150f
TALOSCTL_SHA256=ff432b68986709e6b69c563a08a2ced4232d5196b0dccd6d2e783e9d714d7d7d
ARGOCD_SHA256=e9b7c3f5316b8546bdd499dfb8d874e413a5e3605899a55ec2ce0b668a3e2801
LONGHORNCTL_SHA256=2354ec1b9ff058fa4b7e178451d3445959cd4b6406317d7778b637f0314e1051
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
