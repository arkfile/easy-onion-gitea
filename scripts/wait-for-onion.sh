#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "${ROOT}/scripts/lib.sh"

EOG_INSTALL_ROOT="${1:-${EOG_INSTALL_ROOT}}"
TIMEOUT="${2:-180}"
HOST_FILE="$(eog_onion_hostname_file)"

if eog_wait_for_file "${HOST_FILE}" "${TIMEOUT}"; then
  eog_info "onion hostname ready: $(eog_read_onion_host)"
  exit 0
fi
eog_die "timed out waiting for onion hostname at ${HOST_FILE}"
