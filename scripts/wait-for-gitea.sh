#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "${ROOT}/scripts/lib.sh"

PORT="${1:-3000}"
TIMEOUT="${2:-180}"

if eog_wait_for_gitea "${PORT}" "${TIMEOUT}"; then
  eog_info "Gitea healthy on 127.0.0.1:${PORT}"
  exit 0
fi
eog_die "timed out waiting for Gitea /api/healthz on 127.0.0.1:${PORT}"
