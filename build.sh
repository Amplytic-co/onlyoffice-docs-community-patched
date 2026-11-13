#!/usr/bin/env bash
# Builds a patched ONLYOFFICE Docs Community image.
# Run on a Linux x86_64 host with Docker, >= 8 vCPU and ~100 GB free disk.
#
#   WORK_DIR=$HOME/oo-fork ./build.sh
#
# Re-running reuses WORK_DIR, so an interrupted build resumes.
set -euo pipefail

OO_TAG="${OO_TAG:-v10.0.0.169}"
PRODUCT_VERSION="${PRODUCT_VERSION:-10.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-169}"
PKG_TARGET="${PKG_TARGET:-node24}"
PKG_VERSION="${PKG_VERSION:-6.25.0}"
BROTLI_SHA="${BROTLI_SHA:-db24a98aed38a16de78cc05ca15cdd8dc2a0d92d}"
DEPOT_TOOLS_SHA="${DEPOT_TOOLS_SHA:-a03dfbf7f2d1cefa2795d81d59ca4f16c8616a8f}"
# Docker-DocumentServer tags its release Dockerfile like the source repos; its
# master at release time is a different, multi-stage file that ships nginx's
# default site and a broken Document Server.
DOCKER_DS_REF="${DOCKER_DS_REF:-$OO_TAG}"
IMAGE="${IMAGE:-amplytic/onlyoffice-documentserver:${PRODUCT_VERSION}.${BUILD_NUMBER}-amp2495}"
WORK_DIR="${WORK_DIR:?set WORK_DIR to a directory with ~100 GB free}"
DEB_PORT="${DEB_PORT:-8099}"

here="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$WORK_DIR"
export OO_TAG PKG_TARGET PKG_VERSION BROTLI_SHA DEPOT_TOOLS_SHA PRODUCT_VERSION BUILD_NUMBER

find_deb() {
  find "$WORK_DIR/document-server-package" -name "onlyoffice-documentserver_${PRODUCT_VERSION}-${BUILD_NUMBER}_amd64.deb" 2>/dev/null | head -1
}

if [ -z "$(find_deb)" ] || [ "${REBUILD:-0}" = 1 ]; then
  docker run --rm -v "$WORK_DIR:/w" -v "$here/build-in-container.sh:/build-in-container.sh:ro" \
    -e OO_TAG -e PKG_TARGET -e PKG_VERSION -e BROTLI_SHA -e DEPOT_TOOLS_SHA -e PRODUCT_VERSION -e BUILD_NUMBER \
    ubuntu:24.04 bash /build-in-container.sh
fi

deb="$(find_deb)"
[ -n "$deb" ] || { echo "no .deb produced" >&2; exit 1; }

ds="$WORK_DIR/Docker-DocumentServer"
[ -d "$ds" ] || git clone -q https://github.com/ONLYOFFICE/Docker-DocumentServer.git "$ds"
git -C "$ds" fetch -q --tags
git -C "$ds" checkout -q "$DOCKER_DS_REF"

python3 -m http.server "$DEB_PORT" --bind 127.0.0.1 --directory "$(dirname "$deb")" >/dev/null 2>&1 &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true' EXIT

docker build --network host -t "$IMAGE" \
  --build-arg PACKAGE_BASEURL="http://127.0.0.1:$DEB_PORT" \
  --build-arg PACKAGE_VERSION="${PRODUCT_VERSION}-${BUILD_NUMBER}" \
  --label "co.amplytic.amp2495.onlyoffice-tag=$OO_TAG" \
  --label "co.amplytic.amp2495.pkg-target=$PKG_TARGET" \
  --label "co.amplytic.amp2495.pkg-version=$PKG_VERSION" \
  --label "co.amplytic.amp2495.brotli=$BROTLI_SHA" \
  --label "co.amplytic.amp2495.docker-ds=$(git -C "$ds" rev-parse HEAD)" \
  "$ds"

cp "$WORK_DIR/provenance.txt" "$WORK_DIR/provenance-$(date -u +%Y%m%dT%H%M%SZ).txt"
"$here/verify.sh" "$IMAGE"
