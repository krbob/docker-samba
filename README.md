# Docker Samba

Simple Samba (SMB) file server in Docker. Single public share with guest access — no authentication required.

## Quick Start

```bash
docker compose up -d
```

## Connecting

| Platform | Address |
|---|---|
| macOS | Finder → Cmd+K → `smb://<host-ip>/public` |
| Windows | Explorer → `\\<host-ip>\public` |
| Mobile | Any SMB-capable file manager → `smb://<host-ip>/public` |

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `SHARE_NAME` | `public` | Share name |
| `SHARE_PATH` | `/share` | Path inside container |
| `WORKGROUP` | `WORKGROUP` | SMB workgroup |
| `SERVER_STRING` | `Samba Server` | Server description |
| `FORCE_USER_UID` | `1000` | UID for file operations |
| `FORCE_GROUP_GID` | `1000` | GID for file operations |
| `LOG_LEVEL` | `1` | Log verbosity (0=minimal, 3=debug) |

## Storage

By default, data is stored in a Docker named volume `samba-data`. To use a host directory instead, replace the volume in `docker-compose.yml`:

```yaml
volumes:
  - /path/on/host:/share
```

When using a bind mount, set `FORCE_USER_UID` and `FORCE_GROUP_GID` to match the owner of the host directory.

## Notes

- Only port **445** (SMB2/SMB3) is exposed — no legacy NetBIOS (137-139)
- macOS extended attributes are supported via `vfs_fruit`
- Ensure port 445 is open in your firewall
