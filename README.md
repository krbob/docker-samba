# Docker Samba

A small Samba SMB2/SMB3 file server for a single share and user. Authenticated access is the default; writable guest access and LAN discovery are explicit opt-ins.

Published images support `linux/amd64` and `linux/arm64`. The default Compose profile uses a bridge network and publishes SMB only on `127.0.0.1:445`.

## Quick start

Create a file-backed Compose secret without putting the password in the Compose file or shell history:

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

Optionally copy `.env.example` to `.env` to persist Compose controls such as
the image tag, bind address, or secret-file path. Never store the Samba
password itself in `.env`.

The password file must contain exactly one non-empty line without leading or
trailing whitespace. The default published endpoint is available locally on
the Docker host at `//127.0.0.1/public` (or `smb://127.0.0.1/public`). Peer
containers on the Compose network can use `//samba/public`.

To make SMB reachable from a trusted LAN while keeping bridge networking, bind port 445 to one specific LAN address:

```bash
export SAMBA_BIND_ADDRESS=192.0.2.10 # replace with this host's LAN address
docker compose up -d
```

Keep this value in `.env` if it must survive a new shell. Avoid `0.0.0.0`, restrict TCP 445 with the host firewall, and never expose SMB directly to the public Internet.

## Authentication and boolean values

Choose exactly one authentication mode:

- authenticated: `SAMBA_PASSWORD_FILE` (recommended) or `SAMBA_PASSWORD`;
- anonymous: `GUEST_OK=true`, with both password variables unset.

`SAMBA_PASSWORD` and `SAMBA_PASSWORD_FILE` are mutually exclusive. Guest mode cannot be combined with either one. The share is writable by default, so `GUEST_OK=true` gives every client that can reach the service anonymous write access; combine it with `READ_ONLY=true` unless writable guest access is intentional.

The supplied Compose file enables `SAMBA_PASSWORD_FILE`. To use guest mode without keeping an unused secret mount, apply an override that unsets the variable and resets the service secret list:

```yaml
services:
  samba:
    environment:
      SAMBA_PASSWORD_FILE: null
      GUEST_OK: "true"
      READ_ONLY: "true"
    secrets: !reset []
```

All boolean options accept case-insensitive `1`, `true`, `yes`, or `on`, and `0`, `false`, `no`, or `off`. Unknown values stop startup instead of silently selecting a fallback.

## Configuration

### Compose controls

These variables are expanded by the supplied Compose files:

| Variable | Default | Purpose |
|---|---|---|
| `SAMBA_IMAGE_TAG` | `latest` | Tag used by `ghcr.io/krbob/samba` |
| `SAMBA_BIND_ADDRESS` | `127.0.0.1` | Host address used to publish TCP 445 in the default bridge profile |
| `SAMBA_PASSWORD_SECRET_FILE` | `./.secrets/samba_password` | Host path backing the Compose secret |
| `SAMBA_LAN_INTERFACE` | required by discovery profile | One host LAN interface, for example `eno1` |
| `SAMBA_LAN_NETWORK` | required by discovery profile | Trusted LAN CIDR allowed by Samba, for example `192.0.2.0/24` |

### Container variables

