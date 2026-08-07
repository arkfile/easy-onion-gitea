# easy-onion-gitea -- WIP Plan

This is a planning document for the new `easy-onion-gitea` project. The project will make a private, Tor-reachable Gitea instance easy to deploy on a spare VPS or Linux computer. It is intended for non-developer and non-IT operators as well as teams that need to replicate Git repositories between independently administered Gitea instances.

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

The Compose mapping is:

```yaml
127.0.0.1:${HTTP_PORT}:3000
```

Changing the host port does not change Gitea's internal port. Tor always maps onion port 80 to `gitea:3000` on the internal Compose network.

The onion URL is Gitea's canonical `ROOT_URL`. Set `PUBLIC_URL_DETECTION=never` so untrusted Host headers cannot alter generated links. Set `LOCAL_ROOT_URL=http://gitea:3000/` for Gitea's internal workers. Local access works on the configured localhost port, but generated links and clone URLs remain canonical onion URLs.

Localhost access is intended for work performed on the server or through an SSH port forward. Tor is the intended remote access path.

## Tor-only Gitea egress

All outbound application traffic originating from Gitea must pass through Tor. This includes onion and clearnet Git mirrors, migrations, webhooks, Gitea HTTP clients, and hostname resolution associated with those operations.

Gitea connects only to an internal application network. Tor connects to that network and to an egress-capable network. Gitea must have no direct route to the internet. The design must route or contain DNS so Docker or host DNS cannot leak the names of clearnet mirror destinations. Proxy settings alone are not sufficient proof of Tor-only egress.

### Locked v0.1 network design

Use two Compose networks:

- `internal`: Gitea and Tor both attach here. Gitea has no other network attachment. This network has no default route to the internet.
- `egress`: Tor attaches here so it can reach the public internet. Gitea must never attach to this network.

Gitea reaches the internet only by talking to Tor on `internal`. Tor exposes its SOCKS endpoint on `internal` at a fixed service name and port (for example `tor:9050`). Gitea must not receive Docker embedded DNS, host DNS, or a public resolver. If Gitea needs name resolution for outbound application work, that resolution must occur through Tor remote hostname resolution via the SOCKS proxy, not through a separate DNS path.

Configure Gitea's global HTTP proxy, webhook proxy, and Git HTTP proxy to use the Tor SOCKS endpoint with remote hostname resolution (`socks5h://tor:9050` or equivalent). Apply the proxy to all destinations, not only `*.onion`. HTTPS certificate verification remains enabled.

Acceptance tests and `eog-admin doctor` must prove defense in depth: direct TCP egress from the Gitea container fails, and clearnet mirror hostnames do not resolve through Docker or host DNS when Tor is unavailable or when DNS is observed outside Tor.

Disable unnecessary outbound Gitea features by default, including external avatars, OpenID, mail, Actions, and Gitea update checks. Features that introduce new egress paths remain unsupported until their Tor routing is designed and tested.

The Tor-only requirement applies to traffic originating from the Gitea application. Docker image pulls, operating-system package downloads, and installer downloads originate from the host and are outside this guarantee. Routing the entire host through Tor is not part of v1.

The server Tor SOCKS port remains internal to the Compose project and is not published on the host. Workstation Git clients use their own local Tor daemon; see **`eogit` client command**.

## Container and supply-chain requirements

Use a pinned official Gitea image. Never use a floating `latest` tag in a release.

For v0.1, ship the standard official Gitea image (root inside the container). Non-root Gitea remains later work once volume layout, secret delivery, administrative commands, backup, and restore are proven by tests. Do not block v0.1 on non-root Gitea.

The Tor image is a security-critical component, not a minor implementation choice. Use a small project-owned `Dockerfile.tor` based on a pinned reputable distribution image and pinned Tor package. If a third-party image is considered, it must have reviewable source, active maintenance, non-root execution, multi-architecture support where promised, and a pinned digest.

### Locked v0.1 image pinning and updates

Each release ships a version manifest under the install root. At minimum it contains the project release version and a lock file (`images.lock`) listing every container image reference by digest (Gitea and the project-built Tor image).

`install.sh` and `eog-admin update` may pull only images listed in the manifest for the target release version. Updates are explicit release-to-release operations from this project's verified release artifacts, not open-ended registry browsing and never `latest`.

`eog-admin update` accepts an optional target version argument. With no argument, it reports the installed version and the newest available supported release without changing anything. Before replacing images it creates a backup, recreates the stack from the new manifest, verifies `/api/healthz` and Tor-only egress, and confirms the onion hostname is unchanged. Rollback after a failed or incompatible migration is restore from the pre-update backup, not retagging an older image.

The initial v0.1 release target is `linux/amd64`. Additional architectures may follow once the first path is proven.

