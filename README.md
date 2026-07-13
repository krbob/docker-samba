# Docker Samba

[![CI](https://github.com/krbob/docker-samba/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/krbob/docker-samba/actions/workflows/ci.yml)
[![GHCR](https://img.shields.io/badge/GHCR-ghcr.io%2Fkrbob%2Fsamba-2496ED?logo=github)](https://github.com/krbob/docker-samba/pkgs/container/samba)

A secure-by-default Samba SMB2/SMB3 file server for one share and one user.
Password authentication is the default; guest access and LAN discovery are
explicit opt-ins.

The published image is available as `ghcr.io/krbob/samba` for `linux/amd64`
and `linux/arm64`.

> [!WARNING]
> This image is intended for trusted private networks. Never expose SMB or its
> discovery services directly to the public Internet.

## Features

- SMB2/SMB3 only, with SMB1 and legacy NetBIOS ports disabled;
- one configurable share backed by a named volume or bind mount;
- password authentication, read-only mode, or explicit guest access;
- optional recycle bin, SMB encryption, and mandatory signing;
- macOS metadata and alternate streams through `fruit` and `streams_xattr`;
- optional WSD discovery for Windows and mDNS/DNS-SD for macOS and Linux;
- built-in healthcheck and multi-architecture images tested before publishing.

## Quick start

### Requirements

- Docker Engine or Docker Desktop;
- Docker Compose 2.18.0 or newer;
- an available TCP port 445 on the selected host address.

Run the following commands from a checkout of this repository. They create a
file-backed Compose secret without putting the password in the Compose file or
shell history:

```bash
mkdir -p .secrets
chmod 700 .secrets
(
  umask 077
  read -rsp 'Samba password: ' samba_password
  printf '\n'
  printf '%s\n' "${samba_password}" > .secrets/samba_password
)
chmod 600 .secrets/samba_password

docker compose config --quiet
docker compose pull
docker compose up -d
docker compose ps
```

The service should become `healthy`. If it does not, inspect startup validation
without printing the secret:

```bash
docker compose logs --tail=100 samba
```

The base configuration publishes SMB only on the Docker host's loopback
address. Connect with username `samba` and the password entered above:

| Client | Address |
|---|---|
| Windows | `\\127.0.0.1\public` |
| macOS | `smb://127.0.0.1/public` |
| Linux | `smb://127.0.0.1/public` or `smbclient //127.0.0.1/public -U samba` |

The password file must contain exactly one non-empty line without leading or
trailing whitespace. Copy `.env.example` to `.env` to persist Compose controls
such as the image tag, bind address, or secret-file path. Do not store the
Samba password itself in `.env`.

## Choose network exposure

| Mode | Reachability | Discovery | Intended host |
|---|---|---|---|
| Base configuration | Docker host only, `127.0.0.1:445` | None | Any supported Docker host |
| Bridge with LAN bind | One selected LAN address | None; connect by address or DNS | Any supported Docker host |
| Discovery override | Host network | WSD and mDNS/DNS-SD | Native Linux on a trusted LAN |

For direct LAN access without multicast discovery, bind port 445 to one
specific host address:

```bash
SAMBA_BIND_ADDRESS=192.0.2.10 docker compose up -d
```

Replace the documentation address and keep the value in `.env` if it must
persist. Avoid `0.0.0.0`, restrict TCP 445 with the host firewall, and connect
to `\\192.0.2.10\public` or `smb://192.0.2.10/public`.

For Windows and Bonjour discovery on a native Linux host, use the supplied
override:

```bash
SAMBA_LAN_INTERFACE=eno1 SAMBA_LAN_NETWORK=192.0.2.0/24 \
  docker compose \
    -f docker-compose.yml \
    -f docker-compose.discovery.yml \
    up -d
```

See [Networking and discovery](docs/networking.md) for firewall ports,
interface restrictions, LLMNR, platform limitations, and troubleshooting.

## Common configuration

| Goal | Main settings |
|---|---|
| Rename the share | `SHARE_NAME` |
| Use host storage | bind mount whose target equals `SHARE_PATH`, plus matching `FORCE_USER_UID` and `FORCE_GROUP_GID` |
| Enforce read-only access | `READ_ONLY=true`, a read-only mount, and `MANAGE_SHARE_PERMISSIONS=false` |
| Enable anonymous read-only access | apply [`docker-compose.guest.yml`](docker-compose.guest.yml); writable guest access requires an intentional additional override |
| Retain SMB-deleted files | `RECYCLE_ENABLE=true` and the `RECYCLE_*` settings |
| Protect SMB transport | `SMB_ENCRYPT` and `SMB_SIGNING` |

The full environment-variable reference, validation rules, and Compose
examples are in [Configuration](docs/configuration.md).

## Data safety

The volume target must equal `SHARE_PATH`; otherwise data may be written to the
disposable container layer. Startup changes only the top-level share owner and
does not recursively migrate existing files. The backing filesystem should
preserve numeric ownership and extended attributes.

The recycle directory is on the same filesystem and is not a backup. Read
[Backup, restore, and UID/GID migration](docs/backup-and-restore.md) before
changing ownership, storage, or the image reference.

## Images and updates

`latest` is mutable. Every successful main-branch build also publishes
`sha-<full-git-commit>`. A recorded digest is the strongest deployment pin:

```text
ghcr.io/krbob/samba@sha256:<recorded-digest>
```

Back up the share and record the current digest before updating. Then recreate,
rather than merely restart, the service:

```bash
docker compose pull
docker compose up -d
docker compose ps
```

See [Operations](docs/operations.md) for digest pinning, rollback, health and
troubleshooting.

## Limits

- the container manages one share and one fixed Samba username, `samba`;
- client-side NT ACL management is disabled; access is governed by the forced
  Unix identity, POSIX modes, masks, and the backing filesystem;
- discovery is designed primarily for native Linux hosts and a single trusted
  LAN segment;
- older commit-tagged images are immutable snapshots and are not rebuilt with
  operating-system security updates.

## Documentation

- [Configuration reference](docs/configuration.md)
- [Networking and discovery](docs/networking.md)
- [Operations and troubleshooting](docs/operations.md)
- [Backup, restore, and UID/GID migration](docs/backup-and-restore.md)
- [Security policy](SECURITY.md)
- [Contributing](CONTRIBUTING.md)
- [Changelog](CHANGELOG.md)

Process supervision is provided by
[s6-overlay](https://github.com/just-containers/s6-overlay).
