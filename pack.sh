#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  printf '%s\n' 'Usage: bash pack.sh /path/to/clash-for-linux/runtime /path/to/bootstrap.tar.gz' >&2
  exit 2
fi

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
runtime=$1
output=$2
[[ -x $runtime/bin/mihomo && -x $runtime/bin/yq ]] || {
  printf '%s\n' 'The clash-for-linux runtime must contain executable bin/mihomo and bin/yq.' >&2
  exit 1
}

umask 077
staging=$(mktemp -d)
trap 'rm -rf -- "$staging"' EXIT
root="$staging/codex-container-bootstrap"
mkdir -p -- "$root/assets/bin"
cp -- "$repo_dir"/{setup.sh,pack.sh,README.md,.gitignore} "$root/"
cp -L -- "$runtime"/bin/{mihomo,yq} "$root/assets/bin/"
for name in Country.mmdb GeoIP.dat GeoSite.dat GeoLite2-ASN.mmdb geoip.metadb; do
  if [[ -f "$runtime/$name" ]]; then
    cp -L -- "$runtime/$name" "$root/assets/"
  fi
done

# Create the archive before placing it at the requested path.
tar -czf "$staging/bootstrap.tar.gz" -C "$staging" codex-container-bootstrap
mv -- "$staging/bootstrap.tar.gz" "$output"
printf '%s\n' "$output"
