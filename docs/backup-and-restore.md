# Backup, restore, and UID/GID migration

The recycle directory is not a backup. It lives on the same filesystem as the
share and is lost with that filesystem.

## What must be preserved

A complete backup should preserve:

- file data and directory structure;
- numeric ownership and POSIX modes;
- extended attributes used by `streams_xattr` and `fruit`;
- ACLs supported by the backing filesystem;
- the Compose configuration and the name of the image digest in use;
- the Samba password secret, stored separately from the data archive.

Do not put the password secret inside the share archive.

The commands below assume the default `SHARE_PATH=/share`. If the deployment
uses another target, replace `/share` in both the backup and restore commands.

## Named-volume backup

Stop writes before taking a filesystem-level archive:

```sh
docker compose stop samba
container_id="$(docker compose ps -q --all samba)"
image_id="$(docker inspect --format '{{.Image}}' "${container_id}")"
mkdir -p backups
docker run --rm \
  --volumes-from "${container_id}:ro" \
  -v "${PWD}/backups:/backup" \
  --entrypoint tar \
  "${image_id}" \
  --xattrs --acls --numeric-owner -cpf /backup/samba-data.tar -C /share .
docker compose start samba
```

Record the digest before an upgrade so the deployment can be rolled back:

```sh
docker inspect --format '{{index .RepoDigests 0}}' \
  "$(docker compose images -q samba)"
```

## Restore

Restore into an empty target volume. The following operation overwrites files;
verify the archive path and target container first.

```sh
docker compose stop samba
container_id="$(docker compose ps -q --all samba)"
image_id="$(docker inspect --format '{{.Image}}' "${container_id}")"
docker run --rm \
  --volumes-from "${container_id}" \
  -v "${PWD}/backups:/backup:ro" \
  --entrypoint tar \
  "${image_id}" \
  --xattrs --acls --numeric-owner -xpf /backup/samba-data.tar -C /share
docker compose start samba
docker compose ps
docker compose logs --tail=100 samba
```

Test authentication, directory listing, file reads, and extended attributes
before deleting the previous volume or archive.

## Bind mounts

For a bind mount, use the host's backup tooling and ensure that it preserves
numeric owners, ACLs, and extended attributes. Filesystems mounted through NFS,
CIFS, or a platform-specific Docker Desktop file-sharing layer may not support
the same xattr and ownership semantics as a native Linux filesystem.

## Changing `FORCE_USER_UID` or `FORCE_GROUP_GID`

Changing the variables does not recursively migrate existing data. Perform the
migration offline:

1. stop the Samba service;
2. take and verify a backup;
3. recursively change ownership on the host or in a one-shot maintenance
   container;
4. update both UID/GID variables;
5. start the service and verify ownership of newly created files;
6. retain the backup until clients have completed a read/write test.

For prepared or read-only storage, set `MANAGE_SHARE_PERMISSIONS=0`. The target
directory must already exist and be readable by the configured Samba UID/GID.
