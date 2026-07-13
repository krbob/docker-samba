# Configuration

This document is the reference for the supplied Compose files and the
environment variables accepted by `ghcr.io/krbob/samba`. The image manages one
share and one fixed Samba username, `samba`.

## Authentication

Choose exactly one mode:

- authenticated: set `SAMBA_PASSWORD_FILE` (recommended) or
  `SAMBA_PASSWORD`;
- anonymous: set `GUEST_OK=true` and leave both password variables unset.

`SAMBA_PASSWORD` and `SAMBA_PASSWORD_FILE` are mutually exclusive. Guest mode
cannot be combined with either one. The share is writable by default, so guest
mode gives every client that can reach the service anonymous write access.
Combine it with `READ_ONLY=true` unless writable guest access is intentional.

The supplied Compose file mounts a file-backed secret and sets
`SAMBA_PASSWORD_FILE=/run/secrets/samba_password`. A password file must contain
exactly one non-empty line without leading or trailing whitespace.

Use the supplied override for explicit read-only guest access:

```bash
docker compose \
  -f docker-compose.yml \
  -f docker-compose.guest.yml \
  config --quiet
docker compose \
  -f docker-compose.yml \
  -f docker-compose.guest.yml \
  up -d
```

The override removes the inherited password variable with
`SAMBA_PASSWORD_FILE: !reset null`, removes the secret mount, enables guest
access, and sets `READ_ONLY=true`. The `!reset` tag requires Docker Compose
2.18.0 or newer.

## Boolean values

Boolean options accept these case-insensitive forms:

- true: `1`, `true`, `yes`, `on`;
- false: `0`, `false`, `no`, `off`.

Unknown values stop startup instead of silently selecting a fallback.

## Compose controls

These values are expanded by the supplied Compose files. They configure
Compose itself rather than being general container variables.

| Variable | Default | Purpose |
|---|---|---|
| `SAMBA_IMAGE_TAG` | `latest` | Tag used by `ghcr.io/krbob/samba` |
| `SAMBA_BIND_ADDRESS` | `127.0.0.1` | Host address used to publish TCP 445 in the base configuration |
| `SAMBA_PASSWORD_SECRET_FILE` | `./.secrets/samba_password` | Host path backing the Compose secret |
| `SAMBA_LAN_INTERFACE` | required by discovery override | One host LAN interface, for example `eno1` |
| `SAMBA_LAN_NETWORK` | required by discovery override | Trusted client CIDR allowed by Samba, for example `192.0.2.0/24` |
| `WSDD2_LLMNR_ENABLE` | `0` | Enable LLMNR when using the discovery override |

Copy `.env.example` to `.env` to persist these values. Never put the Samba
password in `.env`.

Values in `.env` are used only where a Compose file contains `${...}`
interpolation. They do not automatically become container environment
variables. To change `SHARE_NAME`, `TZ`, UID/GID, or another runtime setting,
use a Compose override:

```yaml
services:
  samba:
    environment:
      TZ: Europe/Warsaw
      SHARE_NAME: storage
      FORCE_USER_UID: "1000"
      FORCE_GROUP_GID: "1000"
```

## Container variables

| Variable | Default | Purpose |
|---|---|---|
| `TZ` | `UTC` (base Compose sets `Europe/Warsaw`) | Container timezone |
| `SHARE_NAME` | `public` | Share name; up to 80 ASCII letters, digits, spaces, `.`, `_`, and `-`; no edge spaces or reserved section names |
| `SHARE_PATH` | `/share` | Absolute in-container data path; `/` is rejected |
| `WORKGROUP` | `WORKGROUP` | Workgroup; up to 15 ASCII letters, digits, `_`, and `-` |
| `SERVER_STRING` | `Samba Server` (base Compose sets `Home Lab NAS`) | Server description |
| `FORCE_USER_UID` | `1000` | Canonical numeric UID from `1` through `4294967294`, not already assigned to another container account |
| `FORCE_GROUP_GID` | `1000` | Canonical numeric GID from `1` through `4294967294`, not already assigned to another container group |
| `MANAGE_SHARE_PERMISSIONS` | `true` | Create `SHARE_PATH` and set its top-level owner at startup |
| `SHARE_DIR_MODE` | unset | Optional three- or four-digit octal mode for `SHARE_PATH`; requires permission management |
| `READ_ONLY` | `false` | Make the Samba share read-only |
| `CREATE_MASK` | `0664` | Mode mask for newly created files |
| `DIRECTORY_MASK` | `0775` | Mode mask for newly created directories |
| `RECYCLE_ENABLE` | `false` | Move files deleted over SMB into the recycle repository |
| `RECYCLE_REPOSITORY` | `.recycle` | Relative repository below `SHARE_PATH` |
| `RECYCLE_MAX_SIZE` | unset | Largest file, in bytes, moved to recycle; `0` means unlimited |
| `RECYCLE_EXCLUDE` | unset | Comma-separated file patterns that bypass recycle |
| `RECYCLE_EXCLUDE_DIR` | unset | Comma-separated directory patterns that bypass recycle |
| `SAMBA_PASSWORD` | unset | Single-line password without leading or trailing whitespace; less private than a file secret because environment values are inspectable |
| `SAMBA_PASSWORD_FILE` | unset | In-container path to a one-line password file |
| `LOG_LEVEL` | `1` | Samba log level from `0` through `10` |
| `SAMBA_INTERFACES` | unset | Samba listener interfaces or addresses, for example `lo eno1` |
| `SAMBA_BIND_INTERFACES_ONLY` | `false` | Bind Samba only to `SAMBA_INTERFACES`; loopback must be included for the healthcheck |
| `SAMBA_HOSTS_ALLOW` | unset | Samba client allow-list, for example `192.0.2.0/24 127.0.0.0/8` |
| `SMB_ENCRYPT` | unset | `default`, `if_required`, `desired`, `required`, or `off` |
| `SMB_SIGNING` | unset | `default`, `auto`, `mandatory`, or `disabled` |
| `FOLLOW_SYMLINKS` | `false` | Enable Samba wide links outside `SHARE_PATH` inside the container |
| `GUEST_OK` | `false` | Enable anonymous access instead of password authentication |
| `WSDD2_ENABLE` | `false` | Enable Windows Web Service Discovery |
| `WSDD2_LLMNR_ENABLE` | `false` | Also enable the WSDD2 LLMNR responder |
| `WSDD2_HOSTNAME` | automatic | Override the hostname announced by WSDD2 |
| `WSDD2_NETBIOS_NAME` | automatic | Override the NetBIOS name announced by WSDD2 |
| `WSDD2_WORKGROUP` | Samba workgroup | Override the workgroup announced by WSDD2 |
| `AVAHI_ENABLE` | `false` | Enable mDNS/DNS-SD discovery for macOS and Linux |
| `ALLOWED_INTERFACES` | unset | Comma-separated interface names used by WSDD2 and Avahi; each entry is limited to 15 characters |