Persist the complete Tor data directory so the onion identity, hidden-service private keys, and Tor state survive container recreation. The hidden-service directory and key permissions must be verified during installation and by `eog-admin doctor`.

Do not mount the Docker socket into either container. Do not use privileged mode, host networking, or unnecessary Linux capabilities. Configure bounded Docker log rotation to prevent disk exhaustion.

## systemd behavior

Use a `Type=oneshot` unit with `RemainAfterExit=yes`, `Requires=docker.service`, and ordering after `docker.service` and `network-online.target`.

The intended start operation is equivalent to `docker compose up -d --remove-orphans`. The intended stop operation is `docker compose down`. Compose services also use restart policies so a Docker daemon restart recovers the containers.

The unit references the fixed install root and persisted environment file. It does not depend on a login session or a user's working directory.

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

[security]
INSTALL_LOCK = true
DISABLE_GIT_HOOKS = true
DISABLE_QUERY_AUTH_TOKEN = true

[server]
OFFLINE_MODE = true
DISABLE_SSH = true
PUBLIC_URL_DETECTION = never
```

`OFFLINE_MODE = true` disables casual external integrations such as gravatar and update checks. It must not block administrator-configured mirroring, migration, or webhooks that use the Tor proxy. Verify this against the pinned Gitea release during acceptance testing; if it interferes, narrow the setting rather than weakening egress isolation.

The bootstrap administrator is not a shared team account. Administrators create individual users, organizations, and teams. Team members receive only the permissions they need.

Custom Git hooks remain disabled because they permit server-side code execution. SSH access and SSH push-mirror workarounds are not supported in v1. HTTP Git over Tor with personal access tokens is the supported Git transport.

Migration access defaults to known external peers and onion destinations. The exact Gitea setting is `ALLOW_LOCALNETWORKS`, not `ALLOW_LOCAL_NETWORKS`; it remains false unless a later LAN feature explicitly requires it. At install time `ALLOWED_DOMAINS` defaults to empty; administrators add approved clearnet domains through Gitea settings when needed. Never default to `*`. `SKIP_TLS_VERIFY` remains false.

Optional two-factor enforcement is controlled by installer flag `--require-2fa`, which sets Gitea's `ENFORCE_TWO_FACTOR_AUTH = true` in the generated configuration. Default is off; documentation still strongly recommends TOTP for all accounts.

## Credentials and secrets

Write the initial access details to `~/.easy-onion-gitea/creds.txt` for the original invoking user. The directory has mode 700 and the file has mode 600. Both are owned by that user. The file contains the onion URL, local URL, bootstrap administrator username, and generated administrator password.

The console summary points to the credentials file without unnecessarily repeating the password. Re-running the installer never invents or overwrites an administrator password. Password rotation is an explicit administrative operation.

The credentials file is sensitive bootstrap material. Documentation instructs the operator to change the initial password, use an individual administrator account, and securely delete or archive the file when it is no longer needed.

Generate Gitea's `SECRET_KEY`, `INTERNAL_TOKEN`, and other long-lived secrets once. Store them in root-readable files under the install root and pass them through Gitea's `__FILE` configuration support instead of ordinary environment variables. These secrets are included in protected backups because losing them can make encrypted Gitea data unusable.

For v0.1 with the root Gitea image, keep secrets under `secrets/` with directory mode `700` and secret files mode `600`, owned by root. Mount that directory read-only into the Gitea container. The Gitea process runs as root inside the container in v0.1, so no group ownership workaround is required yet. When non-root Gitea is adopted later, revisit ownership using a fixed container UID/GID and group-readable secret files without weakening host permissions.

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

`update` makes a backup first, retrieves the approved image set for the target release from the project version manifest, recreates the stack, verifies `/api/healthz` and Tor-only egress, and confirms the onion hostname is unchanged. It never follows `latest`. If an update performs an incompatible database migration, recovery uses the pre-update backup rather than pretending that changing the image tag is a safe rollback.

`onion` prints the current onion hostname and URL read from persisted Tor state. It verifies that hidden-service keys exist with expected permissions. It does not rotate keys, regenerate the hostname, or print private key material.

`reset-admin-password` generates a new password for the bootstrap administrator account, applies it through Gitea's supported administrative path, and prints a one-line reminder to store it securely. It does not rewrite `~/.easy-onion-gitea/creds.txt`; password rotation after bootstrap is an explicit operator action.

## Install root layout

The v0.1 install root is `/opt/easy-onion-gitea` with this layout:

```text
/opt/easy-onion-gitea/
  VERSION                 # project release version installed on this host
  images.lock             # pinned image digests for this release
  compose.yml             # copied from release artifact
  config.env              # persisted host settings (HTTP_PORT and substitutions)
  config/
    app.ini               # generated Gitea configuration
    torrc                 # Tor hidden service configuration
  secrets/                # root-only Gitea secrets for __FILE references
  data/
    gitea/                # repositories, SQLite database, attachments
    tor/                  # complete Tor data directory including onion keys
  state/                  # installer and admin bookkeeping as needed
