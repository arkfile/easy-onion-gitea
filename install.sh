#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "${ROOT}/scripts/lib.sh"

HTTP_PORT_ARG=""
ADMIN_USER_ARG=""
REQUIRE_2FA="false"
MIN_DISK_MB=5120

usage() {
  cat <<'EOF'
Usage: sudo ./install.sh [--http-port N] [--admin-user NAME] [--require-2fa]

Install easy-onion-gitea on a supported Debian/Ubuntu host with Docker Compose.
Re-running a completed install refreshes static files and exits.
Re-running an incomplete install resumes bootstrap.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --http-port)
      HTTP_PORT_ARG="${2:-}"
      shift 2
      ;;
    --admin-user)
      ADMIN_USER_ARG="${2:-}"
      shift 2
      ;;
    --require-2fa)
      REQUIRE_2FA="true"
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
eog_require_sudo_user

if [[ -f /etc/os-release ]]; then
  # shellcheck source=/dev/null
  source /etc/os-release
else
  eog_die "unsupported host: missing /etc/os-release"
fi

case "${ID:-}:${VERSION_ID:-}" in
  debian:* | ubuntu:*) ;;
  *)
    eog_die "unsupported distribution '${ID:-unknown}'. v0.1 supports Debian and Ubuntu with systemd."
    ;;
esac

command -v systemctl >/dev/null 2>&1 || eog_die "systemd (systemctl) is required"
command -v openssl >/dev/null 2>&1 || eog_die "openssl is required"
command -v curl >/dev/null 2>&1 || eog_die "curl is required"
command -v tar >/dev/null 2>&1 || eog_die "tar is required"

if ! command -v docker >/dev/null 2>&1; then
  eog_info "Docker Engine not found; installing from Docker's Debian/Ubuntu apt repository"
  apt-get update
  apt-get install -y --no-install-recommends ca-certificates curl gnupg
  install -m 0755 -d /etc/apt/keyrings
  if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
    curl -fsSL https://download.docker.com/linux/"${ID}"/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
  fi
  arch="$(dpkg --print-architecture)"
  codename="${VERSION_CODENAME:-}"
  [[ -n ${codename} ]] || eog_die "could not determine VERSION_CODENAME for Docker apt repo"
  printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/%s %s stable\n' \
    "${arch}" "${ID}" "${codename}" >/etc/apt/sources.list.d/docker.list
  apt-get update
  apt-get install -y --no-install-recommends docker-ce docker-ce-cli containerd.io docker-compose-plugin
fi

docker info >/dev/null 2>&1 || eog_die "Docker is installed but not healthy; start docker.service and retry"
docker compose version >/dev/null 2>&1 || eog_die "Docker Compose v2 plugin is required"

eog_load_images_lock "${ROOT}/images.lock"

COMPLETE=false
if eog_install_is_complete; then
  COMPLETE=true
fi

if [[ ${COMPLETE} == "true" ]]; then
  eog_load_config_env "${EOG_INSTALL_ROOT}/config.env"
  eog_info "Completed installation detected at ${EOG_INSTALL_ROOT}"
  eog_info "Preserving port, credentials, secrets, onion identity, data, and app.ini."
  if [[ -n ${HTTP_PORT_ARG} && ${HTTP_PORT_ARG} != "${HTTP_PORT}" ]]; then
    eog_die "refusing to change HTTP port on re-install (configured port is ${HTTP_PORT}); edit config.env deliberately if required"
  fi
  eog_refresh_static_files "${ROOT}"
  systemctl enable easy-onion-gitea.service >/dev/null 2>&1 || true
  eog_info "Static files and systemd unit refreshed."
  eog_info "Use: sudo eog-admin status|doctor|backup|restore|update|onion|reset-admin-password"
  eog_info "To upgrade images from a newer release: sudo eog-admin update /path/to/release"
  exit 0
fi

