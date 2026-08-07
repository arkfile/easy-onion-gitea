# easy-onion-gitea

easy-onion-gitea turns a supported Debian or Ubuntu host into a private Gitea instance published as a Tor v3 onion service. One sudo install command brings up Docker Compose services for Gitea and Tor, a systemd unit for reboot persistence, localhost access for on-server work, Tor-only Gitea egress for mirrors, and simple admin commands.

This project provides Git repository replication with one authoritative source per mirrored repository. It is not multi-master synchronization.

## Requirements

- Debian or Ubuntu with systemd
- sudo for a normal user (`SUDO_USER` must be set)
- About 5 GiB free disk
- Network access for Docker image pulls and building the Tor image

Docker Engine and the Compose v2 plugin are installed by the installer if missing, using Docker's documented apt repository.

## Server install

Download or clone a release tree, then run:

```text
sudo ./install.sh
```

Optional flags:

```text
sudo ./install.sh [--http-port N] [--admin-user NAME] [--require-2fa]
```

Defaults are HTTP port `3000` on `127.0.0.1`, admin user `gitea-admin`, and 2FA not enforced.

The installer starts Tor first, waits for the onion hostname, writes Gitea config with that canonical `ROOT_URL`, starts Gitea, creates the admin user, writes credentials, runs `eog-admin doctor`, then creates an initial backup. The backup briefly stops the service for SQLite consistency.

Credentials are written to `~/.easy-onion-gitea/creds.txt` for the installing user (mode 600). Change the bootstrap password after first login. Create individual user accounts for daily work.

Passkey authentication is disabled by default because WebAuthn behavior can vary across Tor Browser security modes. Username/password authentication remains enabled; TOTP two-factor authentication is recommended.

If install is interrupted, run `sudo ./install.sh` again. Incomplete installs resume bootstrap. Completed installs refresh static files and the systemd unit without rotating secrets or the onion identity.

## Quick VM test checklist

On a fresh Debian or Ubuntu VM with sudo and internet:

```text
sudo ./install.sh
sudo eog-admin status
sudo eog-admin doctor
sudo eog-admin onion
curl -fsS http://127.0.0.1:3000/api/healthz
```

Then open the onion URL in Tor Browser using the credentials file. See `tests/acceptance.md` for deeper checks.

## Access

- Onion URL: shown after install and by `sudo eog-admin onion`. Use Tor Browser.
- Local URL: `http://127.0.0.1:3000/` (or your `--http-port`). Intended for work on the server or an SSH port forward. Generated clone URLs remain onion URLs.

Port `9050` on a developer workstation is the local Tor daemon used by `eogit`. It is not the Gitea server's internal SOCKS port.

## Client install

On Debian/Ubuntu workstations:

```text
sudo ./install-client.sh
```

Then:

```text
eogit clone http://your-service.onion/org/repo.git
eogit pull
eogit push
eogit doctor
```

Use personal access tokens with your individual Gitea account. For Tor Browser SOCKS on port 9150:

```text
export EOGIT_TOR_PROXY=socks5h://127.0.0.1:9150
```

See [docs/eogit.md](docs/eogit.md).

## Administration

```text
sudo eog-admin status
sudo eog-admin doctor
sudo eog-admin backup
sudo eog-admin restore PATH
sudo eog-admin update /path/to/new-release
sudo eog-admin onion
sudo eog-admin reset-admin-password
sudo eog-admin apply-config
```

`apply-config` syncs `/opt/easy-onion-gitea/config/app.ini` into the Gitea data volume and restarts the stack. Use it after editing migration allowlists or other Gitea settings.

Updates are release-tree operations. Unpack a newer release and pass its directory to `eog-admin update`. v0.1 does not phone home for versions.

## Mirroring

Default migration whitelist is `*.onion`. To mirror from clearnet hosts, add domains to `ALLOWED_DOMAINS` in `/opt/easy-onion-gitea/config/app.ini` (for example `*.onion,github.com`) and recreate the stack with `sudo eog-admin` / Compose. Never set `*` unless you intentionally allow all external hosts.

Every mirror needs one authoritative repository. Replicas must not take independent commits to mirrored refs. See [docs/mirroring.md](docs/mirroring.md).

## Backups and uninstall

Backups land in `/var/backups/easy-onion-gitea/` as root-readable archives with manifests and checksums. Encrypt before copying off-host. See [docs/backup-restore.md](docs/backup-restore.md).

```text
sudo ./uninstall.sh
sudo ./uninstall.sh --purge
```

Default uninstall keeps `/opt/easy-onion-gitea` and backups. `--purge` requires typing `YES` and deletes them. Credentials under `~/.easy-onion-gitea/` are not removed automatically.

## Versions pinned in this release

See `VERSION` and `images.lock`. This tree targets Gitea 1.27.1 and Tor 0.4.9.11 (Tor Project bookworm package) on Debian bookworm-slim.

## Documentation

- [docs/mirroring.md](docs/mirroring.md)
- [docs/eogit.md](docs/eogit.md)
- [docs/backup-restore.md](docs/backup-restore.md)
- [docs/hardening.md](docs/hardening.md)
- [AGENTS.md](AGENTS.md)
- [SECURITY.md](SECURITY.md)
- [the-plan.md](the-plan.md)
