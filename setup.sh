#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'HELP'
Usage: bash setup.sh [--check|--install-only] [--subscription|/path/to/clash.yaml] [codex arguments...]
  --subscription  Prompt for a Clash/Mihomo subscription URL (default without a path).
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
subscription_mode=false
case "${1:-}" in
  --subscription) subscription_mode=true; shift ;;
  '') subscription_mode=true ;;
  *)
    config=$1
    shift
    [[ -f $config && -r $config ]] || die "Provide a readable Clash/Mihomo YAML file."
    [[ $config = /* ]] || config="$PWD/$config"
    ;;
esac
[[ $mode == run || $# -eq 0 ]] || die "Codex arguments require run mode."
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
[[ -x $mihomo && -x $yq ]] || die "Missing proxy binaries in $assets/bin. Run bash $repo_dir/prepare-assets.sh from a GitHub-connected machine, or use the prepared bundle."
if [[ $subscription_mode == true ]]; then
  command -v curl >/dev/null 2>&1 || die "curl is required to download a subscription."
  IFS= read -rs -p "Clash/Mihomo subscription URL: " subscription ||
    die "Provide an HTTP or HTTPS subscription URL."
  if [[ -t 0 ]]; then printf '\n' >&2; fi
  case "$subscription" in
    *[[:space:][:cntrl:]]*|*'"'*|*'\'*) die "The subscription URL contains invalid characters." ;;
    https://?*|http://?*) ;;
    *) die "Provide an HTTP or HTTPS subscription URL." ;;
  esac
  config="$runtime/subscription.yaml"
  printf 'url = "%s"\n' "$subscription" |
    curl -q --config - --globoff --proto '=https,http' --proto-redir '=https,http' \
      --fail --silent --show-error --location --connect-timeout 10 --max-time 60 \
      --user-agent 'clash-verge/v2.4.0' --output "$config" 2>"$runtime/subscription.log" ||
    die "Could not download the subscription. Check the link and connectivity to the subscription server."
  unset subscription
  "$yq" eval -e 'tag == "!!map" and ((.proxies | length) > 0 or (.["proxy-providers"] | length) > 0)' \
    "$config" >/dev/null 2>&1 ||
    die "The subscription must return Clash/Mihomo YAML with proxies or proxy providers."
fi
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
with_mihomo() (
  export http_proxy=$proxy HTTP_PROXY=$proxy https_proxy=$proxy HTTPS_PROXY=$proxy
  export all_proxy=$proxy ALL_PROXY=$proxy
  export no_proxy=localhost,127.0.0.1,::1 NO_PROXY=localhost,127.0.0.1,::1
  "$@"
)
export PATH="$HOME/.local/bin:$PATH"

if ! command -v codex >/dev/null 2>&1; then
  command -v curl >/dev/null 2>&1 || die "curl is required to download Codex."
  printf '%s\n' "Downloading the official Codex installer through Mihomo…" >&2
  if with_mihomo curl -q --fail --silent --show-error --location --connect-timeout 10 --max-time 25 \
    --output "$runtime/install-codex.sh" https://chatgpt.com/codex/install.sh; then
    with_mihomo sh "$runtime/install-codex.sh" ||
      printf '%s\n' "The standalone installer failed. Trying GitHub Releases…" >&2
  fi
  if ! command -v codex >/dev/null 2>&1; then
    case "$(uname -m)" in
      x86_64) target=x86_64-unknown-linux-musl ;;
      aarch64|arm64) target=aarch64-unknown-linux-musl ;;
      *) die "GitHub release fallback supports Linux amd64 and arm64." ;;
    esac
    asset="codex-$target"
    url="https://github.com/openai/codex/releases/latest/download/$asset.tar.gz"
    download=(curl -q --fail --silent --show-error --location --proto '=https' --proto-redir '=https'
      --connect-timeout 10 --max-time 900 --output "$runtime/codex.tar.gz" "$url")
    printf '%s\n' "Downloading Codex from OpenAI's GitHub Releases…" >&2
    "${download[@]}" || with_mihomo "${download[@]}" ||
      die "Could not download Codex from GitHub Releases over either network path."
    tar -xOzf "$runtime/codex.tar.gz" "$asset" > "$runtime/codex" ||
      die "Could not extract Codex from the GitHub release archive."
    chmod 755 "$runtime/codex"
    "$runtime/codex" --version >/dev/null || die "The downloaded Codex binary could not run."
    mkdir -p -- "$HOME/.local/bin"
    install -m 755 -- "$runtime/codex" "$HOME/.local/bin/codex"
  fi
fi
command -v codex >/dev/null 2>&1 || die "Codex is not on PATH after installation."
if [[ $mode == install ]]; then
  with_mihomo codex --version
else
  with_mihomo codex "$@"
fi
