#!/bin/bash
# Smoke test: build the image, serve one NetCDF file, hit the endpoints APSViz uses.
# usage: test/smoke.sh <file.nc> [expected TDS version]
set -u
NC=${1:?usage: test/smoke.sh <file.nc> [version]}
VER=${2:-5.10}
IMG=thredds-smoke NAME=thredds-smoke PORT=8089 URL=http://localhost:8089/thredds
export MSYS_NO_PATHCONV=1  # stop git-bash on Windows mangling container paths
cd "$(dirname "$0")/.."

docker build -t $IMG . || exit 1
docker rm -f $NAME >/dev/null 2>&1
docker run -d --name $NAME -p $PORT:8080 $IMG >/dev/null || exit 1
trap 'docker rm -f $NAME >/dev/null' EXIT

docker exec -u root $NAME mkdir -p /data
docker cp "$NC" $NAME:/data/test.nc
docker cp test/catalog.xml $NAME:/home/nru/tomcat/content/thredds/catalog.xml
docker exec -u root $NAME chown -R nru:nru /data /home/nru/tomcat/content
docker restart $NAME >/dev/null  # pick up the catalog

echo "waiting for tomcat..."
for i in $(seq 60); do curl -sf $URL/catalog/catalog.html >/dev/null && break; sleep 2; done

fail=0
check() { if eval "$2" >/dev/null 2>&1; then echo "PASS $1"; else echo "FAIL $1"; fail=1; fi; }
# ponytail: status-code check, Windows curl exits 23 when discarding binary bodies
ok() { [ "$(curl -s -o /dev/null -w '%{http_code}' "$1")" = 200 ]; }
check "catalog.html"         "ok $URL/catalog/catalog.html"
# TDS 5.10 no longer shows its version on the info pages, so read the WAR manifest
check "version is $VER"      "docker exec $NAME grep -qx 'Implementation-Version: $VER.\?' /home/nru/tomcat/webapps/thredds/META-INF/MANIFEST.MF"
check "datasetScan lists nc" "curl -sf $URL/catalog/smoke/catalog.xml | grep -q test.nc"
check "OPeNDAP .dds"         "curl -sf $URL/dodsC/smoke/test.nc.dds"
check "OPeNDAP .das"         "curl -sf $URL/dodsC/smoke/test.nc.das"
check "fileServer download"  "ok $URL/fileServer/smoke/test.nc"
check "renci branding"       "ok $URL/renci-logo.png"

[ $fail = 1 ] && { echo "--- container log tail ---"; docker logs --tail 50 $NAME; }
exit $fail
