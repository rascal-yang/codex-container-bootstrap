#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
assets="${BOOTSTRAP_ASSETS_DIR:-$repo_dir/assets}"
mihomo_version=v1.19.23
yq_version=v4.52.4

case "${1:-$(uname -m)}" in
  x86_64|amd64) arch=amd64; mihomo_arch=amd64-compatible ;;
  aarch64|arm64) arch=arm64; mihomo_arch=arm64 ;;
  *) printf 'Usage: bash prepare-assets.sh [amd64|arm64]\n' >&2; exit 2 ;;
esac

mkdir -p -- "$assets/bin"
staging=$(mktemp -d "$assets/.download.XXXXXXXX")
trap 'rm -rf -- "$staging"' EXIT

download() {
  printf 'Downloading %s\n' "${1##*/}" >&2
  curl --fail --silent --show-error --location --connect-timeout 15 --max-time 180 \
    --retry 2 --retry-max-time 180 --output "$2" "$1"
  test -s "$2"
}

download "https://github.com/MetaCubeX/mihomo/releases/download/$mihomo_version/mihomo-linux-$mihomo_arch-$mihomo_version.gz" "$staging/mihomo.gz"
gzip -dc "$staging/mihomo.gz" > "$staging/mihomo"
download "https://github.com/mikefarah/yq/releases/download/$yq_version/yq_linux_$arch" "$staging/yq"
chmod 755 "$staging/mihomo" "$staging/yq"

geo_url=https://github.com/MetaCubeX/meta-rules-dat/releases/latest/download
download "$geo_url/country.mmdb" "$staging/Country.mmdb"
download "$geo_url/geoip.dat" "$staging/GeoIP.dat"
download "$geo_url/geosite.dat" "$staging/GeoSite.dat"
download "$geo_url/GeoLite2-ASN.mmdb" "$staging/GeoLite2-ASN.mmdb"
download "$geo_url/geoip.metadb" "$staging/geoip.metadb"

mv -- "$staging"/{Country.mmdb,GeoIP.dat,GeoSite.dat,GeoLite2-ASN.mmdb,geoip.metadb} "$assets/"
mv -- "$staging"/{mihomo,yq} "$assets/bin/"
printf 'Proxy assets prepared in %s\n' "$assets"
