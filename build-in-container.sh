#!/usr/bin/env bash
# Runs inside ubuntu:24.04 with the work directory mounted at /w.
# Builds ONLYOFFICE Docs Community at OO_TAG with the patches in this repository and
# packages it as a .deb under /w/document-server-package/deb.
set -euo pipefail

: "${OO_TAG:?}" "${PKG_TARGET:?}" "${PKG_VERSION:?}" "${BROTLI_SHA:?}" "${DEPOT_TOOLS_SHA:?}" "${PRODUCT_VERSION:?}" "${BUILD_NUMBER:?}"
OLD_BROTLI_SHA=a47d7475063eb223c87632eed806c0070e70da29
export DEBIAN_FRONTEND=noninteractive TZ=Etc/UTC

apt-get -qq update
apt-get -qq install -y sudo python3 python3-setuptools git tar wget curl ca-certificates m4 debhelper fakeroot dpkg-dev >/dev/null
# change_bootstrap pins depot_tools' own Python to 3.8, which fetch.py no
# longer runs on; upstream already uses the system Python on macOS for this.
# The system 3.12 needs python3-setuptools for fetch.py's distutils import.
# DEPOT_TOOLS_UPDATE=0 stops depot_tools moving off DEPOT_TOOLS_SHA.
export DEPOT_TOOLS_BOOTSTRAP_PYTHON3=0 DEPOT_TOOLS_UPDATE=0

cd /w
if [ ! -d build_tools ]; then
  git clone -q --depth 1 --branch "$OO_TAG" https://github.com/ONLYOFFICE/build_tools.git
fi
cd build_tools
sed -i "s/pkg_target = \"node20\"/pkg_target = \"$PKG_TARGET\"/" scripts/build_server.py
grep -q "pkg_target = \"$PKG_TARGET\"" scripts/build_server.py || { echo "pkg_target patch did not apply" >&2; exit 1; }
# v8_89.py clones depot_tools at HEAD, and its bootstrap patch no longer fits
# HEAD (CIPD v2.10, 27 Oct 2026); pin it to the tree of the 10.0.0 release.
v8_py=scripts/core_common/modules/v8_89.py
if ! grep -q "$DEPOT_TOOLS_SHA" "$v8_py"; then
  sed -i "/chromium\/tools\/depot_tools.git\"\])/a\\    base.cmd_in_dir(\"depot_tools\", \"git\", [\"checkout\", \"-q\", \"$DEPOT_TOOLS_SHA\"])" "$v8_py"
fi
grep -q "\"checkout\", \"-q\", \"$DEPOT_TOOLS_SHA\"" "$v8_py" || { echo "depot_tools pin did not apply" >&2; exit 1; }

cd tools/linux
[ -d python3 ] || ./python.sh
# The container is fresh on every run, so system packages are reinstalled;
# deps.py returns early while an earlier run's packages_complete exists.
rm -f packages_complete
./python3/bin/python3 ./deps.py
./cmake.sh
# pkg picks the embedded Node.js from its pkg-fetch release: the upstream pin
# 6.11.0 maps node24 to v24.12.0; 6.25.0 (pkg-fetch 3.6.7) maps it to v24.22.1.
npm install -g "@yao-pkg/pkg@$PKG_VERSION" >/dev/null
[ "$(pkg --version)" = "$PKG_VERSION" ] || { echo "pkg $PKG_VERSION not installed" >&2; exit 1; }
[ -d qt_build ] || ./python3/bin/python3 ./qt_binary_fetch.py all
[ -d sysroot/ubuntu16-amd64-sysroot ] || (cd sysroot && ../python3/bin/python3 ./fetch.py all)
cd ../..

PY=./tools/linux/python3/bin/python
CONF=(--branch "tags/$OO_TAG" --module server --sysroot 1 --platform linux_64
      --qt-dir "$PWD/tools/linux/qt_build/Qt-5.9.9")

"$PY" ./configure.py "${CONF[@]}" --update 1
"$PY" -c "import sys; sys.path[:0] = ['scripts']; import config, base; config.parse(); config.parse_defaults(); base.update_repositories(base.get_repositories())"
[ -d /w/document-server-package ] || git clone -q --branch "$OO_TAG" https://github.com/ONLYOFFICE/document-server-package.git /w/document-server-package

# git_update silently falls back to master when a tag is missing, so every
# repository that publishes the tag must sit exactly on it.
: > /w/provenance.txt
for repo in /w/*/; do
  [ -d "$repo/.git" ] || continue
  name=$(basename "$repo")
  head=$(git -C "$repo" rev-parse HEAD)
  if git -C "$repo" rev-parse -q --verify "refs/tags/$OO_TAG^{commit}" >/dev/null; then
    want=$(git -C "$repo" rev-parse "refs/tags/$OO_TAG^{commit}")
    [ "$head" = "$want" ] || { echo "$name is at $head, not $OO_TAG ($want)" >&2; exit 1; }
    echo "$name $head $OO_TAG" >> /w/provenance.txt
  else
    echo "$name $head untagged" >> /w/provenance.txt
  fi
done

v8_dir=/w/core/Common/3dParty/v8_89
if [ -d "$v8_dir/depot_tools" ] && [ "$(git -C "$v8_dir/depot_tools" rev-parse HEAD)" != "$DEPOT_TOOLS_SHA" ]; then
  rm -rf "$v8_dir"
fi

brotli_make=/w/core/Common/3dParty/brotli/make.py
sed -i "s/$OLD_BROTLI_SHA/$BROTLI_SHA/; s/check_module_version(\"1\"/check_module_version(\"2\"/" "$brotli_make"
grep -q "$BROTLI_SHA" "$brotli_make" || { echo "brotli patch did not apply" >&2; exit 1; }

"$PY" ./configure.py "${CONF[@]}" --update 0
PRODUCT_VERSION="$PRODUCT_VERSION" BUILD_NUMBER="$BUILD_NUMBER" "$PY" ./make.py

brotli_head=$(git -C /w/core/Common/3dParty/brotli/brotli rev-parse HEAD)
[ "$brotli_head" = "$BROTLI_SHA" ] || { echo "brotli built from $brotli_head, not $BROTLI_SHA" >&2; exit 1; }
echo "brotli $brotli_head patched" >> /w/provenance.txt
echo "pkg_target $PKG_TARGET patched" >> /w/provenance.txt

cd /w/document-server-package
make deb PRODUCT_VERSION="$PRODUCT_VERSION" BUILD_NUMBER="$BUILD_NUMBER"
find /w/document-server-package -name "*.deb" -newer /w/provenance.txt -print
