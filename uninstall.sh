#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "${ROOT}/scripts/lib.sh"

PURGE=false

usage() {
  cat <<'EOF'
Usage: sudo ./uninstall.sh [--purge]

Default: stop and disable the service, remove the unit and eog-admin.
Data under /opt/easy-onion-gitea and /var/backups/easy-onion-gitea is kept.

--purge: also delete install root and local backups after YES confirmation.
Does not delete ~/.easy-onion-gitea/creds.txt (remove it manually).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --purge)
      PURGE=true
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      eog_die "unknown argument: $1"
      ;;
  esac
done

eog_require_root

if [[ -f "${EOG_INSTALL_ROOT}/config.env" ]]; then
  eog_load_config_env || true
fi

systemctl stop "${EOG_SERVICE_NAME}" 2>/dev/null || true
systemctl disable "${EOG_SERVICE_NAME}" 2>/dev/null || true
if [[ -d ${EOG_INSTALL_ROOT} ]] && command -v docker >/dev/null 2>&1; then
  (cd "${EOG_INSTALL_ROOT}" && docker compose down) 2>/dev/null || true
fi
rm -f /etc/systemd/system/easy-onion-gitea.service
systemctl daemon-reload || true
rm -f /usr/local/sbin/eog-admin

eog_info "Service and eog-admin removed."
eog_info "Install data kept at ${EOG_INSTALL_ROOT} (unless --purge)."
eog_info "Backups kept at ${EOG_BACKUP_DIR} (unless --purge)."

if [[ ${PURGE} == "true" ]]; then
  printf 'This permanently deletes %s and %s\n' "${EOG_INSTALL_ROOT}" "${EOG_BACKUP_DIR}"
  printf 'Type YES to purge: '
  read -r confirm
  [[ ${confirm} == "YES" ]] || eog_die "purge cancelled"
  rm -rf "${EOG_INSTALL_ROOT}"
  rm -rf "${EOG_BACKUP_DIR}"
  eog_info "Purge complete."
  eog_info "Remove credentials manually if present: ~/.easy-onion-gitea/creds.txt"
fi