| Variable | Default | Purpose |
|---|---|---|
| `TZ` | `UTC` (Compose sets `Europe/Warsaw`) | Container timezone |
| `SHARE_NAME` | `public` | Share name; ASCII letters, digits, spaces, `.`, `_`, and `-`, up to 80 characters |
| `SHARE_PATH` | `/share` | Absolute in-container data path; `/` is rejected |
| `WORKGROUP` | `WORKGROUP` | Workgroup, using up to 15 ASCII letters, digits, `_`, and `-` |
| `SERVER_STRING` | `Samba Server` (Compose sets `Home Lab NAS`) | Server description |
| `FORCE_USER_UID` | `1000` | Canonical, non-zero numeric UID used for share operations |
| `FORCE_GROUP_GID` | `1000` | Canonical, non-zero numeric GID used for share operations |
| `MANAGE_SHARE_PERMISSIONS` | `true` | Create `SHARE_PATH` and set its top-level owner at startup |
| `SHARE_DIR_MODE` | unset | Optional three- or four-digit octal mode for `SHARE_PATH`; requires permission management |
| `READ_ONLY` | `false` | Make the Samba share read-only |
| `CREATE_MASK` | `0664` | Mode mask for newly created files |
| `DIRECTORY_MASK` | `0775` | Mode mask for newly created directories |
| `RECYCLE_ENABLE` | `false` | Move files deleted over SMB into the recycle repository |
| `RECYCLE_REPOSITORY` | `.recycle` | Relative repository below `SHARE_PATH`; `.` and paths containing `.`/`..` components are rejected |
| `RECYCLE_MAX_SIZE` | unset | Largest file, in bytes, moved to recycle; `0` means unlimited |
| `RECYCLE_EXCLUDE` | unset | Comma-separated file patterns that bypass recycle |
| `RECYCLE_EXCLUDE_DIR` | unset | Comma-separated directory patterns that bypass recycle |
| `SAMBA_PASSWORD` | unset | Password value; less private than a file secret because environment values are inspectable |
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
| `WSDD2_LLMNR_ENABLE` | `false` | Also enable the WSDD2 LLMNR responder; WSD-only mode is the default |
| `WSDD2_HOSTNAME` | automatic | Override the hostname announced by WSDD2 |
| `WSDD2_NETBIOS_NAME` | automatic | Override the NetBIOS name announced by WSDD2 |
| `WSDD2_WORKGROUP` | Samba workgroup | Override the workgroup announced by WSDD2 |
| `AVAHI_ENABLE` | `false` | Enable mDNS/DNS-SD discovery for macOS/Linux |
| `ALLOWED_INTERFACES` | unset | Comma-separated interface names used by WSDD2 and Avahi |

Comma is the preferred separator for `RECYCLE_EXCLUDE` and `RECYCLE_EXCLUDE_DIR`. Legacy pipe-separated values are accepted and normalized to commas. For example:

```yaml
RECYCLE_EXCLUDE: "*.tmp,*.temp,*.bak"
RECYCLE_EXCLUDE_DIR: ".recycle,tmp,cache"
```

`SMB_ENCRYPT=desired` negotiates SMB encryption with capable clients. `SMB_ENCRYPT=required` rejects clients without encrypted SMB3 support. `SMB_SIGNING=mandatory` requires signing, with a possible compatibility and throughput cost for older clients.

## Storage and permissions

The default `samba-data` named volume is mounted at `/share`. A bind mount can be substituted:

```yaml
services:
  samba:
    volumes:
      - /srv/samba:/share
```

The volume target must equal `SHARE_PATH`. If `SHARE_PATH=/data`, mount storage at `/data`; otherwise files may be written to the disposable container layer.

With the default `MANAGE_SHARE_PERMISSIONS=true`, startup creates the target if needed and changes its top-level owner to the configured Samba UID/GID. It does not recursively migrate existing files. Set `FORCE_USER_UID` and `FORCE_GROUP_GID` to the numeric owner expected by a bind mount.

For prepared or read-only storage, disable permission changes and enforce read-only access at both Samba and mount boundaries:

```yaml
services:
  samba:
    environment:
      READ_ONLY: "true"
      MANAGE_SHARE_PERMISSIONS: "false"
    volumes:
      - /srv/samba:/share:ro
```

The directory must already exist and be readable by the configured UID/GID, and `SHARE_DIR_MODE` must remain unset.

The image uses `fruit` and `streams_xattr` for macOS metadata and alternate data streams. Use a backing filesystem that supports extended attributes. Client-side NT ACL management is disabled (`nt acl support = no`), so access is primarily governed by the forced Unix identity, POSIX modes, masks, and the backing filesystem. Docker Desktop file sharing, NFS, and CIFS mounts may not preserve Linux ownership, ACL, or xattr behavior exactly.

The recycle repository is on the same filesystem and is not a backup. It is not purged automatically.

See [Backup, restore, and UID/GID migration](docs/backup-and-restore.md) before changing ownership or upgrading storage.

## Network discovery

Normal SMB access does not require discovery. Connect by host address, or use the discovery override on a trusted LAN:

```bash
export SAMBA_LAN_INTERFACE=eno1
export SAMBA_LAN_NETWORK=192.0.2.0/24

docker compose \
  -f docker-compose.yml \
  -f docker-compose.discovery.yml \
  config --quiet
docker compose \
  -f docker-compose.yml \
  -f docker-compose.discovery.yml \
  up -d
```

Replace both example values. The discovery profile:

- requires `SAMBA_LAN_INTERFACE` and `SAMBA_LAN_NETWORK`;
- switches to host networking and removes the bridge port mapping;
- restricts Samba, [WSDD2](https://github.com/Netgear/wsdd2), and Avahi to the selected interface/network;
- enables WSD for Windows and mDNS/DNS-SD for macOS/Linux;
- leaves LLMNR disabled unless `WSDD2_LLMNR_ENABLE=true` is set.

Host networking shares the host network namespace. The profile is intended for native Linux Docker hosts; multicast discovery and host networking can be unavailable or behave differently under Docker Desktop, rootless Docker, VPNs, or routed/VLAN-separated networks.

Allow only the required traffic on the trusted interface:

| Service | Ports |
|---|---|
| SMB | TCP 445 |
| WSD | UDP 3702 multicast and TCP 3702 unicast responder |
| mDNS/DNS-SD | UDP 5353 |
| LLMNR, only when enabled | UDP 5355 multicast and TCP 5355 unicast |

Legacy SMB1/NetBIOS ports 137-139 are not used. LLMNR increases the name-resolution attack surface and should remain disabled unless clients require it.

## Security notes

- This image is for trusted private networks, not direct Internet exposure.
- `FOLLOW_SYMLINKS=true` enables wide links that can expose paths outside the share when they are mounted or reachable inside the container. Enable it only for trusted users and tightly scoped mounts.
- Rotate the Samba secret periodically and after suspected disclosure.
- Preserve host firewall rules and network segmentation even when `SAMBA_HOSTS_ALLOW` is set.
- OS metadata files such as `.DS_Store`, `Thumbs.db`, `.Thumbs.db`, and `._*` are vetoed.

Report vulnerabilities according to [SECURITY.md](SECURITY.md).

## Images, upgrades, and rollback

`latest` is mutable. A `sha-<full-git-commit>` value for `SAMBA_IMAGE_TAG` identifies a specific source revision, while a recorded digest provides the strongest deployment pin. To pin a digest, replace the Compose image reference with:

```text
ghcr.io/krbob/samba@sha256:<recorded-digest>
```

Record the current digest before an upgrade:

```bash
docker inspect --format '{{index .RepoDigests 0}}' \
  "$(docker compose images -q samba)"
```

Back up the share and Compose configuration, change the tag or digest, then run `docker compose pull` followed by `docker compose up -d`. To roll back, restore the previous reference and run the same commands. Older images do not receive rebuilt operating-system packages; consult [SECURITY.md](SECURITY.md) for the support policy.

## Local development and tests

Use the development override to build the current checkout while retaining the production Compose defaults:

```bash
docker compose \
  -f docker-compose.yml \
  -f docker-compose.dev.yml \
  build
docker compose \
  -f docker-compose.yml \
  -f docker-compose.dev.yml \
  up -d
```

Run the complete smoke suite against an exact local image:

```bash
docker build -t local/samba:test .
bash tests/smoke.sh
```

The suite tests a client over the Compose network, authentication modes, input validation, recycle behavior, read-only storage, UID/GID mapping, discovery processes, transport settings, healthcheck credentials, and veto files. It creates and removes disposable containers, volumes, and temporary directories.

Advanced test controls:

| Variable | Default | Purpose |
|---|---|---|
| `SAMBA_TEST_IMAGE` | `local/samba:test` | Existing image to retag and test as `local/samba:test` |
| `SAMBA_TEST_COMPOSE_FILE` | `docker-compose-test.yml` | Compose file used for the baseline smoke test |
| `SAMBA_SMOKE_SCOPE` | `full` | `full` runs every scenario; `minimal` stops after the baseline network/authentication checks |

Process supervision is provided by [s6-overlay](https://github.com/just-containers/s6-overlay).
