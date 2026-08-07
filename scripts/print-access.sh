#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "${ROOT}/scripts/lib.sh"

EOG_INSTALL_ROOT="${1:-${EOG_INSTALL_ROOT}}"
eog_load_config_env "${EOG_INSTALL_ROOT}/config.env"
onion="$(eog_read_onion_host || true)"
if [[ -z ${onion} ]]; then
  eog_die "onion hostname not available yet"
fi
printf 'Onion URL:  http://%s/\n' "${onion}"
printf 'Local URL:  http://127.0.0.1:%s/\n' "${HTTP_PORT}"
printf 'Admin user: %s\n' "${ADMIN_USER}"
printf 'Credentials file is written for the installing user; password is not printed here.\n'
