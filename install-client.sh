#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

info() {
  printf '%s\n' "$*"
}

if [[ ${EUID} -ne 0 ]]; then
  die "run as root via sudo: sudo ./install-client.sh"
fi
if [[ -z ${SUDO_USER:-} || ${SUDO_USER} == "root" ]]; then
  die "run via sudo as a normal user so SUDO_USER is set"
fi

if [[ -f /etc/os-release ]]; then
  # shellcheck source=/dev/null
  source /etc/os-release
else
  die "unsupported host: missing /etc/os-release"
fi

case "${ID:-}" in
  debian | ubuntu) ;;
  *)
    die "v0.1 client installer supports Debian and Ubuntu only"
    ;;
esac

command -v systemctl >/dev/null 2>&1 || die "systemd is required"
apt-get update
apt-get install -y --no-install-recommends tor git curl ca-certificates
systemctl enable --now tor.service || systemctl enable --now tor@default.service || true

# Wait for SOCKS
ok=0
for _ in $(seq 1 30); do
  if ss -ltn | grep -qE '127\.0\.0\.1:9050'; then
    ok=1
    break
  fi
  sleep 1
done
[[ ${ok} -eq 1 ]] || die "Tor SOCKS listener not available on 127.0.0.1:9050"

# The SOCKS port opens before circuits exist. A new /var/lib/tor rejects
# the first proxied fetches until bootstrap finishes, so retry the same
# check eogit doctor uses.
info "Waiting for Tor to finish bootstrap..."
deadline=$((SECONDS + 180))
boot_ok=0
last_err=""
while ((SECONDS < deadline)); do
  if last_err="$(sudo -u "${SUDO_USER}" curl -fsS --max-time 10 --proxy socks5h://127.0.0.1:9050 -o /dev/null https://check.torproject.org/api/ip 2>&1)"; then
    boot_ok=1
    break
  fi
  info "Tor SOCKS is up; circuits are not ready yet."
  if ((SECONDS + 5 >= deadline)); then
    break
  fi
  sleep 5
done
if [[ ${boot_ok} -ne 1 ]]; then
  if [[ -n ${last_err} ]]; then
    printf '%s\n' "${last_err}" >&2
  fi
  die "Tor did not become usable via socks5h://127.0.0.1:9050. Check: journalctl -u tor.service"
fi

install -m 0755 "${ROOT}/bin/eogit" /usr/local/bin/eogit
install -d -m 0755 /usr/local/share/doc/easy-onion-gitea
[[ -f "${ROOT}/docs/eogit.md" ]] && install -m 0644 "${ROOT}/docs/eogit.md" /usr/local/share/doc/easy-onion-gitea/eogit.md

if ! sudo -u "${SUDO_USER}" EOGIT_TOR_PROXY="socks5h://127.0.0.1:9050" /usr/local/bin/eogit doctor; then
  die "eogit doctor failed after install"
fi

info "Client install complete. Use: eogit clone http://your-onion.onion/org/repo.git"
info "For Tor Browser SOCKS on 9150: export EOGIT_TOR_PROXY=socks5h://127.0.0.1:9150"
