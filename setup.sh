#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'HELP'
Usage: bash setup.sh [--check|--install-only] /path/to/clash.yaml [codex arguments...]
  --check         Validate the config and local assets without starting the proxy.
  --install-only  Install Codex and print its version without opening a session.
  BOOTSTRAP_ASSETS_DIR  Directory containing bin/mihomo, bin/yq and optional GEO files.
  BOOTSTRAP_PROXY_PORT  Loopback mixed proxy port (default: 17890).
HELP
}

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

mode=run
case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  --check) mode=check; shift ;;
  --install-only) mode=install; shift ;;
esac
[[ $# -ge 1 ]] || { usage >&2; exit 2; }
config=$1
shift
[[ $mode == run || $# -eq 0 ]] || die "Codex arguments require run mode."
[[ -f $config && -r $config ]] || die "Provide a readable Clash/Mihomo YAML file."
[[ $config = /* ]] || config="$PWD/$config"
[[ $(uname -s) == Linux ]] || die "This bootstrap supports Linux containers."

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
assets=${BOOTSTRAP_ASSETS_DIR:-$repo_dir/assets}
[[ $assets = /* ]] || assets="$PWD/$assets"
port=${BOOTSTRAP_PROXY_PORT:-17890}
[[ $port =~ ^[1-9][0-9]{0,4}$ ]] && (( port <= 65535 )) || die "Invalid BOOTSTRAP_PROXY_PORT."

umask 077
runtime=$(mktemp -d)
proxy_pid=
cleanup() {
  if [[ -n $proxy_pid ]]; then
    kill "$proxy_pid" 2>/dev/null || true
    wait "$proxy_pid" 2>/dev/null || true
  fi
  rm -rf -- "$runtime"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mihomo="$assets/bin/mihomo"
yq="$assets/bin/yq"
[[ -x $mihomo && -x $yq ]] || die "Missing proxy binaries in $assets/bin. Use the bundle or point BOOTSTRAP_ASSETS_DIR at the clash-for-linux runtime directory."
for name in Country.mmdb GeoIP.dat GeoSite.dat GeoLite2-ASN.mmdb geoip.metadb; do
  if [[ -f "$assets/$name" ]]; then
    ln -s -- "$assets/$name" "$runtime/$name"
  fi
done

# Keep the proxy isolated to this shell and avoid listeners from the supplied YAML.
BOOTSTRAP_PROXY_PORT=$port "$yq" eval '
  .["mixed-port"] = env(BOOTSTRAP_PROXY_PORT) |
  .["allow-lan"] = false |
  .["bind-address"] = "127.0.0.1" |
  .["tun"] = {"enable": false} |
  .["geo-auto-update"] = false |
  del(.port, .["socks-port"], .["redir-port"], .["tproxy-port"],
      .["external-controller"], .["external-controller-tls"],
      .["external-controller-unix"], .["external-controller-pipe"],
      .["external-ui"], .["external-ui-url"], .["find-process-mode"],
      .listeners, .authentication, .["skip-auth-prefixes"],
      .dns.listen)
' "$config" > "$runtime/config.yaml" 2>"$runtime/yq.log" ||
  die "Could not parse the Clash YAML."
"$mihomo" -t -d "$runtime" -f "$runtime/config.yaml" >"$runtime/config-test.log" 2>&1 ||
  die "Mihomo rejected the config. Check the YAML, proxy providers and GEO files."
if [[ $mode == check ]]; then
  printf '%s\n' "Clash YAML and Mihomo runtime validation passed."
  exit 0
fi

proxy_port_open() {
  ( : >"/dev/tcp/127.0.0.1/$port" ) 2>/dev/null
}
if proxy_port_open; then
  die "Port $port is already in use. Set BOOTSTRAP_PROXY_PORT to a free port."
fi
"$mihomo" -d "$runtime" -f "$runtime/config.yaml" >"$runtime/mihomo.log" 2>&1 &
proxy_pid=$!
for ((attempt=0; attempt<50; attempt++)); do
  kill -0 "$proxy_pid" 2>/dev/null || die "Mihomo exited before opening port $port."
  if proxy_port_open; then break; fi
  sleep 0.2
done
proxy_port_open || die "Mihomo did not open port $port within 10 seconds."

proxy="http://127.0.0.1:$port"
export http_proxy=$proxy HTTP_PROXY=$proxy https_proxy=$proxy HTTPS_PROXY=$proxy
export all_proxy=$proxy ALL_PROXY=$proxy
export no_proxy=localhost,127.0.0.1,::1 NO_PROXY=localhost,127.0.0.1,::1
export PATH="$HOME/.local/bin:$PATH"

if ! command -v codex >/dev/null 2>&1; then
  command -v curl >/dev/null 2>&1 || die "curl is required to download Codex."
  printf '%s\n' "Downloading the official Codex installer through Mihomo…" >&2
  curl --fail --silent --show-error --location --connect-timeout 10 --max-time 60 \
    --retry 2 --retry-max-time 90 --output "$runtime/install-codex.sh" \
    https://chatgpt.com/codex/install.sh
  sh "$runtime/install-codex.sh"
fi
command -v codex >/dev/null 2>&1 || die "Codex is not on PATH after installation."
if [[ $mode == install ]]; then
  codex --version
else
  codex "$@"
fi
