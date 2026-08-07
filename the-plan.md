# easy-onion-gitea -- v0.1 design record

This is the design record for `easy-onion-gitea`. The project makes a private, Tor-reachable Gitea instance easy to deploy on a spare VPS or Linux computer. It is intended for non-developer and non-IT operators as well as teams that need to replicate Git repositories between independently administered Gitea instances. Locked decisions below match the implemented v0.1 tree; the completion checklist tracks what has been verified on a live host versus remaining acceptance work.

## Goal

Ship a small, opinionated project that turns a supported Linux host into a secure Gitea onion service with one sudo install command. The operator should end up with an onion URL, localhost access, an initial administrator account, systemd-managed reboot persistence, Tor-only Gitea egress, simple administration commands, and documented repository mirroring.

The project provides Git repository replication, not multi-master synchronization. Every mirrored repository must have one declared authoritative instance. Other instances are replicas and must not accept independent changes to mirrored refs.

## Locked platform decisions

The project name is `easy-onion-gitea`.

The server installation requires sudo. The installer refuses direct root invocation without a recoverable original user in `SUDO_USER`, unless a future explicit unattended mode safely supplies the required owner and home directory.

The container runtime is Docker Engine with the Docker Compose v2 plugin. Podman is not supported in v1.

Gitea and Tor run as containers in one Compose project. The project does not install host Tor for the server stack and does not edit `/etc/tor/torrc`.

One systemd unit named `easy-onion-gitea.service` wraps the Compose project. The unit is enabled for reboot and manages the stack as one deployment. Separate systemd units for Gitea and Tor are not used in v1.

The install root is `/opt/easy-onion-gitea`. It contains deployment configuration, Compose files, root-readable secrets, persistent data, administrative state, and version information. See **Install root layout** below for the v0.1 path map.

SQLite is the v1 database. Backup operations stop the service to obtain a consistent database snapshot.

The v1 hidden service is Tor v3 only. Onion private keys and hostname identity must survive container recreation and restore.

The initial support target is Debian and Ubuntu systems using systemd. RHEL-family support can be added after the first path is proven.

## Access and canonical URL

Gitea is available through both its onion URL and a localhost HTTP listener. The default host listener is `127.0.0.1:3000`. It must never bind to all interfaces in v1.

The installer accepts `--http-port N` to change the host-side port. The selected value is validated and persisted so re-runs retain it. A port collision causes a clear failure and directs the operator to choose another port; the installer does not silently choose one.

Docker does not wire host port mappings for containers attached only to `internal: true` networks. Host publish therefore lives on the `loopback-proxy` sidecar (socat), not on the Gitea service:

```yaml
# loopback-proxy service
ports:
  - "127.0.0.1:${HTTP_PORT}:3000"
```

Changing the host port does not change Gitea's internal port (`3000`). Tor maps onion port 80 to Gitea's static address on the internal network (`172.30.0.10:3000`). Tor does not accept Docker DNS names in `HiddenServicePort`, so the Compose `internal` subnet and Gitea `ipv4_address` are pinned.

The onion URL is Gitea's canonical `ROOT_URL`. Set `PUBLIC_URL_DETECTION=never` so untrusted Host headers cannot alter generated links. Set `LOCAL_ROOT_URL=http://gitea:3000/` for Gitea's internal workers. Local access works on the configured localhost port, but generated links and clone URLs remain canonical onion URLs.

Localhost access is intended for work performed on the server or through an SSH port forward. Tor is the intended remote access path.

## Tor-only Gitea egress

All outbound application traffic originating from Gitea must pass through Tor. This includes onion and clearnet Git mirrors, migrations, webhooks, Gitea HTTP clients, and hostname resolution associated with those operations.

Gitea connects only to an internal application network. Tor connects to that network and to an egress-capable network. Gitea must have no direct route to the internet. The design must route or contain DNS so Docker or host DNS cannot leak the names of clearnet mirror destinations. Proxy settings alone are not sufficient proof of Tor-only egress.

### Locked v0.1 network design

Use three Compose networks:

- `internal`: Gitea, Tor, and the loopback proxy attach here. Mark this network `internal: true` so it has no route to the public internet. Gitea has no other network attachment.
- `egress`: Tor attaches here so it can reach the public internet. Gitea must never attach to this network.
- `publish`: Non-internal network used only by `loopback-proxy` so Docker can wire `127.0.0.1:HTTP_PORT` (containers on internal-only networks do not get host port mappings). Gitea must never attach here.

Gitea reaches the internet only by talking to Tor on `internal`. Tor exposes its SOCKS endpoint on `internal` at a fixed service name and port (for example `tor:9050`).

Docker embedded DNS may remain available so Gitea can resolve the Compose service name `tor`. That is intentional and required for SOCKS. Gitea must not use Docker DNS, host DNS, or a public resolver for application egress destinations such as clearnet or onion mirror hostnames. All application hostname resolution for outbound work must occur through Tor remote hostname resolution via the SOCKS proxy (`socks5h`).

Configure Gitea's global HTTP proxy, webhook proxy, and Git HTTP proxy to use the Tor SOCKS endpoint with remote hostname resolution (`socks5h://tor:9050` or equivalent). Apply the proxy to all destinations, not only `*.onion`. HTTPS certificate verification remains enabled.

Acceptance tests and `eog-admin doctor` must prove defense in depth: a direct TCP connect from the Gitea container to a clearnet address fails; application egress hostnames are not usefully resolved through Docker or host DNS when Tor is stopped; and mirror traffic is observed only through Tor when Tor is available.

Disable unnecessary outbound Gitea features by default, including external avatars, OpenID, mail, Actions, and Gitea update checks. Features that introduce new egress paths remain unsupported until their Tor routing is designed and tested.

Disable passkey authentication by default because WebAuthn behavior may vary across Tor Browser security modes. Keep username/password authentication enabled and recommend TOTP two-factor authentication.

The Tor-only requirement applies to traffic originating from the Gitea application. Docker image pulls, operating-system package downloads, and installer downloads originate from the host and are outside this guarantee. Routing the entire host through Tor is not part of v1.

The server Tor SOCKS port remains internal to the Compose project and is not published on the host. Workstation Git clients use their own local Tor daemon; see **`eogit` client command**.

## Container and supply-chain requirements

Use a pinned official Gitea image. Never use a floating `latest` tag in a release.

For v0.1, ship the standard official Gitea image. Do not block v0.1 on the separate non-root Gitea image variant. Before locking secret ownership, spike the pinned image and record the uid and gid of the running Gitea application process. Official images often start as root and then run the app as a non-root user such as `git` (commonly uid 1000). Secret delivery must match that process user.

The Tor image is a security-critical component, not a minor implementation choice. Use a small project-owned `Dockerfile.tor` based on a pinned reputable distribution image and pinned Tor package. If a third-party image is considered, it must have reviewable source, active maintenance, non-root execution, multi-architecture support where promised, and a pinned digest.

### Locked v0.1 image pinning and updates

Each project release is a verified tarball or git tag checkout that contains the installer scripts, `compose.yml`, `Dockerfile.tor`, `Dockerfile.loopback`, `VERSION`, `images.lock`, templates, and documentation. Operators install and update from that release tree. v0.1 does not phone home to discover newer releases.

`images.lock` records the pinned official Gitea image by digest and the pinned base image plus Tor package inputs used by `Dockerfile.tor`. On install and update, pull the pinned Gitea digest from the registry and build the Tor and loopback-proxy images locally. Record the resulting local Tor image identity in install state. Never follow `latest`.

`eog-admin update` means the operator unpacks or checks out a newer release and runs update from that tree. With no target argument, print the installed `VERSION` and instruct the operator to download a newer release artifact; do not query GitHub or any remote channel automatically. Before replacing images it creates a backup, rebuilds Tor if needed, recreates the stack from the new release's manifests, verifies `/api/healthz` and Tor-only egress, and confirms the onion hostname is unchanged. Rollback after a failed or incompatible migration is restore from the pre-update backup, not retagging an older image.

The initial v0.1 release target is `linux/amd64`. Additional architectures may follow once the first path is proven.

Persist the complete Tor data directory so the onion identity, hidden-service private keys, and Tor state survive container recreation. The hidden-service directory and key permissions must be verified during installation and by `eog-admin doctor`.

Do not mount the Docker socket into either container. Do not use privileged mode, host networking, or unnecessary Linux capabilities. Configure bounded Docker log rotation to prevent disk exhaustion.