if [[ -f "${EOG_INSTALL_ROOT}/config.env" ]]; then
  eog_info "Incomplete installation detected; resuming bootstrap."
  eog_load_config_env "${EOG_INSTALL_ROOT}/config.env"
  HTTP_PORT_FINAL="${HTTP_PORT}"
  ADMIN_USER_FINAL="${ADMIN_USER}"
  REQUIRE_2FA_FINAL="${REQUIRE_2FA:-false}"
  if [[ -n ${HTTP_PORT_ARG} && ${HTTP_PORT_ARG} != "${HTTP_PORT_FINAL}" ]]; then
    eog_die "refusing to change HTTP port during resume (configured port is ${HTTP_PORT_FINAL})"
  fi
  if [[ -n ${ADMIN_USER_ARG} && ${ADMIN_USER_ARG} != "${ADMIN_USER_FINAL}" ]]; then
    eog_die "refusing to change admin user during resume (configured user is ${ADMIN_USER_FINAL})"
  fi
else
  HTTP_PORT_FINAL="${HTTP_PORT_ARG:-3000}"
  ADMIN_USER_FINAL="${ADMIN_USER_ARG:-gitea-admin}"
  REQUIRE_2FA_FINAL="${REQUIRE_2FA}"
  eog_validate_http_port "${HTTP_PORT_FINAL}"
  if eog_port_in_use "${HTTP_PORT_FINAL}"; then
    eog_die "port ${HTTP_PORT_FINAL} is already in use; choose another with --http-port N"
  fi
fi

[[ ${ADMIN_USER_FINAL} =~ ^[A-Za-z0-9_][A-Za-z0-9_-]{0,39}$ ]] || eog_die "invalid admin username"

free_mb="$(eog_disk_free_mb || echo 0)"
if [[ -n ${free_mb} && ${free_mb} =~ ^[0-9]+$ ]] && ((free_mb < MIN_DISK_MB)); then
  eog_die "need at least ${MIN_DISK_MB} MiB free disk; found ${free_mb} MiB"
fi

eog_ensure_dirs
eog_refresh_static_files "${ROOT}"
install -m 0644 "${ROOT}/config.env.example" "${EOG_INSTALL_ROOT}/config.env.example"

TOR_IMAGE="${TOR_IMAGE_NAME}:${TOR_IMAGE_TAG}"
LOOPBACK_IMAGE="${LOOPBACK_IMAGE_NAME}:${LOOPBACK_IMAGE_TAG}"
GITEA_IMAGE_PIN="${GITEA_IMAGE}"

cat >"${EOG_INSTALL_ROOT}/config.env" <<EOF
COMPOSE_PROJECT_NAME=${EOG_COMPOSE_PROJECT}
INSTALL_ROOT=${EOG_INSTALL_ROOT}
HTTP_PORT=${HTTP_PORT_FINAL}
ADMIN_USER=${ADMIN_USER_FINAL}
REQUIRE_2FA=${REQUIRE_2FA_FINAL}
GITEA_IMAGE=${GITEA_IMAGE_PIN}
TOR_IMAGE=${TOR_IMAGE}
LOOPBACK_IMAGE=${LOOPBACK_IMAGE}
DEBIAN_BASE_IMAGE=${DEBIAN_BASE_IMAGE}
TOR_APT_SUITE=${TOR_APT_SUITE}
TOR_PACKAGE_VERSION=${TOR_PACKAGE_VERSION}
EOF
chmod 0640 "${EOG_INSTALL_ROOT}/config.env"
chown root:root "${EOG_INSTALL_ROOT}/config.env"

eog_load_config_env "${EOG_INSTALL_ROOT}/config.env"

eog_info "Pulling Gitea ${GITEA_VERSION}..."
docker pull "${GITEA_IMAGE}"

eog_write_secrets_if_missing

systemctl enable easy-onion-gitea.service

eog_info "Building Tor and loopback-proxy images..."
eog_compose build tor loopback-proxy
eog_record_tor_identity
eog_ensure_dirs

# Bootstrap: start Tor first for onion hostname, then write app.ini, then full stack.
# Tear down first so Compose recreates networks when IPAM/subnet pins change.
eog_info "Starting Tor to obtain onion hostname..."
eog_compose down >/dev/null 2>&1 || true
eog_compose up -d --remove-orphans tor
if ! eog_wait_for_file "$(eog_onion_hostname_file)" 180; then
  eog_die "onion hostname timeout; check: docker compose --project-directory ${EOG_INSTALL_ROOT} logs tor"