```

The systemd unit loads `config.env` from the install root. Re-running `install.sh` preserves `config.env`, `secrets/`, `data/`, and `state/`; it may refresh static templates and unit files from the release when appropriate without rotating secrets or the onion identity.

Gitea first-boot is handled by the installer, not the web wizard. The installer writes `config/app.ini` with `INSTALL_LOCK = true`, mounts persistent data, starts the stack, and creates the bootstrap administrator through Gitea's supported CLI or API path. The web install wizard must not appear on a fresh install.

## Installer behavior

The intended server command is:

```text
sudo ./install.sh [--http-port N] [--require-2fa]
```

The installer verifies sudo usage, supported distribution, systemd, available disk space, port availability, Docker Engine, and Compose v2. It uses supported distribution packages or Docker's documented repository and does not execute an unaudited remote convenience script through a shell.

The installer creates the install root, generates secrets, writes fixed templates with validated substitutions, writes `config.env` and `config/app.ini`, installs the systemd unit and `eog-admin`, enables the stack, waits on `/api/healthz`, creates the administrator idempotently, waits for Tor's onion hostname, writes credentials, runs `eog-admin doctor`, and creates the initial backup. The initial backup briefly stops the service for SQLite consistency; documentation should mention this expected pause at the end of install.

Re-running the installer preserves the port, credentials, secrets, onion identity, and data. It reports the existing installation and directs the operator to `eog-admin` for updates, backups, restore, and password changes.

Failures stop early with plain messages, including unsupported host, missing `SUDO_USER`, occupied port, unhealthy Docker, unhealthy Tor, onion hostname timeout, Gitea health failure, unsafe permissions, or failed initial backup.

## Uninstall behavior

`uninstall.sh` is the supported removal path. Default behavior stops and disables `easy-onion-gitea.service`, removes the systemd unit, removes `/usr/local/sbin/eog-admin`, and leaves `/opt/easy-onion-gitea` and `/var/backups/easy-onion-gitea/` intact so an operator can reinstall or inspect data later.

`sudo ./uninstall.sh --purge` requires an explicit confirmation prompt. Purge removes the install root including secrets, onion keys, Gitea data, and local backup copies under `/var/backups/easy-onion-gitea/`. It does not remove `~/.easy-onion-gitea/creds.txt`; documentation tells the operator to delete that file manually. Purge is irreversible.

## Languages and file formats

Use Bash for `install.sh`, `install-client.sh`, `uninstall.sh`, `eogit`, `eog-admin`, helper scripts, and initial integration tests. These components primarily coordinate Docker, systemd, Git, Tor, archives, permissions, and health checks. Avoid adding Python for v1 because it would introduce another runtime and packaging path without a clear benefit.

All Bash scripts use `set -Eeuo pipefail`, explicit argument validation, safe temporary directories, cleanup traps, atomic file replacement, and careful quoting. Run ShellCheck and shfmt in development and CI. Do not parse structured configuration with fragile text pipelines when a fixed template or purpose-built command is available.

Use YAML for `compose.yml`, systemd unit syntax for the service, Tor configuration syntax for `torrc`, Dockerfile syntax for the project-owned Tor image, and Markdown for documentation.

If `eog-admin` later grows into complex version migrations, structured archive transformations, or a substantial interactive application, Go is the preferred replacement because it can ship as one static binary. This is not required for v1.

## Documentation and coding conventions

All code, documentation, comments, logs, command output, examples, and file contents use ASCII-only language. Do not use emojis or em dashes. Prefer clear paragraph format in documentation. Occasional short lists, outlines, and code blocks are acceptable when they improve comprehension.

Add a concise `AGENTS.md` defining these conventions, the privacy and Tor-only requirements, secret-handling rules, shell safety rules, supported architecture, test requirements, and the prohibition on weakening egress isolation for convenience.

Add a basic `SECURITY.md` defining the threat model, supported release policy, vulnerability reporting method, security boundaries, Tor and host limitations, mirror limitations, backup sensitivity, and handling expectations for onion private keys and Gitea secrets. A real private reporting route must be selected before the first public release.

The `README.md` is operator-focused and mostly paragraph-form. It covers installation, access, credentials, individual user and team setup, client installation, `eogit`, `eog-admin`, authoritative-source mirroring, updates, backups, and recovery.

## Planned repository layout

```text
easy-onion-gitea/
  AGENTS.md
  README.md
  SECURITY.md
  Dockerfile.tor
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