## systemd behavior

Use a `Type=oneshot` unit with `RemainAfterExit=yes`, `Requires=docker.service`, and ordering after `docker.service` and `network-online.target`.

The intended start operation is equivalent to `docker compose up -d --remove-orphans`. The intended stop operation is `docker compose down`. Compose services also use restart policies so a Docker daemon restart recovers the containers.

Because `RemainAfterExit=yes`, a plain `systemctl start` is a no-op when systemd already considers the unit active (common after an interrupted bootstrap that brought Tor up under the unit). Installer, backup, restore, and apply-config paths therefore stop or restart the unit rather than relying on `start` alone. Bootstrap also runs `compose down` before starting Tor so network IPAM changes apply cleanly.

The unit references the fixed install root and persisted environment file. It does not depend on a login session or a user's working directory.

Tor `torrc` must not set `User debian-tor` when the image already drops to that user via Dockerfile `USER` and Compose `cap_drop: ALL`. Tor then fails group setup and never publishes the onion hostname.

## Private-team defaults

The default deployment is private. New accounts are created by an administrator, anonymous viewing is disabled, repositories are forced private, new users keep email addresses private, and organization memberships are private by default.

The intended Gitea settings include:

```ini
[repository]
FORCE_PRIVATE = true

[service]
DISABLE_REGISTRATION = true
REQUIRE_SIGNIN_VIEW = true
DEFAULT_KEEP_EMAIL_PRIVATE = true
DEFAULT_ORG_MEMBER_VISIBLE = false
ENABLE_PASSKEY_AUTHENTICATION = false

[security]
INSTALL_LOCK = true
DISABLE_GIT_HOOKS = true
DISABLE_QUERY_AUTH_TOKEN = true

[server]
OFFLINE_MODE = true
DISABLE_SSH = true
PUBLIC_URL_DETECTION = never

[migrations]
ALLOWED_DOMAINS = *.onion
BLOCKED_DOMAINS =
ALLOW_LOCALNETWORKS = false
SKIP_TLS_VERIFY = false

[proxy]
PROXY_ENABLED = true
PROXY_URL = socks5h://tor:9050
PROXY_HOSTS = **
```

`OFFLINE_MODE = true` disables casual external integrations such as gravatar and update checks. It must not block administrator-configured mirroring, migration, or webhooks that use the Tor proxy. Verify this against the pinned Gitea release during acceptance testing; if it interferes, narrow the setting rather than weakening egress isolation.

### Locked v0.1 migration host policy

Gitea migration and mirror URL checks use `[migrations]` settings. Current Gitea behavior (verified against upstream `services/migrations/migrate.go` and the config cheat sheet):

- An empty `ALLOWED_DOMAINS` value does **not** mean deny-all. Empty means allow public "external" hosts via Gitea's builtin external matcher.
- `.onion` hostnames typically do not resolve to public IPs through normal DNS, so they fail that empty/external default. Onion remotes require an explicit pattern such as `*.onion`.
- When `ALLOWED_DOMAINS` is non-empty, only matching hostname patterns are allowed (comma-separated; wildcards supported). That replaces the builtin external whitelist.
- `ALLOW_LOCALNETWORKS` is the correct key name (not `ALLOW_LOCAL_NETWORKS`). When false, private and loopback destinations are blocked at the application SSRF layer. Current Gitea dial logic still permits connecting to the configured proxy host and port, so Tor SOCKS at `tor:9050` does not require `ALLOW_LOCALNETWORKS = true`.
- `BLOCKED_DOMAINS` denies matching hosts. `SKIP_TLS_VERIFY` must remain false.

Therefore v0.1 defaults to `ALLOWED_DOMAINS = *.onion` and `ALLOW_LOCALNETWORKS = false`. Do not ship an empty whitelist and do not ship `*`. Operators who need clearnet mirrors edit `config/app.ini` (then recreate/restart via `eog-admin`) to append approved domains, for example `*.onion,github.com,codeberg.org`. Document that changing this file is an administrative action and that `*` would allow all external hosts. Acceptance tests must cover onion pull/push mirrors with the default whitelist and a clearnet mirror after an explicit domain is added. Confirm `*.onion` matching against the pinned Gitea release during the first integration spike.

