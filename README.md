# Docker Samba

Simple Samba (SMB) file server in Docker. Single share with minimal setup for either authenticated access or a deliberate guest share on a trusted LAN.

## Usage

```yaml
services:
  samba:
    image: ghcr.io/krbob/samba:latest
    container_name: samba
    restart: unless-stopped
    network_mode: host
    cap_add:
      - CAP_NET_ADMIN
      - CAP_NET_RAW
    environment:
      TZ: Europe/Warsaw
      SHARE_NAME: public
      SAMBA_PASSWORD: "replace-with-a-strong-password"
      # GUEST_OK: "1"
      # SAMBA_HOSTS_ALLOW: "192.168.1.0/24 127.0.0.0/8"
      # WSDD2_ENABLE: "1"
      # WSDD2_HOSTNAME: "homelab"
      # WSDD2_NETBIOS_NAME: "HOMELAB"
      # AVAHI_ENABLE: "1"
      # ALLOWED_INTERFACES: "eno1"
    volumes:
      - samba-data:/share

volumes:
  samba-data:
    driver: local
```

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `TZ` | `UTC` | Timezone (e.g. `Europe/Warsaw`) |
| `SHARE_NAME` | `public` | Share name |
| `SHARE_PATH` | `/share` | Path inside container |
| `WORKGROUP` | `WORKGROUP` | SMB workgroup |
| `SERVER_STRING` | `Samba Server` | Server description |
| `FORCE_USER_UID` | `1000` | UID for file operations |
| `FORCE_GROUP_GID` | `1000` | GID for file operations |
| `SHARE_DIR_MODE` | *(unset)* | Optional mode to apply to `SHARE_PATH` at startup (e.g. `0777`) |
| `SAMBA_PASSWORD` | *(required unless `GUEST_OK=1`)* | Password for the `samba` user |
| `LOG_LEVEL` | `1` | Log verbosity (0=minimal, 3=debug) |
| `SAMBA_HOSTS_ALLOW` | *(unset)* | Restrict access to specific networks (e.g. `192.168.1.0/24 127.0.0.0/8`) |
| `WSDD2_ENABLE` | *(unset)* | Set to `1` to enable WSDD2 (Windows network discovery) |
| `WSDD2_HOSTNAME` | *(unset)* | Override the hostname announced by WSDD2 |
| `WSDD2_NETBIOS_NAME` | *(unset)* | Override the NetBIOS name announced by WSDD2 |
| `WSDD2_WORKGROUP` | *(unset)* | Override the workgroup announced by WSDD2 (defaults to `WORKGROUP` env if set) |
| `AVAHI_ENABLE` | *(unset)* | Set to `1` to enable Avahi (macOS/Linux network discovery) |
| `ALLOWED_INTERFACES` | *(unset)* | Restrict WSDD2/Avahi to specific interfaces (e.g. `eno1,br0`) |
| `FOLLOW_SYMLINKS` | *(unset)* | Set to `1` to allow symlinks inside the share |
| `GUEST_OK` | *(unset)* | Set to `1` to allow anonymous access (no password required) |

Set either `SAMBA_PASSWORD` for authenticated access or `GUEST_OK=1` for an anonymous guest share. Leaving both unset is treated as a configuration error.

## Network Discovery

By default, the share must be accessed by IP address. To enable automatic discovery:

- **Windows**: Set `WSDD2_ENABLE=1` — uses [WSDD2](https://github.com/christgau/wsdd2) for Web Service Discovery
- **macOS/Linux**: Set `AVAHI_ENABLE=1` — uses [Avahi](https://avahi.org/) for mDNS/DNS-SD (Finder sidebar discovery)

Windows discovery also requires `CAP_NET_RAW` for `wsdd2` in addition to `CAP_NET_ADMIN`.

Both discovery methods require `network_mode: host` (see compose example above).

## Storage

By default, data is stored in a Docker named volume `samba-data`. To use a host directory instead, replace the volume:

```yaml
volumes:
  - /path/on/host:/share
```

When using a bind mount, set `FORCE_USER_UID` and `FORCE_GROUP_GID` to match the owner of the host directory.

The container always ensures `SHARE_PATH` exists and is owned by `samba`, but it no longer changes the directory mode unless `SHARE_DIR_MODE` is set explicitly.

## Notes

- Only port **445** (SMB2/SMB3) is exposed — no legacy NetBIOS (137-139)
- macOS extended attributes are supported via `vfs_fruit`
- OS junk files (`.DS_Store`, `Thumbs.db`, `._*`, etc.) are automatically vetoed
- Process management via [s6-overlay](https://github.com/just-containers/s6-overlay)
- Ensure port 445 is open in your firewall
