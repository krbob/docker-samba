# Backup, restore, and UID/GID migration

The recycle directory is not a backup. It lives on the same filesystem as the
share and is lost with that filesystem.

## What must be preserved

A complete backup should preserve:

- file data and directory structure;
- numeric ownership and POSIX modes;
- extended attributes used by `streams_xattr` and `fruit`;
- ACLs supported by the backing filesystem;
- the Compose configuration and exact image tag or digest;
- the Samba password secret, stored separately from the data archive.

Do not put the password secret inside the share archive.

The commands below assume the base `SHARE_PATH=/share`. If the deployment uses
another target, replace `/share` consistently in the backup, restore, and
override examples.

## Named-volume backup

Stop writes while taking the archive. This example uses a timestamped filename,
verifies that the archive can be listed, records a SHA-256 checksum, and starts
Samba again even if a backup step fails:

```bash
set -eu

mkdir -p backups
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
archive_name="samba-data-${timestamp}.tar"

docker compose stop samba
restart_samba() {
  docker compose start samba
}
trap restart_samba EXIT HUP INT TERM

container_id="$(docker compose ps -q --all samba)"
image_id="$(docker inspect --format '{{.Image}}' "${container_id}")"

docker run --rm \
  --volumes-from "${container_id}:ro" \
  -v "${PWD}/backups:/backup" \
  --entrypoint tar \
  "${image_id}" \
  --xattrs --acls --numeric-owner \
  -cpf "/backup/${archive_name}" -C /share .

docker run --rm \
  -v "${PWD}/backups:/backup:ro" \
  --entrypoint tar \
  "${image_id}" \
  -tf "/backup/${archive_name}" >/dev/null

docker run --rm \
  -v "${PWD}/backups:/backup:ro" \
  -w /backup \
  --entrypoint sha256sum \
  "${image_id}" \
  "${archive_name}" > "backups/${archive_name}.sha256"

trap - EXIT HUP INT TERM
docker compose start samba
printf 'Backup: %s\nChecksum: %s\n' \
  "backups/${archive_name}" "backups/${archive_name}.sha256"
```

Store the checksum, Compose configuration, secret, and image reference in
separate protected locations. A successful `tar -tf` only proves structural
readability; periodically test a complete restore.

Record the image digest before an upgrade:

```bash
docker inspect --format '{{index .RepoDigests 0}}' \
  "$(docker compose images -q samba)"
```

## Restore a named volume

Restore into a new empty volume first. This preserves the current volume for a
fast rollback and prevents files absent from the archive from being mixed into
the restored state.

Select the archive and verify its checksum and table of contents:

```bash
set -eu

archive_name="samba-data-YYYYMMDDTHHMMSSZ.tar"
image_id="$(docker compose images -q samba)"

docker run --rm \
  -v "${PWD}/backups:/backup:ro" \
  -w /backup \
  --entrypoint sha256sum \
  "${image_id}" \
  -c "${archive_name}.sha256"

docker run --rm \
  -v "${PWD}/backups:/backup:ro" \
  --entrypoint tar \
  "${image_id}" \
  -tf "/backup/${archive_name}" >/dev/null
```

Create a uniquely named volume and extract the archive. A failed extraction
removes the incomplete new volume and leaves the live deployment untouched:

```bash
set -eu

archive_name="samba-data-YYYYMMDDTHHMMSSZ.tar"
image_id="$(docker compose images -q samba)"
restore_volume="samba-restore-$(date -u +%Y%m%dT%H%M%SZ)"
docker volume create "${restore_volume}" >/dev/null

if ! docker run --rm \
  -v "${restore_volume}:/share" \
  -v "${PWD}/backups:/backup:ro" \
  --entrypoint tar \
  "${image_id}" \
  --xattrs --acls --numeric-owner \
  -xpf "/backup/${archive_name}" -C /share; then
  docker volume rm "${restore_volume}" >/dev/null
  exit 1
fi

printf 'Restored volume: %s\n' "${restore_volume}"
```

Create `restore.override.yml` to attach the restored external volume without
changing the base Compose file:

```yaml
services:
  samba:
    volumes:
      - restored-data:/share

volumes:
  restored-data:
    external: true
    name: ${SAMBA_RESTORE_VOLUME:?Set SAMBA_RESTORE_VOLUME}
```

Stop the current service, validate the merged model, and recreate it with the
restored volume:

```bash
export SAMBA_RESTORE_VOLUME="samba-restore-YYYYMMDDTHHMMSSZ"

docker compose stop samba
docker compose \
  -f docker-compose.yml \
  -f restore.override.yml \
  config --quiet
docker compose \
  -f docker-compose.yml \
  -f restore.override.yml \
  up -d
docker compose \
  -f docker-compose.yml \
  -f restore.override.yml \
  ps
```

Test authentication, directory listings, representative reads and writes, and
extended attributes. Keep the original volume and backup until clients have
validated the restored data. Persist the override or deliberately update the
deployment's volume mapping before the next normal `docker compose up`.

To return to the original named volume, remove the restored-volume override and
recreate the base service:

```bash
docker compose -f docker-compose.yml up -d
```

## Bind mounts

For a bind mount, use the host's snapshot or backup tooling and ensure it
preserves numeric owners, ACLs, and extended attributes. Restore into a new
directory or filesystem, verify it, and then switch the bind source.

Filesystems mounted through NFS, CIFS, or a platform-specific Docker Desktop
file-sharing layer may not support the same xattr and ownership semantics as a
native Linux filesystem.

## Changing `FORCE_USER_UID` or `FORCE_GROUP_GID`

Changing the variables does not recursively migrate existing data. Perform the
migration offline:

1. stop the Samba service;
2. take and verify a backup;
3. recursively change ownership on the host or in a one-shot maintenance
   container;
4. update both UID/GID variables;
5. recreate the service and verify ownership of newly created files;
6. retain the backup until clients complete a read/write and xattr test.

For prepared or read-only storage, set `MANAGE_SHARE_PERMISSIONS=false`. The
target directory must already exist and be readable by the configured UID/GID,
and `SHARE_DIR_MODE` must remain unset.
