# Acceptance tests

Run on a disposable Debian/Ubuntu VM with Docker available.

## Install and basics

1. Fresh `sudo ./install.sh` completes doctor and initial backup.
2. Interrupt mid-install (Ctrl-C after Tor starts) and re-run `sudo ./install.sh`; bootstrap resumes and finishes.
3. Re-run `sudo ./install.sh` on a completed install refreshes static files and exits without rotating secrets.
4. `curl -fsS http://127.0.0.1:3000/api/healthz` succeeds.
5. Host listen address is only `127.0.0.1:3000` (or custom `--http-port`).
6. No host publish of Tor SOCKS on `0.0.0.0:9050`.
7. `sudo eog-admin onion` prints the hostname; keys are not printed.
8. Secret files under `/opt/easy-onion-gitea/secrets` are mode `640` owned `root:1000` (or recorded gitea gid).
9. Reboot; `systemctl status easy-onion-gitea` is active; healthz succeeds.

## Networking

1. `sudo eog-admin doctor` reports direct clearnet egress blocked with proxies cleared.
2. Doctor reports Gitea resolves `tor` and can reach Tor SOCKS when `nc` is available.
3. With Tor stopped (`docker compose stop tor`), clearnet/onion mirror attempts fail closed.
4. Clearnet migrate is rejected until `ALLOWED_DOMAINS` is extended and `sudo eog-admin apply-config` is run.

## Operations

1. `sudo eog-admin backup` produces archive with MANIFEST and SHA256SUMS; restore accepts it.
2. Corrupt checksum is rejected by restore.
3. Restore preserves onion identity.
4. `sudo eog-admin reset-admin-password` sets a new password without rewriting creds.txt.
5. Edit `ALLOWED_DOMAINS`, run `sudo eog-admin apply-config`, confirm setting sticks after restart.
6. `sudo eog-admin update /path/to/same-or-newer-release` keeps onion identity and preserves `ALLOWED_DOMAINS`.
7. `sudo ./uninstall.sh` removes unit and keeps data; `--purge` deletes data after YES.

## Client

1. `sudo ./install-client.sh` then `eogit doctor`.
2. `eogit clone` over onion with a PAT.
3. `EOGIT_TOR_PROXY=socks5h://127.0.0.1:9150` override path.
4. SSH remote rejected / not used via GIT_ALLOW_PROTOCOL.
