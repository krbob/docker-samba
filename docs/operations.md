# Operations and troubleshooting

## Health and logs

Check the Compose and container health state after every configuration or image
change:

```bash
docker compose ps
docker inspect --format '{{.State.Health.Status}}' \
  "$(docker compose ps -q samba)"
docker compose logs --tail=100 samba
```

Startup validates the complete configuration before creating the Samba
identity or changing the mounted share. An `unhealthy` or restarting container
therefore often indicates a rejected environment value, conflicting
authentication mode, unreadable secret, missing prepared share path, or UID/GID
collision. The startup log reports the failing variable without printing the
password.

When `SAMBA_READY_INTERFACE` is configured, startup also waits for that
interface to receive a global IPv4 address. The healthcheck tests the share on
the interface address, not only on loopback. A readiness timeout usually means
the container started before DHCP completed, the interface name is wrong, or
the host network never came online.

Use `docker compose up -d` after changing Compose configuration or environment
values. `docker compose restart` reuses the existing container configuration
and does not apply those changes.

## Image references

The project currently publishes continuously from `main` and does not create
versioned GitHub releases.

- `latest` points to the newest validated main-branch image and is mutable;
- `sha-<full-git-commit>` points to the validated image built from that source
  revision;
- a digest such as `ghcr.io/krbob/samba@sha256:...` identifies an exact
  registry artifact;
- `candidate-*` tags are CI staging artifacts and may represent a build that
  failed validation; do not deploy them.

`SAMBA_IMAGE_TAG` can select `latest` or a `sha-*` tag. To pin a digest, replace
the complete `image:` value in a Compose override instead of putting a digest
in `SAMBA_IMAGE_TAG`:

```yaml
services:
  samba:
    image: ghcr.io/krbob/samba@sha256:<recorded-digest>
```

Record the artifact currently used by the service:

```bash
docker inspect --format '{{index .RepoDigests 0}}' \
  "$(docker compose images -q samba)"
```

## Update

Before updating:

1. create and verify a share backup;
2. preserve the Compose files, `.env`, and password secret separately;
3. record the current tag or digest;
4. review `CHANGELOG.md` and configuration changes.

Pull and recreate the service:

```bash
docker compose pull
docker compose up -d
docker compose ps
docker compose logs --tail=100 samba
```

Test authentication, directory listing, representative reads and writes, and
extended attributes before deleting the previous backup.

## Rollback

Restore the previous tag or digest in the deployment configuration, then run:

```bash
docker compose pull
docker compose up -d
docker compose ps
```

An image rollback does not revert share contents, UID/GID changes, or files
already modified by clients. Use the backup runbook when data or ownership must
also be restored.

## Troubleshooting

### TCP 445 is already in use

Only one listener can bind the selected host address and TCP port. Check for a
host Samba service, another container, or an operating-system file-sharing
service.

Linux:

```bash
sudo ss -ltnp 'sport = :445'
```

macOS:

```bash
lsof -nP -iTCP:445 -sTCP:LISTEN
```

Choose a free host address or stop the conflicting service. SMB clients expect
TCP 445, so publishing a different host port is not a broadly compatible LAN
solution.

### Authentication fails

- use the fixed username `samba` for authenticated mode;
- confirm the secret contains exactly one non-empty line;
- do not set both `SAMBA_PASSWORD` and `SAMBA_PASSWORD_FILE`;
- do not combine either password setting with `GUEST_OK=true`;
- recreate the container with `docker compose up -d` after changing the
  secret.

Do not use `docker inspect` to troubleshoot password values because environment
variables may be exposed in its output.

### Permission denied or wrong ownership

`FORCE_USER_UID` and `FORCE_GROUP_GID` must match the numeric ownership expected
by a bind mount. Startup changes only the top-level share directory and does
not recursively migrate existing files. Inspect ownership on the Docker host
and follow the offline migration procedure in the backup runbook when IDs must
change.

For prepared or read-only storage, the path must already exist and be readable
by the configured IDs, `MANAGE_SHARE_PERMISSIONS=false`, and `SHARE_DIR_MODE`
must be unset.

### macOS metadata or alternate streams fail

The backing filesystem and every intermediate mount layer must preserve Linux
extended attributes. Docker Desktop sharing, NFS, and CIFS-backed paths can
behave differently from a native Linux filesystem. Reproduce the operation on
a native local filesystem before treating it as a Samba configuration issue.

### Direct SMB works but the server is not discoverable

This is a discovery or multicast issue rather than a file-server failure.
Follow the checklist in [Networking and discovery](networking.md).

### Loopback works but LAN access is refused

Compare `SAMBA_INTERFACES` with the listener addresses reported by
`ss -ltn 'sport = :445'`. For host-network deployments using DHCP, set
`SAMBA_READY_INTERFACE` to the physical LAN interface and recreate the
container. Do not rely on a loopback-only healthcheck to validate LAN access.

## Related runbooks

- [Configuration reference](configuration.md)
- [Networking and discovery](networking.md)
- [Backup, restore, and UID/GID migration](backup-and-restore.md)
- [Security policy](../SECURITY.md)