fi
ONION_HOST="$(eog_read_onion_host)"
[[ ${ONION_HOST} == *.onion ]] || eog_die "invalid onion hostname: ${ONION_HOST}"

if [[ ! -f "${EOG_INSTALL_ROOT}/config/app.ini" ]]; then
  eog_render_app_ini "${ONION_HOST}" "${REQUIRE_2FA_FINAL}" "${EOG_INSTALL_ROOT}/config/app.ini.tmpl"
else
  eog_info "Preserving existing config/app.ini; syncing onion URL and runtime copy"
  eog_update_app_ini_onion "${ONION_HOST}" || eog_render_app_ini "${ONION_HOST}" "${REQUIRE_2FA_FINAL}" "${EOG_INSTALL_ROOT}/config/app.ini.tmpl"
fi
eog_sync_app_ini_to_runtime
chown -R "${EOG_GITEA_UID}:${EOG_GITEA_GID}" "${EOG_INSTALL_ROOT}/data/gitea"

eog_info "Starting full stack..."
systemctl start easy-onion-gitea.service || eog_compose up -d --remove-orphans

if ! eog_wait_for_gitea "${HTTP_PORT}" 180; then
  eog_die "Gitea health check failed on 127.0.0.1:${HTTP_PORT}/api/healthz (try: docker compose --project-directory ${EOG_INSTALL_ROOT} logs gitea)"
fi

CREDS_DIR="$(eog_sudo_home)/.easy-onion-gitea"
CREDS_FILE="${CREDS_DIR}/creds.txt"
if [[ -f "${EOG_INSTALL_ROOT}/state/admin_bootstrapped" ]]; then
  eog_info "Administrator already bootstrapped; not creating or rotating password"
else
  ADMIN_PASSWORD="$(eog_generate_password)"
  eog_create_admin_if_missing "${ADMIN_USER}" "${ADMIN_PASSWORD}"
  printf '%s\n' "${ADMIN_USER}" >"${EOG_INSTALL_ROOT}/state/admin_user"
  date -u +%Y-%m-%dT%H:%M:%SZ >"${EOG_INSTALL_ROOT}/state/admin_bootstrapped"
  chmod 600 "${EOG_INSTALL_ROOT}/state/admin_user" "${EOG_INSTALL_ROOT}/state/admin_bootstrapped"
  if [[ ! -f ${CREDS_FILE} ]]; then
    sudo_group="$(id -gn "${SUDO_USER}")"
    install -d -m 700 -o "${SUDO_USER}" -g "${sudo_group}" "${CREDS_DIR}"
    cat >"${CREDS_FILE}" <<EOF
onion_url=http://${ONION_HOST}/
local_url=http://127.0.0.1:${HTTP_PORT}/
admin_user=${ADMIN_USER}
admin_password=${ADMIN_PASSWORD}
EOF
    chown "${SUDO_USER}:${sudo_group}" "${CREDS_FILE}"
    chmod 600 "${CREDS_FILE}"
  fi
fi

eog_info "Running eog-admin doctor..."
/usr/local/sbin/eog-admin doctor || eog_die "eog-admin doctor reported failures"

if [[ ! -f "${EOG_INSTALL_ROOT}/state/initial_backup_done" ]]; then
  eog_info "Creating initial backup (service will pause briefly for SQLite consistency)..."
  /usr/local/sbin/eog-admin backup || eog_die "initial backup failed"
  date -u +%Y-%m-%dT%H:%M:%SZ >"${EOG_INSTALL_ROOT}/state/initial_backup_done"
  chmod 600 "${EOG_INSTALL_ROOT}/state/initial_backup_done"
else
  eog_info "Initial backup already recorded; skipping automatic backup on resume"
fi

eog_mark_install_complete

eog_info ""
eog_info "Installation complete."
eog_info "Onion URL: http://${ONION_HOST}/"
eog_info "Local URL: http://127.0.0.1:${HTTP_PORT}/"
eog_info "Credentials: ${CREDS_FILE}"
eog_info "Change the bootstrap password after first login. Use individual accounts for daily work."
eog_info "Admin commands: sudo eog-admin status|doctor|backup|restore|update|onion|reset-admin-password"
