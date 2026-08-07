# Mirroring

easy-onion-gitea uses Gitea's built-in pull and push mirrors. Mirrors copy Git branches, tags, and commits. They do not keep accounts, teams, issues, pull requests, or release attachments continuously in sync.

## Authoritative source

Every mirrored repository must have one declared authoritative instance. Other instances are replicas. Do not treat two remotes that push or pull into each other as safe bidirectional sync. Push mirrors force-push and can overwrite destination changes.

## Whitelist

Default install sets:

```ini
[migrations]
ALLOWED_DOMAINS = *.onion
ALLOW_LOCALNETWORKS = false
SKIP_TLS_VERIFY = false
```

Empty `ALLOWED_DOMAINS` in upstream Gitea means "allow external hosts", not deny-all, and `.onion` names usually fail that default. This project therefore defaults to `*.onion`.

To allow clearnet peers, edit `/opt/easy-onion-gitea/config/app.ini` and append domains:

```ini
ALLOWED_DOMAINS = *.onion,github.com,codeberg.org
```

Then apply and restart:

```text
sudo eog-admin apply-config
```

`eog-admin update` preserves `config/app.ini` (including `ALLOWED_DOMAINS`) and only refreshes onion URL fields. Do not set `ALLOWED_DOMAINS = *` unless you intentionally allow all external hosts.

## Supported topologies

- Authoritative clearnet Gitea pulled into an onion easy-onion-gitea replica (requires clearnet domains on the whitelist).
- Authoritative onion Gitea pulled into another onion instance.
- Authoritative easy-onion-gitea pushing to another HTTP Git remote over Tor.

All outbound connections from the easy-onion-gitea server use Tor.

## Pull mirrors

Create the destination repository through Gitea's migration UI and select mirroring. An ordinary repository cannot later be converted into a pull mirror through the normal interface. Use a dedicated service account or narrowly scoped token. Do not put tokens in clone URLs or docs.

## Push mirrors

Configure push mirrors on the authoritative repository. Warn operators that the destination must not accept independent commits to mirrored refs. SSH push mirrors are not supported in v1.

## Credentials

Enter mirror credentials in Gitea's authorization fields only. Rotate tokens when people leave or when leakage is suspected.
