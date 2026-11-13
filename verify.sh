#!/usr/bin/env bash
# Checks an ONLYOFFICE Docs image without starting the Document Server: the
# Node.js runtime embedded in the pkg binaries (read, not run), that no nginx
# site competes for port 80, and the Brotli build recorded on the image.
#
#   ./verify.sh <image> [expected-node-version]
set -euo pipefail

image="${1:?image}"
want_node="${2:-v24.22.1}"
server=/var/www/onlyoffice/documentserver/server
tmp="$(mktemp -d)"
cid="$(docker create --entrypoint /bin/true "$image")"
trap 'docker rm "$cid" >/dev/null; rm -rf "$tmp"' EXIT

fail=0
for bin in DocService/docservice FileConverter/converter Metrics/metrics; do
  docker cp -q "$cid:$server/$bin" "$tmp/bin"
  got="$(strings -n 6 "$tmp/bin" | grep -oE 'release/v[0-9]+\.[0-9]+\.[0-9]+' | sort | uniq -c | sort -rn | awk 'NR==1{sub("release/","",$2); print $2}')"
  if [ "$got" = "$want_node" ]; then echo "PASS $bin node $got"; else echo "FAIL $bin node $got, want $want_node"; fail=1; fi
done

# Ubuntu's default site also claims port 80 as default_server, so nginx never
# starts once the Document Server writes its own (vendor Bug 82308).
if docker run --rm --entrypoint test "$image" -e /etc/nginx/sites-enabled/default; then
  echo "FAIL nginx sites-enabled/default is present"; fail=1
else
  echo "PASS nginx sites-enabled/default absent"
fi

docker cp -q "$cid:/var/lib/dpkg/status" "$tmp/status"
awk '/^Package: (onlyoffice-documentserver|libbrotli1)$/{p=$2} p&&/^Version:/{print "INFO " p " " $2; p=""}' "$tmp/status"
docker image inspect --format '{{range $k, $v := .Config.Labels}}{{if or (eq $k "co.amplytic.amp2495.brotli") (eq $k "co.amplytic.amp2495.onlyoffice-tag")}}INFO {{$k}} {{$v}}{{"\n"}}{{end}}{{end}}' "$image"
exit "$fail"