The bootstrap administrator username defaults to `gitea-admin`. Optional installer flag `--admin-user NAME` may override it on first bootstrap only. Store the chosen username in `creds.txt` and install state. Re-install never renames the account. This account is bootstrap material, not a shared daily team login. Administrators create individual users, organizations, and teams. Team members receive only the permissions they need.

Custom Git hooks remain disabled because they permit server-side code execution. SSH access and SSH push-mirror workarounds are not supported in v1. HTTP Git over Tor with personal access tokens is the supported Git transport.

Optional two-factor enforcement is controlled by installer flag `--require-2fa`, which sets Gitea's `ENFORCE_TWO_FACTOR_AUTH = true` in the generated configuration. Default is off; documentation still strongly recommends TOTP for all accounts.

## Credentials and secrets

Write the initial access details to `~/.easy-onion-gitea/creds.txt` for the original invoking user. The directory has mode 700 and the file has mode 600. Both are owned by that user. The file contains the onion URL, local URL, bootstrap administrator username, and generated administrator password.

The console summary points to the credentials file without unnecessarily repeating the password. Re-running the installer never invents or overwrites an administrator password. Password rotation is an explicit administrative operation.

The credentials file is sensitive bootstrap material. Documentation instructs the operator to change the initial password, use an individual administrator account, and securely delete or archive the file when it is no longer needed.

Generate Gitea's `SECRET_KEY`, `INTERNAL_TOKEN`, and other long-lived secrets once. Store them under the install root and pass them through Gitea's `__FILE` configuration support instead of ordinary environment variables. These secrets are included in protected backups because losing them can make encrypted Gitea data unusable.

Keep secrets under `secrets/`. The install root and secrets directory remain host-root managed: only root may create, replace, or delete secret files. Mount `secrets/` read-only into the Gitea container. File ownership and modes must allow the running Gitea application process to read `__FILE` secrets after the uid/gid spike. Preferred v0.1 pattern after the spike: parent directory mode `750` or `700` owned by root, secret files mode `640` owned `root:<gitea-group>` or owned by the container application uid under a root-owned parent that only root can modify. Do not make secrets world-readable. When the non-root Gitea image variant is adopted later, revisit ownership without weakening host permissions.

Mirrors use dedicated service accounts or narrowly scoped access tokens. Mirror credentials are entered through Gitea's authorization fields and are never embedded in repository URLs, logs, documentation, or commands.

## Mirroring model

Gitea mirroring replicates Git branches, tags, and commits. It does not continuously synchronize accounts, teams, permissions, issues, pull requests, projects, Actions data, or release attachments. Initial migration may copy some forge metadata, but later mirror runs do not keep that metadata synchronized.

Pull mirroring must be selected when the destination repository is created through migration. An existing ordinary repository cannot later be converted into a pull mirror through the normal Gitea interface.

Push mirrors force-push and can overwrite destination changes. Every mirror setup must identify the authoritative repository and warn that the replica must not be independently modified. The documentation must not describe two mirrors pushing or pulling into each other as safe bidirectional synchronization.

The supported topologies are an authoritative clearnet Gitea replicated to an onion Gitea, an authoritative onion Gitea replicated to another onion Gitea, and an authoritative easy-onion-gitea instance pushed to another supported HTTP Git remote. All outbound operations from the easy-onion-gitea server use Tor, including connections to clearnet remotes.

SSH push mirrors and `post-receive` workarounds remain outside v1. Air-gap tools such as `gitea-mirror-manager` may be mentioned as future research but are not bundled.

## `eogit` client command

Ship `eogit` as an executable Git wrapper, not as a Git alias. It gives team members a predictable way to run Git without manually configuring proxy settings:

```text
eogit clone http://example.onion/team/repo.git
eogit pull
eogit push
eogit doctor
```

For every Git invocation that may access a remote, `eogit` applies a per-process `socks5h://127.0.0.1:9050` proxy so hostname resolution occurs through Tor. This uses the workstation's local Tor daemon, not the Gitea server's internal SOCKS port. Allow an explicit configuration file or `EOGIT_TOR_PROXY` override for installations such as Tor Browser on port 9150.

