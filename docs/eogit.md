# eogit

`eogit` is a small Git wrapper for team workstations. It forces remote Git traffic through a local Tor SOCKS proxy so developers do not have to remember proxy environment variables.

## Install

On Debian or Ubuntu:

```text
sudo ./install-client.sh
```

This installs the distribution `tor` package if needed, enables it, installs `/usr/local/bin/eogit`, and runs `eogit doctor`.

## Usage

```text
eogit clone http://example.onion/team/repo.git
eogit pull
eogit push
eogit doctor
```

Authentication uses personal access tokens and your normal Git credential helper. `eogit` does not store passwords.

## Proxy settings

Default proxy: `socks5h://127.0.0.1:9050` (system Tor on the workstation).

Overrides:

```text
export EOGIT_TOR_PROXY=socks5h://127.0.0.1:9150
```

Or create `~/.config/eogit/config`:

```bash
EOGIT_TOR_PROXY_FROM_CONFIG=socks5h://127.0.0.1:9150
```

The workstation Tor listener is unrelated to the Gitea server's internal Tor container.

## Protocol restrictions

`eogit` sets `GIT_ALLOW_PROTOCOL=http:https` so SSH, `git://`, and helper protocols cannot silently bypass Tor. Common `git@` and `git://` submodule URLs are rewritten toward HTTPS when possible. Operations that still require disallowed protocols fail with an error.

HTTPS certificate verification remains enabled.
