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
    environment:
      TZ: Europe/Warsaw
      SHARE_NAME: public
      SAMBA_PASSWORD: "replace-with-a-strong-password"
      # SAMBA_PASSWORD_FILE: /run/secrets/samba_password
      # GUEST_OK: "1"
      # SAMBA_HOSTS_ALLOW: "192.168.1.0/24 127.0.0.0/8"
      # SMB_ENCRYPT: "desired"
      # SMB_SIGNING: "mandatory"
      # WSDD2_ENABLE: "1"
      # WSDD2_HOSTNAME: "homelab"
      # WSDD2_NETBIOS_NAME: "HOMELAB"
      # AVAHI_ENABLE: "1"
      # ALLOWED_INTERFACES: "eno1"
    volumes:
      - samba-data:/share
    # secrets:
    #   - samba_password

volumes:
  samba-data:
    driver: local

# secrets:
#   samba_password:
#     file: ./samba_password.txt
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
| `READ_ONLY` | *(unset)* | Set to `1` to make the share read-only |
| `CREATE_MASK` | `0664` | File mode mask for newly created files |
| `DIRECTORY_MASK` | `0775` | Directory mode mask for newly created directories |
| `RECYCLE_ENABLE` | *(unset)* | Set to `1` to move SMB-deleted files into a recycle directory |
| `RECYCLE_REPOSITORY` | `.recycle` | Relative recycle directory inside `SHARE_PATH` |
| `RECYCLE_MAX_SIZE` | *(unset)* | Optional maximum file size, in bytes, that is moved to recycle (`0` means no per-file limit) |
| `RECYCLE_EXCLUDE` | *(unset)* | Optional recycle exclude patterns, separated by `|` |
| `RECYCLE_EXCLUDE_DIR` | *(unset)* | Optional recycle directory exclude patterns, separated by `|` |
| `SAMBA_PASSWORD` | *(required unless `SAMBA_PASSWORD_FILE` or `GUEST_OK=1`)* | Password for the `samba` user |
| `SAMBA_PASSWORD_FILE` | *(unset)* | Read the Samba password from a file, such as `/run/secrets/samba_password` |
| `LOG_LEVEL` | `1` | Log verbosity (0=minimal, 3=debug) |
| `SAMBA_INTERFACES` | *(unset)* | Optional Samba listener interfaces/IPs, e.g. `lo eno1` |
| `SAMBA_BIND_INTERFACES_ONLY` | *(unset)* | Set to `1` to bind `smbd` only to `SAMBA_INTERFACES` |
| `SAMBA_HOSTS_ALLOW` | *(unset)* | Restrict access to specific networks (e.g. `192.168.1.0/24 127.0.0.0/8`) |
| `SMB_ENCRYPT` | *(unset)* | Optional `server smb encrypt` value: `default`, `if_required`, `desired`, `required`, or `off` |
| `SMB_SIGNING` | *(unset)* | Optional `server signing` value: `default`, `auto`, `mandatory`, or `disabled` |
| `WSDD2_ENABLE` | *(unset)* | Set to `1` to enable WSDD2 (Windows network discovery) |
| `WSDD2_HOSTNAME` | *(unset)* | Override the hostname announced by WSDD2 |
| `WSDD2_NETBIOS_NAME` | *(unset)* | Override the NetBIOS name announced by WSDD2 |
| `WSDD2_WORKGROUP` | *(unset)* | Override the workgroup announced by WSDD2 (defaults to `WORKGROUP` env if set) |
| `AVAHI_ENABLE` | *(unset)* | Set to `1` to enable Avahi (macOS/Linux network discovery) |
| `ALLOWED_INTERFACES` | *(unset)* | Restrict WSDD2/Avahi to specific interfaces (e.g. `eno1,br0`) |
| `FOLLOW_SYMLINKS` | *(unset)* | Security-sensitive: set to `1` to allow Samba wide links |
| `GUEST_OK` | *(unset)* | Set to `1` to allow anonymous access (no password required) |

Set only one of `SAMBA_PASSWORD` or `SAMBA_PASSWORD_FILE`. Use one of those for authenticated access, or set `GUEST_OK=1` for an anonymous guest share. Leaving all three unset is treated as a configuration error.

### SMB Transport Protection

Set `SMB_ENCRYPT=desired` to encrypt traffic for clients that support SMB encryption. Set `SMB_ENCRYPT=required` only when every client supports encrypted SMB3; older or limited clients will be denied.

Set `SMB_SIGNING=mandatory` to require SMB signing. This can improve integrity protection on trusted LANs, but may reduce throughput and can break very old clients.

### Symlinks

`FOLLOW_SYMLINKS=1` enables Samba `wide links`, which lets clients follow symlinks that point outside `SHARE_PATH` inside the container. Use it only for trusted users and tightly scoped mounts, because it can expose other mounted paths or container filesystem paths.

## Network Discovery

By default, the share must be accessed by IP address. To enable automatic discovery:

- **Windows**: Set `WSDD2_ENABLE=1` — uses [WSDD2](https://github.com/christgau/wsdd2) for Web Service Discovery
- **macOS/Linux**: Set `AVAHI_ENABLE=1` — uses [Avahi](https://avahi.org/) for mDNS/DNS-SD (Finder sidebar discovery)

If you enable WSDD2, add:

```yaml
cap_add:
  - CAP_NET_ADMIN
  - CAP_NET_RAW
```

Both discovery methods require `network_mode: host` (see compose example above).

## Network Binding

With `network_mode: host`, Docker does not restrict port 445 to selected host interfaces. Set `SAMBA_INTERFACES` and `SAMBA_BIND_INTERFACES_ONLY=1` to make `smbd` listen only on specific interfaces. Include `lo` or a `127.x.x.x` address because the container healthcheck connects to `127.0.0.1`.

## Storage

By default, data is stored in a Docker named volume `samba-data`. To use a host directory instead, replace the volume:

```yaml
volumes:
  - /path/on/host:/share
```

When using a bind mount, set `FORCE_USER_UID` and `FORCE_GROUP_GID` to match the owner of the host directory.

The container always ensures `SHARE_PATH` exists and is owned by `samba`, but it no longer changes the directory mode unless `SHARE_DIR_MODE` is set explicitly.

If `RECYCLE_ENABLE=1` is set, files deleted through SMB are moved under `RECYCLE_REPOSITORY` with the original directory tree preserved. `RECYCLE_REPOSITORY` must be a relative path inside `SHARE_PATH`. The recycle directory is not purged automatically; clean it manually or use `RECYCLE_EXCLUDE`, `RECYCLE_EXCLUDE_DIR`, and `RECYCLE_MAX_SIZE` to reduce what is kept.

## Notes

- Only port **445** (SMB2/SMB3) is exposed — no legacy NetBIOS (137-139)
- macOS extended attributes are supported via `vfs_fruit`
- OS junk files (`.DS_Store`, `Thumbs.db`, `._*`, etc.) are automatically vetoed
- Process management via [s6-overlay](https://github.com/just-containers/s6-overlay)
- Ensure port 445 is open in your firewall
