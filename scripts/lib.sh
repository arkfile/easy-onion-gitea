# Shared library for easy-onion-gitea shell tools.
# shellcheck shell=bash

set -Eeuo pipefail

EOG_INSTALL_ROOT="${EOG_INSTALL_ROOT:-/opt/easy-onion-gitea}"
EOG_BACKUP_DIR="${EOG_BACKUP_DIR:-/var/backups/easy-onion-gitea}"
EOG_SERVICE_NAME="${EOG_SERVICE_NAME:-easy-onion-gitea.service}"
EOG_COMPOSE_PROJECT="${EOG_COMPOSE_PROJECT:-easy-onion-gitea}"
EOG_GITEA_UID="${EOG_GITEA_UID:-1000}"
EOG_GITEA_GID="${EOG_GITEA_GID:-1000}"
# debian-tor in official Debian tor packages is commonly uid/gid 101; overridden after image build.
EOG_TOR_UID="${EOG_TOR_UID:-101}"
EOG_TOR_GID="${EOG_TOR_GID:-101}"

eog_die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

eog_info() {
  printf '%s\n' "$*"
}

eog_require_root() {
  if [[ ${EUID} -ne 0 ]]; then
    eog_die "this command must run as root (use sudo)"
  fi
}

eog_require_sudo_user() {
  if [[ -z ${SUDO_USER:-} || ${SUDO_USER} == "root" ]]; then
    eog_die "run via sudo as a normal user so SUDO_USER is set (needed for credentials ownership)"
  fi
}

eog_sudo_home() {
  local home
  home="$(getent passwd "${SUDO_USER}" | cut -d: -f6 || true)"
  [[ -n ${home} ]] || eog_die "could not resolve home directory for SUDO_USER=${SUDO_USER}"
  printf '%s\n' "${home}"
}

eog_load_images_lock() {
  local lock_file="$1"
  [[ -f ${lock_file} ]] || eog_die "missing images.lock at ${lock_file}"
  # shellcheck disable=SC1090
  set -a
  # shellcheck source=/dev/null
  source <(grep -E '^[A-Z0-9_]+=' "${lock_file}")
  set +a
}

eog_load_config_env() {
  local env_file="${1:-${EOG_INSTALL_ROOT}/config.env}"
  [[ -f ${env_file} ]] || eog_die "missing config.env at ${env_file}"
  # shellcheck disable=SC1090
  set -a
  # shellcheck source=/dev/null
  source "${env_file}"
  set +a
  INSTALL_ROOT="${INSTALL_ROOT:-${EOG_INSTALL_ROOT}}"
  EOG_INSTALL_ROOT="${INSTALL_ROOT}"
  HTTP_PORT="${HTTP_PORT:-3000}"
  ADMIN_USER="${ADMIN_USER:-gitea-admin}"
  if [[ -f "${EOG_INSTALL_ROOT}/state/tor_uid" ]]; then
    EOG_TOR_UID="$(tr -d '[:space:]' <"${EOG_INSTALL_ROOT}/state/tor_uid")"
  fi
  if [[ -f "${EOG_INSTALL_ROOT}/state/tor_gid" ]]; then
    EOG_TOR_GID="$(tr -d '[:space:]' <"${EOG_INSTALL_ROOT}/state/tor_gid")"
  fi
}

eog_compose() {
  docker compose \
    --project-directory "${EOG_INSTALL_ROOT}" \
    --env-file "${EOG_INSTALL_ROOT}/config.env" \
    "$@"
}

eog_atomic_write() {
  local dest="$1"
  local mode="${2:-0644}"
  local owner="${3:-}"
  local tmp
  tmp="$(mktemp "${dest}.tmp.XXXXXX")"
  cat >"${tmp}"
  chmod "${mode}" "${tmp}"
  if [[ -n ${owner} ]]; then
    chown "${owner}" "${tmp}"
  fi
  mv -f "${tmp}" "${dest}"
}

eog_generate_secret() {
  openssl rand -base64 48 | tr -d '\n'
}

eog_generate_password() {
  openssl rand -base64 24 | tr -d '\n=/+' | head -c 32
}

eog_gitea_generate_secret() {
  local kind="$1"
  local image="${GITEA_IMAGE:-}"
  if [[ -n ${image} ]] && docker image inspect "${image}" >/dev/null 2>&1; then
    docker run --rm --entrypoint /usr/local/bin/gitea "${image}" generate secret "${kind}" | tr -d '\r\n'
    return 0
  fi
  eog_generate_secret
}

eog_port_in_use() {
  local port="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -ltn "sport = :${port}" | grep -q LISTEN
  else
    return 1
  fi
}

