#!/bin/sh
set -eu

cache_root="${LOVELY_HELM_CACHE_ROOT:?Lovely invocation cache is not set}"

if [ "$#" -lt 6 ] \
  || [ "$1" != '--registry-config' ] \
  || [ "$2" != '/tmp/.helm/registry.json' ] \
  || [ "$3" != '--repository-cache' ] \
  || [ "$4" != '/tmp/.helm/cache/repository' ] \
  || [ "$5" != '--repository-config' ] \
  || [ "$6" != '/tmp/.helm/repositories.json' ]; then
  printf '%s\n' 'Unexpected Lovely Helm arguments; review the pinned plugin version.' >&2
  exit 2
fi

shift 6
mkdir -p "$cache_root/cache/repository"

exec /usr/local/bin/helm \
  --registry-config "$cache_root/registry.json" \
  --repository-cache "$cache_root/cache/repository" \
  --repository-config "$cache_root/repositories.json" \
  "$@"
