# Hardening notes

## Network

- Host HTTP is published only on `127.0.0.1` via the `loopback-proxy` sidecar.
- Tor SOCKS is internal to Compose and must not be published on the host.
- Gitea attaches only to the `internal` Compose network (`internal: true`).
- Docker does not wire host port mappings for containers on internal-only networks, so `loopback-proxy` attaches to `internal` plus a non-internal `publish` network and forwards to Gitea's static IP.
- Tor attaches to `internal` and `egress`. Gitea must never attach to `egress` or `publish`.
- Application egress uses SOCKS to `tor:9050` with remote hostname resolution.

## Gitea defaults

Private-team defaults disable open registration, force private repositories, disable SSH Git, disable custom Git hooks, disable Actions, disable mailer and OpenID, and set `OFFLINE_MODE`. Migration whitelist defaults to `*.onion`.

Optional install flag `--require-2fa` sets `ENFORCE_TWO_FACTOR_AUTH`. TOTP is recommended for all accounts even when not enforced.

## Secrets

Host root manages `/opt/easy-onion-gitea/secrets`. Secret files are owned `root:<gitea-gid>` with mode `640`, and the directory is mode `750`. The Gitea process gid can read them; ordinary host users should not be able to modify them. `SECRET_KEY` is referenced through `SECRET_KEY_URI=file:/run/eog-secrets/secret_key`. `INTERNAL_TOKEN` and `JWT_SECRET` are rendered into `config/app.ini` (mode 640) from those secret files.

## Operator practice

- Change the bootstrap `gitea-admin` password immediately.
- Create personal admin and developer accounts.
- Use narrowly scoped tokens for mirrors.
- Encrypt backups before off-host copy.
- Keep the host patched; Tor-only Gitea egress does not harden the host itself.