eog_validate_http_port() {
  local port="$1"
  [[ ${port} =~ ^[0-9]+$ ]] || eog_die "HTTP port must be an integer"
  if ((port < 1 || port > 65535)); then
    eog_die "HTTP port must be between 1 and 65535"
  fi
}

eog_onion_hostname_file() {
  printf '%s\n' "${EOG_INSTALL_ROOT}/data/tor/hidden_service/hostname"
}

eog_read_onion_host() {
  local f
  f="$(eog_onion_hostname_file)"
  [[ -f ${f} ]] || return 1
  tr -d '[:space:]' <"${f}"
}

eog_wait_for_file() {
  local path="$1"
  local timeout_s="${2:-180}"
  local i=0
  while [[ ! -s ${path} ]]; do
    if ((i >= timeout_s)); then
      return 1
    fi
    sleep 1
    i=$((i + 1))
  done
}

eog_wait_for_gitea() {
  local port="${1:-${HTTP_PORT:-3000}}"
  local timeout_s="${2:-180}"
  local i=0
  local url="http://127.0.0.1:${port}/api/healthz"
  while true; do
    if curl -fsS --max-time 3 "${url}" >/dev/null 2>&1; then
      return 0
    fi
    if ((i >= timeout_s)); then
      return 1
    fi
    sleep 1
    i=$((i + 1))
  done
}

eog_ensure_dirs() {
  mkdir -p \
    "${EOG_INSTALL_ROOT}/config" \
    "${EOG_INSTALL_ROOT}/secrets" \
    "${EOG_INSTALL_ROOT}/data/gitea/gitea/conf" \
    "${EOG_INSTALL_ROOT}/data/tor/hidden_service" \
    "${EOG_INSTALL_ROOT}/state" \
    "${EOG_BACKUP_DIR}"
  chmod 755 "${EOG_INSTALL_ROOT}"
  chmod 750 "${EOG_INSTALL_ROOT}/secrets"
  chmod 700 "${EOG_INSTALL_ROOT}/data/tor" "${EOG_INSTALL_ROOT}/data/tor/hidden_service"
  chown root:"${EOG_GITEA_GID}" "${EOG_INSTALL_ROOT}/secrets"
  chown -R "${EOG_TOR_UID}:${EOG_TOR_GID}" "${EOG_INSTALL_ROOT}/data/tor"
  chown -R "${EOG_GITEA_UID}:${EOG_GITEA_GID}" "${EOG_INSTALL_ROOT}/data/gitea"
}

eog_write_secrets_if_missing() {
  local sdir="${EOG_INSTALL_ROOT}/secrets"
  mkdir -p "${sdir}"
  chmod 750 "${sdir}"
  chown root:"${EOG_GITEA_GID}" "${sdir}"

  if [[ ! -f "${sdir}/secret_key" ]]; then
    eog_gitea_generate_secret SECRET_KEY | eog_atomic_write "${sdir}/secret_key" 0640 "root:${EOG_GITEA_GID}"
  fi
  if [[ ! -f "${sdir}/internal_token" ]]; then
    eog_gitea_generate_secret INTERNAL_TOKEN | eog_atomic_write "${sdir}/internal_token" 0640 "root:${EOG_GITEA_GID}"
  fi
  if [[ ! -f "${sdir}/jwt_secret" ]]; then
    eog_gitea_generate_secret JWT_SECRET | eog_atomic_write "${sdir}/jwt_secret" 0640 "root:${EOG_GITEA_GID}"
  fi

  # Enforce root-owned, group-readable secrets (group = Gitea gid).
  local key
  for key in secret_key internal_token jwt_secret; do
    chown "root:${EOG_GITEA_GID}" "${sdir}/${key}"
    chmod 0640 "${sdir}/${key}"
  done
  chmod 750 "${sdir}"
  chown root:"${EOG_GITEA_GID}" "${sdir}"
}

eog_escape_sed() {
  printf '%s' "$1" | sed -e 's/[\/&]/\\&/g'
}

