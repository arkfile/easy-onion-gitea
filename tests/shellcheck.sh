#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

files=(
  install.sh
  install-client.sh
  uninstall.sh
  bin/eog-admin
  bin/eogit
  scripts/lib.sh
  scripts/wait-for-gitea.sh
  scripts/wait-for-onion.sh
  scripts/print-access.sh
  tests/shellcheck.sh
  tests/smoke-static.sh
)

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "shellcheck not installed; skipping"
  exit 0
fi

# Info-level source-follow noise is ignored; warnings and errors fail the job.
shellcheck -x -S warning "${files[@]}"
echo "shellcheck OK"
