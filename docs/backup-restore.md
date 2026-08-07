# Backup and restore

## What is included

`eog-admin backup` stops the stack for a consistent SQLite snapshot, then archives:

- Gitea data (repositories, database, attachments)
- Tor data directory (including onion keys)
- `config/`, `secrets/`, `config.env`, `state/`
- `VERSION`, `images.lock`, `compose.yml`, `Dockerfile.tor`
- `scripts/`, `bin/eog-admin`, and the systemd unit when present
- `MANIFEST` and `SHA256SUMS` (checksums exclude the checksum file itself)

Archives are written under `/var/backups/easy-onion-gitea/` with mode 600.

## Encryption

v0.1 does not encrypt backups itself. Before copying a backup off the host, encrypt it with a tool you trust (for example age or GnuPG). A local snapshot protects against operator mistakes; it does not protect against host or disk loss.

## Restore

```text
sudo eog-admin restore /var/backups/easy-onion-gitea/easy-onion-gitea-YYYYMMDDThhmmssZ.tar.gz
```

Restore verifies checksums, asks you to type `YES`, creates a pre-restore safety backup, replaces install data, restores admin tooling when present in the archive, rebuilds the Tor image when `Dockerfile.tor` is present, restarts the stack, checks `/api/healthz`, and confirms the onion hostname matches the manifest.

Prefer keeping a release tree available on the host for updates even after restore.

## Update recovery

`eog-admin update` creates a backup first. If a Gitea database migration is incompatible or health checks fail, restore that pre-update backup. Do not treat retagging an older image as a safe rollback after a migration.