The server operator downloads a verified release, runs `sudo ./install.sh`, waits for all health checks and the initial backup, and opens the credentials file. They can use the onion URL in Tor Browser or localhost from the server. After signing in, they change the bootstrap password, create individual accounts, create organizations and teams, and configure authoritative repositories and replicas.

Team members run `sudo ./install-client.sh` on supported Linux workstations, then use `eogit` for clone, pull, and push operations. They use individual Gitea accounts and personal access tokens, not the bootstrap administrator or shared mirror credentials.

After reboot, `systemctl status easy-onion-gitea` and `sudo eog-admin status` show deployment state. Routine administration uses `eog-admin`; operators do not need to remember raw Docker commands.

## Security boundaries and non-goals

Tor protects network location and provides authenticated onion routing, but this project cannot secure a compromised host, malicious VPS operator, compromised client, weak user password, or stolen access token. Localhost HTTP is intentionally direct and outside Tor, but is never exposed beyond loopback.

The onion address is public routing information, not an access-control secret. Gitea authentication and private repository permissions remain required. Optional Tor v3 client authorization may be researched later but is not part of v1.

The project does not provide bidirectional conflict resolution, synchronized team identities, synchronized issues or pull requests, high availability, multi-host databases, Caddy, clearnet exposure, onion TLS certificates, host-wide Tor routing, SSH Git, a backup web UI, or air-gap orchestration in v1.

## Acceptance tests

Tests must cover fresh installation, idempotent re-installation, reboot recovery, custom localhost port, port collision, file ownership and modes, administrator bootstrap, credentials preservation, health checks, and uninstall behavior.

Networking tests must prove that Gitea is bound only to loopback on the host, Tor SOCKS is not host-published, Gitea has no direct TCP egress, DNS destinations do not leak through Docker or host DNS, all clearnet and onion mirror traffic traverses Tor, and Gitea operations fail closed when Tor is unavailable.

Mirroring tests must cover onion pull mirror, clearnet pull mirror through Tor, onion push mirror, clearnet push mirror through Tor, token rotation, failed credentials, synchronization scheduling, explicit force-push warnings, and preservation of the declared authoritative repository.

Client tests must cover `eogit` clone, pull, push, submodules, SOCKS failure, DNS failure, Tor Browser port override, protocol rejection, and prevention of SSH or helper-protocol bypass.

Operations tests must cover initial backup, manual backup, checksum rejection, restore, pre-restore safety backup, onion identity preservation, administrator password reset, successful update, failed update recovery, and disk-space failure.

Container tests must verify pinned images, non-root execution where selected, absence of privileged mode and Docker socket mounts, expected capabilities, persistent data, bounded logs, and safe behavior after Docker daemon restart.

## v0.1 completion checklist

- [ ] Project-owned pinned Tor image and persistent identity
- [ ] Pinned official Gitea image (root variant for v0.1) and fixed Compose topology
- [ ] Enforced Tor-only Gitea TCP and DNS egress
- [ ] Localhost-only HTTP with configurable host port
- [ ] Canonical onion `ROOT_URL` and fixed internal URL
- [ ] Private-team Gitea defaults and individual-account workflow
- [ ] Idempotent sudo installer and systemd unit
- [ ] Root-readable Gitea secret files using `__FILE`
- [ ] Safe credentials file for the invoking user
- [ ] `eogit` and supported client installer
- [ ] Version manifest and `images.lock` wired into install and update
- [ ] `eog-admin` status, doctor, backup, restore, update, onion, and password reset
- [ ] Documented uninstall with default retain and explicit `--purge`
- [ ] Automatic post-install backup with manifest and checksums
- [ ] README, AGENTS, SECURITY, mirroring, hardening, client, and recovery docs
- [ ] ShellCheck, shfmt, and complete acceptance tests
- [ ] Verified fresh install, reboot, mirror, update, backup, and restore paths

## Later work

Possible later work includes non-root Gitea, optional Tor v3 client authorization, Podman support, RHEL-family support, SSH-over-onion, encrypted off-host backup automation, air-gap mirror chaining, richer team provisioning, additional client platforms, and replacement of complex Bash administration code with a static Go binary if complexity justifies it.

## Remaining implementation decisions

These items are still open but no longer block the overall architecture:

Select and pin the initial Debian base, Tor package, and Gitea release versions that populate `images.lock`. Prove the locked two-network Compose design in acceptance tests, including observed DNS behavior when Tor is down. Finalize backup archive format (tar structure, compression, manifest fields) and operator-facing encryption guidance; v0.1 backups are root-readable local archives and encryption for off-host copy remains operator-side unless a later feature adds it. Select the public vulnerability reporting route before the first public release.
