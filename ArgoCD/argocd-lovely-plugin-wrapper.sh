#!/bin/sh
set -eu

cache_root="$(mktemp -d /tmp/helm-cache.XXXXXX)"
trap 'rm -rf "$cache_root"' EXIT
export LOVELY_HELM_CACHE_ROOT="$cache_root"

/usr/local/bin/argocd-lovely-plugin "$@"