Set `GIT_ALLOW_PROTOCOL=http:https` so SSH, `git://`, local file remotes, and external transport helpers cannot silently bypass Tor. Keep HTTPS certificate verification enabled. Authentication uses personal access tokens and the user's chosen Git credential helper; `eogit` does not store credentials itself.

For submodules, `eogit` sets `url.<base>.insteadOf` or equivalent configuration so common SSH and `git://` submodule URLs are rewritten to HTTPS before fetch. Submodule operations that cannot be rewritten to allowed protocols fail with a clear error instead of bypassing Tor.

Include `eogit doctor` to verify the Git executable, SOCKS listener, Tor connectivity, supported protocol restrictions, and configuration. Errors use clear ASCII-only messages and must not expose credentials.

Ship `install-client.sh` separately from the server installer. On supported client systems it installs or verifies system Tor, installs `eogit` under `/usr/local/bin`, and verifies connectivity. Installing `eogit` only on the Gitea server would not help developers' workstations.

v0.1 supported client systems are Debian and Ubuntu workstations with systemd and `apt`. The script installs the distribution `tor` package when missing and verifies a SOCKS listener on `127.0.0.1:9050`. macOS, Windows, and mobile clients are out of scope for v0.1; documentation may mention manual Tor Browser or torsocks setup without promising an installer.

## `eog-admin` server command

Install `eog-admin` under `/usr/local/sbin` as the supported root-operated administration interface. Keep its initial command set small:

```text
eog-admin status
eog-admin doctor
eog-admin backup
eog-admin restore PATH
eog-admin update
eog-admin onion
eog-admin reset-admin-password
```

`status` reports systemd, Compose, Gitea health, and Tor health without printing secrets. `doctor` verifies configuration permissions, container isolation, localhost binding, blocked direct Gitea egress, Tor DNS and SOCKS behavior, persistent onion identity, available disk space, and Gitea's `/api/healthz`.

`backup` stops the systemd service for SQLite consistency, archives Gitea repositories and data, configuration, cryptographic secrets, deployment state, and the Tor data directory, writes a manifest and checksums, then restarts the stack and verifies health. Backup files are root-readable only.

The installer runs one automatic backup after successful bootstrap and stores it under `/var/backups/easy-onion-gitea/`. No recurring backup timer is installed in v1. Documentation explains that a local snapshot protects against operator error but not host or disk loss, and directs operators to copy an encrypted backup off-host.

`restore` verifies the archive format, manifest, and checksums; makes a pre-restore safety backup; requires explicit confirmation; stops the service; restores data with correct ownership and modes; restarts the service; and verifies Gitea health and the expected onion identity.

`update` is run from a newer unpacked release tree. It makes a backup first, pulls the pinned Gitea digest, rebuilds the Tor image from that release's `Dockerfile.tor` when needed, recreates the stack, verifies `/api/healthz` and Tor-only egress, and confirms the onion hostname is unchanged. With no target it only reports the installed `VERSION` and tells the operator to obtain a newer release. It never follows `latest` and never auto-queries a remote release channel. If an update performs an incompatible database migration, recovery uses the pre-update backup rather than pretending that changing the image tag is a safe rollback.

`onion` prints the current onion hostname and URL read from persisted Tor state. It verifies that hidden-service keys exist with expected permissions. It does not rotate keys, regenerate the hostname, or print private key material.

`reset-admin-password` generates a new password for the bootstrap administrator account (`gitea-admin` unless overridden at first install), applies it through Gitea's supported administrative path, and prints a one-line reminder to store it securely. It does not rewrite `~/.easy-onion-gitea/creds.txt`; password rotation after bootstrap is an explicit operator action.

## Install root layout

The v0.1 install root is `/opt/easy-onion-gitea` with this layout:

```text
/opt/easy-onion-gitea/
  VERSION                 # project release version installed on this host
  images.lock             # pinned image digests for this release
  compose.yml             # copied from release artifact
  Dockerfile.tor          # project-owned Tor image build
  Dockerfile.loopback     # loopback publish sidecar build
  config.env              # persisted host settings (HTTP_PORT and substitutions)
  config/
    app.ini               # generated Gitea configuration
    app.ini.tmpl          # template used for first render
    torrc                 # Tor hidden service configuration
  secrets/                # host-root managed Gitea secrets for __FILE references
  data/
    gitea/                # repositories, SQLite database, attachments
    tor/                  # complete Tor data directory including onion keys
  state/                  # install_complete, admin_bootstrapped, backup markers, tor uid/gid
  bin/                    # installed eog-admin copy
  scripts/                # helpers and lib.sh
```