Invalid names, paths, modes, identities, enums, or conflicting authentication
settings stop the container before its Samba identity or mounted share is
modified.

Reserved share names are `.`, `..`, `global`, `homes`, and `printers`, matched
case-insensitively. `ALLOWED_INTERFACES` accepts non-empty interface names made
from ASCII letters, digits, `_`, `-`, `.`, and `:`.

## Storage and permissions

The base Compose configuration mounts the `samba-data` named volume at
`/share`. A bind mount can replace it:

```yaml
services:
  samba:
    volumes:
      - /srv/samba:/share
```

The target must equal `SHARE_PATH`. If `SHARE_PATH=/data`, mount storage at
`/data`; otherwise files may be written to the disposable container layer.

With `MANAGE_SHARE_PERMISSIONS=true`, startup creates the target if needed and
changes only its top-level owner to `FORCE_USER_UID:FORCE_GROUP_GID`. It does
not recursively migrate existing files. Match both numeric IDs to the owner
expected by a bind mount.

For prepared or read-only storage, disable permission changes and enforce
read-only access at both Samba and mount boundaries:

```yaml
services:
  samba:
    environment:
      READ_ONLY: "true"
      MANAGE_SHARE_PERMISSIONS: "false"
    volumes:
      - /srv/samba:/share:ro
```

The directory must already exist and be readable by the configured UID/GID,
and `SHARE_DIR_MODE` must remain unset.

The image uses `fruit` and `streams_xattr` for macOS metadata and alternate
data streams. Use a backing filesystem that supports extended attributes.
Docker Desktop file sharing, NFS, and CIFS mounts may not preserve Linux
ownership, ACL, or xattr behavior exactly.

Client-side NT ACL management is disabled (`nt acl support = no`). Access is
primarily governed by the forced Unix identity, POSIX modes, masks, and the
backing filesystem.

## Recycle bin

Enable the recycle VFS module with `RECYCLE_ENABLE=true`. Deleted files remain
on the same filesystem under `RECYCLE_REPOSITORY`; they are not purged
automatically and do not replace backups.

The repository must be a relative path below `SHARE_PATH`. Absolute paths and
`.` or `..` path components are rejected.

Comma is the preferred separator for exclusion patterns:

```yaml
RECYCLE_EXCLUDE: "*.tmp,*.temp,*.bak"
RECYCLE_EXCLUDE_DIR: ".recycle,tmp,cache"
```

Legacy pipe-separated values are accepted and normalized to commas.

## SMB transport protection

`SMB_ENCRYPT=desired` negotiates encryption with capable clients.
`SMB_ENCRYPT=required` rejects clients without encrypted SMB3 support.
`SMB_SIGNING=mandatory` requires signing, with a possible compatibility and
throughput cost for older clients.

Keep the host firewall and network segmentation in place even when
`SAMBA_HOSTS_ALLOW` is set.

## Symbolic links

`FOLLOW_SYMLINKS=true` enables Samba wide links. It can expose paths outside
the share when those paths are mounted or otherwise reachable inside the
container. Enable it only for trusted users and tightly scoped mounts.

See also:

- [Networking and discovery](networking.md)
- [Operations and troubleshooting](operations.md)
- [Backup, restore, and UID/GID migration](backup-and-restore.md)
