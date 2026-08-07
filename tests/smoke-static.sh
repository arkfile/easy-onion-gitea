#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

fail=0
check() {
  local name="$1"
  shift
  if "$@"; then
    printf 'OK  %s\n' "${name}"
  else
    printf 'FAIL %s\n' "${name}"
    fail=1
  fi
}

check "VERSION present" test -s VERSION
check "images.lock pins gitea digest" grep -q 'gitea/gitea:1.27.1@sha256:' images.lock
check "images.lock pins tor package" grep -q '0.4.9.11' images.lock
check "compose internal network" grep -q 'internal: true' compose.yml
check "compose no docker.sock" bash -c "! grep -q docker.sock compose.yml"
check "compose localhost bind" grep -Fq '127.0.0.1:${HTTP_PORT' compose.yml
check "compose does not bind-mount app.ini read-only" bash -c "! grep -q 'app.ini:ro' compose.yml"
check "compose gitea does not cap_drop ALL" bash -c "! awk '/^  gitea:/,/^  [a-z]/ {print}' compose.yml | grep -q 'cap_drop'"
check "app template onion allowlist" grep -q 'ALLOWED_DOMAINS = \*.onion' config/app.ini.tmpl
check "app template proxy" grep -q 'socks5h://tor:9050' config/app.ini.tmpl
check "app template SECRET_KEY_URI" grep -q 'SECRET_KEY_URI = file:/run/eog-secrets/secret_key' config/app.ini.tmpl
check "torrc hidden service v3" grep -q 'HiddenServiceVersion 3' config/torrc
check "scripts executable" test -x install.sh && test -x bin/eog-admin && test -x bin/eogit
check "install complete marker helper" grep -q 'eog_mark_install_complete' scripts/lib.sh
check "backup excludes SHA256SUMS from hash input" grep -q '! -name SHA256SUMS' bin/eog-admin
check "ASCII docs" bash -c "! grep -P '[^\x00-\x7F]' README.md AGENTS.md SECURITY.md"

if [[ ${fail} -ne 0 ]]; then
  echo "smoke-static failed"
  exit 1
fi
echo "smoke-static OK"