The systemd unit loads `config.env` from the install root. Re-running `install.sh` preserves `config.env`, `secrets/`, `data/`, and `state/`; it may refresh static templates and unit files from the release when appropriate without rotating secrets or the onion identity.

### Locked v0.1 bootstrap sequence

Gitea first-boot is handled by the installer, not the web wizard. The onion hostname must exist before Gitea is treated as configured, because `ROOT_URL` is the canonical onion URL.

Preferred sequence:

1. Create the install root, secrets, `config.env`, Tor `torrc`, and data directories.
2. Stop any stale `easy-onion-gitea.service` state, then start Tor first (Compose `up` for `tor` only).
3. Wait until the persisted Tor hidden-service `hostname` file exists. Prefer letting Tor create v3 keys on first run and reading that file. Do not hand-roll onion key generation in v0.1 unless a later need appears.
4. Write `config/app.ini` with `INSTALL_LOCK = true`, `PUBLIC_URL_DETECTION = never`, `ROOT_URL=http://<onion>/`, `LOCAL_ROOT_URL=http://gitea:3000/`, and `ENABLE_PASSKEY_AUTHENTICATION = false` (also enforced on resume when preserving an existing `app.ini`).
5. Restart the systemd unit so Gitea and `loopback-proxy` start with that configuration, wait on host `/api/healthz`, and create the bootstrap administrator `gitea-admin` (or `--admin-user`) through Gitea's supported CLI or API path.
6. Write credentials, run `eog-admin doctor`, and create the initial backup.

The web install wizard must not appear on a fresh install. Re-installs and updates must reuse the existing onion identity and must never regenerate hidden-service keys.

## Installer behavior

The intended server command is:

```text
sudo ./install.sh [--http-port N] [--admin-user NAME] [--require-2fa]
```

The installer verifies sudo usage, supported distribution, systemd, available disk space, port availability, Docker Engine, and Compose v2. It uses supported distribution packages or Docker's documented repository and does not execute an unaudited remote convenience script through a shell.

The installer creates the install root, generates secrets, writes fixed templates with validated substitutions, writes `config.env`, installs the systemd unit and `eog-admin`, follows the locked bootstrap sequence (Tor up, onion hostname present, then `app.ini` with canonical `ROOT_URL`, then Gitea health and admin creation), writes credentials, runs `eog-admin doctor`, and creates the initial backup. The initial backup briefly stops the service for SQLite consistency; documentation should mention this expected pause at the end of install.

Re-running the installer preserves the port, credentials, secrets, onion identity, and data. It reports the existing installation and directs the operator to `eog-admin` for updates, backups, restore, and password changes.

Failures stop early with plain messages, including unsupported host, missing `SUDO_USER`, occupied port, unhealthy Docker, unhealthy Tor, onion hostname timeout, Gitea health failure, unsafe permissions, or failed initial backup.

## Uninstall behavior

`uninstall.sh` is the supported removal path. Default behavior stops and disables `easy-onion-gitea.service`, removes the systemd unit, removes `/usr/local/sbin/eog-admin`, and leaves `/opt/easy-onion-gitea` and `/var/backups/easy-onion-gitea/` intact so an operator can reinstall or inspect data later.

`sudo ./uninstall.sh --purge` requires an explicit confirmation prompt. Purge removes the install root including secrets, onion keys, Gitea data, and local backup copies under `/var/backups/easy-onion-gitea/`. It does not remove `~/.easy-onion-gitea/creds.txt`; documentation tells the operator to delete that file manually. Purge is irreversible.

## Languages and file formats

Use Bash for `install.sh`, `install-client.sh`, `uninstall.sh`, `eogit`, `eog-admin`, helper scripts, and initial integration tests. These components primarily coordinate Docker, systemd, Git, Tor, archives, permissions, and health checks. Avoid adding Python for v1 because it would introduce another runtime and packaging path without a clear benefit.

