#!/usr/bin/env sh
set -eu

: "${PORT:=8080}"
: "${FLIPT_UPSTREAM_HOST:=flipt.railway.internal}"
: "${FLIPT_UPSTREAM_PORT:=9000}"

sed -e "s|@PORT@|${PORT}|g" \
    -e "s|@FLIPT_UPSTREAM_HOST@|${FLIPT_UPSTREAM_HOST}|g" \
    -e "s|@FLIPT_UPSTREAM_PORT@|${FLIPT_UPSTREAM_PORT}|g" \
    /etc/envoy/envoy.yaml.tmpl > /etc/envoy/envoy.yaml

exec /docker-entrypoint.sh "$@"
