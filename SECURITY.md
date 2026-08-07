# Security policy

## Threat model

easy-onion-gitea helps operators run a private Gitea instance reachable as a Tor v3 onion service, with Tor-only application egress for mirrors and related outbound traffic.

This project cannot protect a compromised host, a malicious VPS operator, a compromised client, a weak user password, or a stolen personal access token. Localhost HTTP on the server is intentionally outside Tor and must remain bound to loopback only.

The onion address is public routing information. It is not a password. Gitea authentication and private repository permissions remain required.

## Security boundaries

- Gitea has no Docker egress network attachment; outbound application traffic must use the internal Tor SOCKS endpoint.
- Host localhost HTTP is published only through the loopback-proxy sidecar; Gitea itself is not attached to the Compose `publish` or `egress` networks.
- Host package installs, Docker image pulls, and installer downloads are outside the Tor-only guarantee.
- Custom Git hooks are disabled. SSH Git is disabled in v1. Passkey (WebAuthn) authentication is disabled by default.
- Migration destination hosts are limited by Gitea `ALLOWED_DOMAINS` (default `*.onion`).
- Backups contain repositories, SQLite data, Gitea secrets, and Tor hidden-service keys. Treat them as highly sensitive. v0.1 writes root-readable local archives; encrypt before copying off-host.

## Supported versions

Security fixes target the latest released easy-onion-gitea version on the main release line. Older releases may not receive backports until a support policy is expanded.

## Reporting vulnerabilities

A private reporting route will be published before the first public release. Until then, if you have a coordinated disclosure channel with the maintainers, use that channel and do not file public issues with exploit details.

## Handling onion keys and Gitea secrets

Onion private keys under `data/tor/hidden_service` and files under `secrets/` must not appear in logs, tickets, or chat. Rotate Gitea admin passwords with `eog-admin reset-admin-password`. Onion identity rotation is out of scope for v0.1 routine operations; restoring a backup restores the same onion identity.
