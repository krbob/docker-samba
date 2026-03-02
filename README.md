# Docker Samba

Simple Samba (SMB) file server in Docker. Single share with minimal setup — connect with user `samba` and save credentials in your OS keychain.

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
    environment:
      TZ: Europe/Warsaw
      SHARE_NAME: public
      SAMBA_PASSWORD: "samba"
      # SAMBA_HOSTS_ALLOW: "192.168.1.0/24 127.0.0.0/8"
      # WSDD2_ENABLE: "1"
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
| `SAMBA_PASSWORD` | `samba` | Password for the `samba` user |
| `LOG_LEVEL` | `1` | Log verbosity (0=minimal, 3=debug) |
| `SAMBA_HOSTS_ALLOW` | *(unset)* | Restrict access to specific networks (e.g. `192.168.1.0/24 127.0.0.0/8`) |
| `WSDD2_ENABLE` | *(unset)* | Set to `1` to enable WSDD2 (Windows network discovery) |
| `AVAHI_ENABLE` | *(unset)* | Set to `1` to enable Avahi (macOS/Linux network discovery) |
| `ALLOWED_INTERFACES` | *(unset)* | Restrict WSDD2/Avahi to specific interfaces (e.g. `eno1,br0`) |

## Network Discovery

By default, the share must be accessed by IP address. To enable automatic discovery:

- **Windows**: Set `WSDD2_ENABLE=1` — uses [WSDD2](https://github.com/christgau/wsdd2) for Web Service Discovery
- **macOS/Linux**: Set `AVAHI_ENABLE=1` — uses [Avahi](https://avahi.org/) for mDNS/DNS-SD (Finder sidebar discovery)

Both require `network_mode: host` and `CAP_NET_ADMIN` (see compose example above).

## Storage

By default, data is stored in a Docker named volume `samba-data`. To use a host directory instead, replace the volume:

```yaml
volumes:
  - /path/on/host:/share
```

When using a bind mount, set `FORCE_USER_UID` and `FORCE_GROUP_GID` to match the owner of the host directory.

## Notes

- Only port **445** (SMB2/SMB3) is exposed — no legacy NetBIOS (137-139)
- macOS extended attributes are supported via `vfs_fruit`
- Process management via [s6-overlay](https://github.com/just-containers/s6-overlay)
- Ensure port 445 is open in your firewall