eog_render_app_ini() {
  local onion_host="$1"
  local require_2fa="${2:-false}"
  local tmpl="$3"
  local dest_operator="${EOG_INSTALL_ROOT}/config/app.ini"
  local dest_runtime="${EOG_INSTALL_ROOT}/data/gitea/gitea/conf/app.ini"
  local require_ini="false"
  local internal_token jwt_secret
  if [[ ${require_2fa} == "true" || ${require_2fa} == "1" ]]; then
    require_ini="true"
  fi
  [[ -f ${tmpl} ]] || eog_die "missing app.ini template: ${tmpl}"
  [[ -f "${EOG_INSTALL_ROOT}/secrets/internal_token" ]] || eog_die "missing secrets/internal_token"
  [[ -f "${EOG_INSTALL_ROOT}/secrets/jwt_secret" ]] || eog_die "missing secrets/jwt_secret"
  internal_token="$(tr -d '\r\n' <"${EOG_INSTALL_ROOT}/secrets/internal_token")"
  jwt_secret="$(tr -d '\r\n' <"${EOG_INSTALL_ROOT}/secrets/jwt_secret")"
  mkdir -p "$(dirname "${dest_runtime}")"

  local onion_esc token_esc jwt_esc
  onion_esc="$(eog_escape_sed "${onion_host}")"
  token_esc="$(eog_escape_sed "${internal_token}")"
  jwt_esc="$(eog_escape_sed "${jwt_secret}")"

  sed \
    -e "s/__ONION_HOST__/${onion_esc}/g" \
    -e "s/__REQUIRE_2FA__/${require_ini}/g" \
    -e "s/__INTERNAL_TOKEN__/${token_esc}/g" \
    -e "s/__JWT_SECRET__/${jwt_esc}/g" \
    "${tmpl}" | eog_atomic_write "${dest_operator}" 0640 "root:${EOG_GITEA_GID}"

  # Runtime copy inside the Gitea data volume (writable by the image entrypoint).
  cp -a "${dest_operator}" "${dest_runtime}"
  chown "${EOG_GITEA_UID}:${EOG_GITEA_GID}" "${dest_runtime}"
  chmod 0640 "${dest_runtime}"
}

eog_sync_app_ini_to_runtime() {
  local src="${EOG_INSTALL_ROOT}/config/app.ini"
  local dest="${EOG_INSTALL_ROOT}/data/gitea/gitea/conf/app.ini"
  [[ -f ${src} ]] || return 0
  mkdir -p "$(dirname "${dest}")"
  cp -a "${src}" "${dest}"
  chown "${EOG_GITEA_UID}:${EOG_GITEA_GID}" "${dest}"
  chmod 0640 "${dest}"
}

eog_update_app_ini_onion() {
  local onion_host="$1"
  local dest_operator="${EOG_INSTALL_ROOT}/config/app.ini"
  [[ -f ${dest_operator} ]] || return 1
  local tmp
  tmp="$(mktemp)"
  sed \
    -e "s|^DOMAIN = .*|DOMAIN = ${onion_host}|" \
    -e "s|^ROOT_URL = .*|ROOT_URL = http://${onion_host}/|" \
    "${dest_operator}" >"${tmp}"
  chmod 0640 "${tmp}"
  chown "root:${EOG_GITEA_GID}" "${tmp}"
  mv -f "${tmp}" "${dest_operator}"
  eog_sync_app_ini_to_runtime
}

