# AGENTS.md

Guidance for humans and coding agents working on easy-onion-gitea.

## Language and docs

Use ASCII-only text in code, comments, logs, command output, examples, and documentation. Do not use emojis or em dashes. Prefer clear paragraphs. Short lists and code blocks are fine when they help.

Do not use PC language for the sake of being PC. Terms such as "whitelist" and "blacklist" are not offensive or intended to offend; prefer the ordinary technical words when they are clear.

## Security and privacy

Preserve Tor-only Gitea application egress. Do not weaken container network isolation for convenience. Gitea stays on the Compose `internal` network only. Tor alone may use `egress`. Host loopback HTTP is published by the `loopback-proxy` sidecar on the `publish` network; do not attach Gitea to `publish` or `egress`.

Do not mount the Docker socket into containers. Do not use privileged mode, host networking, or floating `latest` tags in releases.

Secrets live under `/opt/easy-onion-gitea/secrets`, managed by host root, readable by the Gitea application uid via `__FILE`. Never log passwords, tokens, or onion private keys.

The onion address is routing information, not an access-control secret. Private repositories and authentication remain required.

## Shell safety

Bash scripts use `set -Eeuo pipefail`, validate arguments, use safe temporary directories, cleanup traps, atomic file replacement, and careful quoting. Prefer fixed templates over fragile text parsing. Run ShellCheck and shfmt in development and CI.

## Architecture

v0.1 targets Debian/Ubuntu with systemd and Docker Compose v2 on linux/amd64. SQLite only. Canonical `ROOT_URL` is the onion URL. Localhost HTTP is loopback-only. Server Tor SOCKS is not published on the host. Client `eogit` uses the workstation Tor daemon (default `127.0.0.1:9050`).

## Tests

Do not merge changes that break install bootstrap, Tor-only egress checks, backup/restore onion identity preservation, or secret file permissions. Prefer adding acceptance coverage when behavior changes.

## Git

LLMs and AI agents must never use `git` (or `eogit`) themselves. Do not create any commits, add files, or create PRs. Leave this to the developers to do.