All Bash scripts use `set -Eeuo pipefail`, explicit argument validation, safe temporary directories, cleanup traps, atomic file replacement, and careful quoting. Run ShellCheck and shfmt in development and CI. Do not parse structured configuration with fragile text pipelines when a fixed template or purpose-built command is available.

Use YAML for `compose.yml`, systemd unit syntax for the service, Tor configuration syntax for `torrc`, Dockerfile syntax for the project-owned Tor and loopback-proxy images, and Markdown for documentation.

If `eog-admin` later grows into complex version migrations, structured archive transformations, or a substantial interactive application, Go is the preferred replacement because it can ship as one static binary. This is not required for v1.

## Documentation and coding conventions

All code, documentation, comments, logs, command output, examples, and file contents use ASCII-only language. Do not use emojis or em dashes. Prefer clear paragraph format in documentation. Occasional short lists, outlines, and code blocks are acceptable when they improve comprehension.

Add a concise `AGENTS.md` defining these conventions, the privacy and Tor-only requirements, secret-handling rules, shell safety rules, supported architecture, test requirements, and the prohibition on weakening egress isolation for convenience. Include: do not use PC language for the sake of being PC. Terms such as "whitelist" and "blacklist" are not offensive or intended to offend; prefer the ordinary technical words when they are clear.

Add a basic `SECURITY.md` defining the threat model, supported release policy, vulnerability reporting method, security boundaries, Tor and host limitations, mirror limitations, backup sensitivity, and handling expectations for onion private keys and Gitea secrets. A real private reporting route must be selected before the first public release.

The `README.md` is operator-focused and mostly paragraph-form. It covers installation, access, credentials, individual user and team setup, client installation, `eogit`, `eog-admin`, authoritative-source mirroring, updates, backups, and recovery.

## Planned repository layout

```text
easy-onion-gitea/
  AGENTS.md
  README.md
  SECURITY.md
  Dockerfile.tor
  Dockerfile.loopback
  compose.yml
  config.env.example
  images.lock
  VERSION
  install.sh
  install-client.sh
  uninstall.sh
  bin/eog-admin
  bin/eogit
  config/torrc
  systemd/easy-onion-gitea.service
  scripts/wait-for-gitea.sh
  scripts/print-access.sh
  tests/
  docs/backup-restore.md
  docs/eogit.md
  docs/hardening.md
  docs/mirroring.md
```

## Operator and team workflows

The server operator downloads a verified release, runs `sudo ./install.sh` from that tree, waits for all health checks and the initial backup, and opens the credentials file. They can use the onion URL in Tor Browser or localhost from the server. After signing in as `gitea-admin`, they change the bootstrap password, create individual accounts, create organizations and teams, and configure authoritative repositories and replicas. Clearnet mirrors require adding approved domains to `ALLOWED_DOMAINS` before use.

Team members run `sudo ./install-client.sh` on supported Linux workstations, then use `eogit` for clone, pull, and push operations. They use individual Gitea accounts and personal access tokens, not the bootstrap administrator or shared mirror credentials.

After reboot, `systemctl status easy-onion-gitea` and `sudo eog-admin status` show deployment state. Routine administration uses `eog-admin`; operators do not need to remember raw Docker commands.

## Security boundaries and non-goals

Tor protects network location and provides authenticated onion routing, but this project cannot secure a compromised host, malicious VPS operator, compromised client, weak user password, or stolen access token. Localhost HTTP is intentionally direct and outside Tor, but is never exposed beyond loopback.

The onion address is public routing information, not an access-control secret. Gitea authentication and private repository permissions remain required. Optional Tor v3 client authorization may be researched later but is not part of v1.

The project does not provide bidirectional conflict resolution, synchronized team identities, synchronized issues or pull requests, high availability, multi-host databases, Caddy, clearnet exposure, onion TLS certificates, host-wide Tor routing, SSH Git, a backup web UI, or air-gap orchestration in v1.

## Acceptance tests

Tests must cover fresh installation, idempotent re-installation, reboot recovery, custom localhost port, port collision, file ownership and modes, administrator bootstrap, credentials preservation, health checks, and uninstall behavior.

Networking tests must prove that Gitea is bound only to loopback on the host, Tor SOCKS is not host-published, Gitea has no direct TCP egress, DNS destinations do not leak through Docker or host DNS, all clearnet and onion mirror traffic traverses Tor, and Gitea operations fail closed when Tor is unavailable.