eog_enforce_passkey_disabled() {
  local dest="${EOG_INSTALL_ROOT}/config/app.ini"
  [[ -f ${dest} ]] || return 1
  awk '
    BEGIN {
      in_service = 0
      saw_service = 0
      set_key = 0
    }
    /^\[service\][[:space:]]*$/ {
      in_service = 1
      saw_service = 1
      print
      next
    }
    in_service && /^\[/ {
      if (!set_key) {
        print "ENABLE_PASSKEY_AUTHENTICATION = false"
        set_key = 1
      }
      in_service = 0
    }
    in_service && /^[[:space:]]*ENABLE_PASSKEY_AUTHENTICATION[[:space:]]*=/ {
      if (!set_key) {
        print "ENABLE_PASSKEY_AUTHENTICATION = false"
        set_key = 1
      }
      next
    }
    { print }
    END {
      if (in_service && !set_key) {
        print "ENABLE_PASSKEY_AUTHENTICATION = false"
      } else if (!saw_service) {
        print ""
        print "[service]"
        print "ENABLE_PASSKEY_AUTHENTICATION = false"
      }
    }
  ' "${dest}" | eog_atomic_write "${dest}" 0640 "root:${EOG_GITEA_GID}"
}

eog_service_start() {
  systemctl start "${EOG_SERVICE_NAME}"
}

eog_service_stop() {
  systemctl stop "${EOG_SERVICE_NAME}" || true
}

eog_gitea_exec() {
  # Official image CLI should run as the git application user.
  eog_compose exec -T -u git gitea gitea "$@"
}

eog_create_admin_if_missing() {
  local user="$1"
  local password="$2"
  local email="${3:-${user}@localhost.local}"
  if eog_gitea_exec admin user list 2>/dev/null | awk '{print $2}' | grep -qx "${user}"; then
    eog_info "administrator user ${user} already exists"
    return 0
  fi
  eog_gitea_exec admin user create \
    --admin \
    --username "${user}" \
    --password "${password}" \
    --email "${email}" \
    --must-change-password=false
}

eog_disk_free_mb() {
  df -Pm "${EOG_INSTALL_ROOT%/*}" 2>/dev/null | awk 'NR==2 {print $4}'
}

eog_record_tor_identity() {
  local image="${TOR_IMAGE:-}"
  [[ -n ${image} ]] || return 0
  mkdir -p "${EOG_INSTALL_ROOT}/state"
  local digest uid gid
  digest="$(docker image inspect --format '{{index .RepoDigests 0}}' "${image}" 2>/dev/null || true)"
  if [[ -z ${digest} || ${digest} == "<no value>" ]]; then
    digest="$(docker image inspect --format '{{.Id}}' "${image}" 2>/dev/null || true)"
  fi
  [[ -n ${digest} ]] && printf '%s\n' "${digest}" >"${EOG_INSTALL_ROOT}/state/tor_image_id"

  uid="$(docker image inspect --format '{{.Config.User}}' "${image}" 2>/dev/null || true)"
  if [[ ${uid} == *:* ]]; then
    # unusual
    :
  fi
  # Resolve debian-tor uid/gid from a short-lived container.
  uid="$(docker run --rm --entrypoint /usr/bin/id "${image}" -u 2>/dev/null || true)"
  gid="$(docker run --rm --entrypoint /usr/bin/id "${image}" -g 2>/dev/null || true)"
  if [[ ${uid} =~ ^[0-9]+$ && ${gid} =~ ^[0-9]+$ ]]; then
    printf '%s\n' "${uid}" >"${EOG_INSTALL_ROOT}/state/tor_uid"
    printf '%s\n' "${gid}" >"${EOG_INSTALL_ROOT}/state/tor_gid"
    EOG_TOR_UID="${uid}"
    EOG_TOR_GID="${gid}"
    chown -R "${EOG_TOR_UID}:${EOG_TOR_GID}" "${EOG_INSTALL_ROOT}/data/tor"
    chmod 700 "${EOG_INSTALL_ROOT}/data/tor" "${EOG_INSTALL_ROOT}/data/tor/hidden_service"
  fi
}

eog_install_complete_marker() {
  printf '%s\n' "${EOG_INSTALL_ROOT}/state/install_complete"
}

eog_mark_install_complete() {
  mkdir -p "${EOG_INSTALL_ROOT}/state"
  date -u +%Y-%m-%dT%H:%M:%SZ >"$(eog_install_complete_marker)"
  chmod 600 "$(eog_install_complete_marker)"
}

eog_install_is_complete() {
  [[ -f "$(eog_install_complete_marker)" ]]
}

eog_refresh_static_files() {
  local root="$1"
  mkdir -p "${EOG_INSTALL_ROOT}/scripts" "${EOG_INSTALL_ROOT}/bin"
  install -m 0644 "${root}/compose.yml" "${EOG_INSTALL_ROOT}/compose.yml"
  install -m 0644 "${root}/Dockerfile.tor" "${EOG_INSTALL_ROOT}/Dockerfile.tor"
  install -m 0644 "${root}/Dockerfile.loopback" "${EOG_INSTALL_ROOT}/Dockerfile.loopback"
  install -m 0644 "${root}/images.lock" "${EOG_INSTALL_ROOT}/images.lock"
  install -m 0644 "${root}/config/torrc" "${EOG_INSTALL_ROOT}/config/torrc"
  install -m 0644 "${root}/config/app.ini.tmpl" "${EOG_INSTALL_ROOT}/config/app.ini.tmpl"
  install -m 0755 "${root}/bin/eog-admin" /usr/local/sbin/eog-admin
  install -m 0755 "${root}/bin/eog-admin" "${EOG_INSTALL_ROOT}/bin/eog-admin"
  install -m 0755 "${root}/scripts/"*.sh "${EOG_INSTALL_ROOT}/scripts/"
  install -m 0644 "${root}/systemd/easy-onion-gitea.service" /etc/systemd/system/easy-onion-gitea.service
  systemctl daemon-reload
  if [[ -d "${root}/docs" ]]; then
    cp -a "${root}/docs" "${EOG_INSTALL_ROOT}/"
  fi
  [[ -f "${root}/README.md" ]] && install -m 0644 "${root}/README.md" "${EOG_INSTALL_ROOT}/README.md"
  [[ -f "${root}/AGENTS.md" ]] && install -m 0644 "${root}/AGENTS.md" "${EOG_INSTALL_ROOT}/AGENTS.md"
  [[ -f "${root}/SECURITY.md" ]] && install -m 0644 "${root}/SECURITY.md" "${EOG_INSTALL_ROOT}/SECURITY.md"
  [[ -f "${root}/VERSION" ]] && install -m 0644 "${root}/VERSION" "${EOG_INSTALL_ROOT}/VERSION"
}