Mirroring tests must cover onion pull mirror under the default `ALLOWED_DOMAINS = *.onion` policy, clearnet pull mirror through Tor only after an explicit approved domain is added, onion push mirror, clearnet push mirror through Tor with an approved domain, rejection of clearnet remotes when only `*.onion` is allowed, token rotation, failed credentials, synchronization scheduling, explicit force-push warnings, and preservation of the declared authoritative repository.

Client tests must cover `eogit` clone, pull, push, submodules, SOCKS failure, DNS failure, Tor Browser port override, protocol rejection, and prevention of SSH or helper-protocol bypass.

Operations tests must cover initial backup, manual backup, checksum rejection, restore, pre-restore safety backup, onion identity preservation, administrator password reset, successful update, failed update recovery, and disk-space failure.

Container tests must verify pinned images, the recorded Gitea process uid can read `__FILE` secrets, absence of privileged mode and Docker socket mounts, expected capabilities, persistent data, bounded logs, and safe behavior after Docker daemon restart.

## v0.1 completion checklist

Verified on a live Debian VM unless noted:

- [x] Project-owned pinned Tor image and persistent identity
- [x] Pinned official Gitea image and fixed Compose topology (`internal` / `egress` / `publish`, loopback-proxy)
- [x] Enforced Tor-only Gitea TCP egress (doctor clearnet probe); SOCKS reachability from Gitea
- [x] Localhost-only HTTP via loopback-proxy on configurable host port
- [x] Tor-first bootstrap with canonical onion `ROOT_URL` and Tor Browser access to the login page
- [x] Private-team Gitea defaults including passkeys disabled
- [x] Migration whitelist default `*.onion` and Tor proxy settings in rendered config
- [x] Bootstrap admin `gitea-admin` with optional `--admin-user`
- [x] Idempotent sudo installer and systemd unit (resume after interrupt; stop/restart for oneshot unit)
- [x] Host-root managed Gitea secret files using `SECRET_KEY_URI` / rendered tokens, readable by the app uid
- [x] Safe credentials file for the invoking user
- [x] Release-tree install with local Tor and loopback image builds and `images.lock`
- [x] `eog-admin` doctor and onion; post-install backup with manifest and checksums
- [x] README, AGENTS, SECURITY, mirroring, hardening, client, and recovery docs (reporting route still TBD)
- [x] ShellCheck, shfmt, and static smoke tests in CI
- [ ] `eogit` client path verified end-to-end against this onion (clone/pull/push)
- [ ] Clearnet migrate reject / allowlist opt-in and fail-closed when Tor is stopped
- [ ] Reboot persistence and full restore / update acceptance paths
- [ ] Documented uninstall retain and `--purge` exercised on a disposable host
- [ ] Public vulnerability reporting route selected before first public release

## Later work

Possible later work includes non-root Gitea, optional Tor v3 client authorization, Podman support, RHEL-family support, SSH-over-onion, encrypted off-host backup automation, air-gap mirror chaining, richer team provisioning, additional client platforms, and replacement of complex Bash administration code with a static Go binary if complexity justifies it.

## Other implementation decisions

v0.1.0 pins are recorded in `images.lock`: Gitea `1.27.1`, Debian `bookworm-slim`, and Tor Project package `0.4.9.11-1~d12.bookworm+1`. Secret files are owned `root:<gitea-gid>` mode `640` (doctor compares numeric `0:gid`). Install uses `state/install_complete` so interrupted installs can resume. Updates preserve operator `app.ini` while enforcing `ENABLE_PASSKEY_AUTHENTICATION = false`. Backup format is `easy-onion-gitea-backup-v1` (tar.gz with `MANIFEST` and `SHA256SUMS` excluding the checksum file from its own hash). RETURN traps expand temp paths at set time so `set -u` does not fail cleanup.

Live host progress: fresh install, doctor, localhost healthz, onion login in Tor Browser, and initial backup have succeeded. Remaining acceptance work is listed unchecked above and in `tests/acceptance.md` (client Git over Tor, mirroring policy, reboot, restore, update, uninstall). Select the public vulnerability reporting route before the first public release.
