#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${SAMBA_TEST_COMPOSE_FILE:-${ROOT_DIR}/docker-compose-test.yml}"
SOURCE_IMAGE="${SAMBA_TEST_IMAGE:-local/samba:test}"
LOCAL_IMAGE="local/samba:test"
SMOKE_SCOPE="${SAMBA_SMOKE_SCOPE:-full}"
COMPOSE_PROJECT="samba-smoke-${GITHUB_RUN_ID:-$$}-${GITHUB_RUN_ATTEMPT:-0}"
PREFIX="${COMPOSE_PROJECT}"
COMPOSE_CONTAINER=""

declare -a CONTAINERS=()
declare -a VOLUMES=()
declare -a NETWORKS=()
declare -a TEMP_DIRS=()
LAST_CONTAINER=""
LAST_VOLUME=""
CLEANED_UP=0

case "${SMOKE_SCOPE}" in
  full | minimal) ;;
  *)
    printf 'ERROR: SAMBA_SMOKE_SCOPE must be full or minimal, got: %s\n' "${SMOKE_SCOPE}" >&2
    exit 1
    ;;
esac

log() {
  printf '\n==> %s\n' "$*"
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  local path

  if [ "${CLEANED_UP}" -eq 1 ]; then
    return
  fi
  CLEANED_UP=1
  set +eu

  docker compose -p "${COMPOSE_PROJECT}" -f "${COMPOSE_FILE}" down -v --remove-orphans >/dev/null 2>&1

  for path in "${CONTAINERS[@]}"; do
    docker rm -f "${path}" >/dev/null 2>&1
  done
  for path in "${VOLUMES[@]}"; do
    docker volume rm "${path}" >/dev/null 2>&1
  done
  for path in "${NETWORKS[@]}"; do
    docker network rm "${path}" >/dev/null 2>&1
  done
  for path in "${TEMP_DIRS[@]}"; do
    if ! rm -rf "${path}" >/dev/null 2>&1; then
      docker run --rm \
        --entrypoint sh \
        -e HOST_UID="$(id -u)" \
        -e HOST_GID="$(id -g)" \
        -v "${path}:/cleanup-target" \
        "${LOCAL_IMAGE}" \
        -c 'chown -R "${HOST_UID}:${HOST_GID}" /cleanup-target' >/dev/null 2>&1
      rm -rf "${path}" >/dev/null 2>&1
    fi
  done
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

new_volume() {
  local suffix="$1"

  LAST_VOLUME="${PREFIX}-${suffix}-data"
  docker volume create "${LAST_VOLUME}" >/dev/null
  VOLUMES+=("${LAST_VOLUME}")
}

new_temp_dir() {
  LAST_TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/samba-smoke.XXXXXX")"
  TEMP_DIRS+=("${LAST_TEMP_DIR}")
}

start_container() {
  local suffix="$1"
  shift

  LAST_CONTAINER="${PREFIX}-${suffix}"
  CONTAINERS+=("${LAST_CONTAINER}")
  docker run -d --name "${LAST_CONTAINER}" "$@" "${LOCAL_IMAGE}" >/dev/null
}

remove_container() {
  docker rm -f "$1" >/dev/null
}

remove_volume() {
  docker volume rm "$1" >/dev/null
}

wait_healthy() {
  local name="$1"
  local attempts="${2:-45}"
  local health=""
  local status=""
  local i

  for ((i = 1; i <= attempts; i++)); do
    status="$(docker inspect -f '{{.State.Status}}' "${name}" 2>/dev/null || true)"
    health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "${name}" 2>/dev/null || true)"
    if [ "${health}" = "healthy" ]; then
      return
    fi
    if [ "${health}" = "unhealthy" ] || [ "${status}" = "exited" ] || [ "${status}" = "dead" ]; then
      docker logs "${name}" >&2 || true
      fail "${name} reached status=${status}, health=${health}"
    fi
    sleep 1
  done

  docker logs "${name}" >&2 || true
  fail "${name} did not become healthy (status=${status}, health=${health})"
}

wait_exited() {
  local name="$1"
  local attempts="${2:-15}"
  local status=""
  local i

  for ((i = 1; i <= attempts; i++)); do
    status="$(docker inspect -f '{{.State.Status}}' "${name}" 2>/dev/null || true)"
    if [ "${status}" = "exited" ]; then
      return
    fi
    sleep 1
  done

  docker logs "${name}" >&2 || true
  fail "${name} should have exited, got status=${status}"
}

assert_log_contains() {
  local name="$1"
  local pattern="$2"
  local output

  output="$(docker logs "${name}" 2>&1)"
  printf '%s\n' "${output}"
  printf '%s\n' "${output}" | grep -Eqi "${pattern}" \
    || fail "logs for ${name} did not match: ${pattern}"
}

assert_vetoed() {
  local name="$1"
  local filename="$2"
  local output
  local rc

  set +e
  output="$(docker exec "${name}" smbclient -U 'samba%test-password' //127.0.0.1/public \
    -c "put /etc/hostname ${filename}" 2>&1)"
  rc=$?
  set -e
  printf '%s\n' "${output}"
  [ "${rc}" -ne 0 ] || fail "vetoed file ${filename} was accepted"
  printf '%s\n' "${output}" | grep -q "NT_STATUS_OBJECT_NAME_NOT_FOUND" \
    || fail "upload of ${filename} failed for an unexpected reason"
  docker exec "${name}" test ! -e "/share/${filename}" \
    || fail "vetoed file ${filename} exists in the share"
}

log "Preparing exact test image ${SOURCE_IMAGE}"
docker image inspect "${SOURCE_IMAGE}" >/dev/null \
  || fail "test image is not available locally: ${SOURCE_IMAGE}"
if [ "${SOURCE_IMAGE}" != "${LOCAL_IMAGE}" ]; then
  docker image tag "${SOURCE_IMAGE}" "${LOCAL_IMAGE}"
fi

log "Baseline authenticated share"
docker compose -p "${COMPOSE_PROJECT}" -f "${COMPOSE_FILE}" up -d --no-build
COMPOSE_CONTAINER="$(docker compose -p "${COMPOSE_PROJECT}" -f "${COMPOSE_FILE}" ps -q samba)"
[ -n "${COMPOSE_CONTAINER}" ] || fail "Compose did not create the samba service container"
wait_healthy "${COMPOSE_CONTAINER}"

healthcheck_definition="$(docker inspect -f '{{json .Config.Healthcheck.Test}}' "${COMPOSE_CONTAINER}")"
printf '%s\n' "${healthcheck_definition}"
if printf '%s\n' "${healthcheck_definition}" | grep -Eq -- '--password|SAMBA_PASSWORD'; then
  fail "healthcheck exposes the Samba password in argv"
fi
docker exec "${COMPOSE_CONTAINER}" test -f /run/samba/healthcheck.auth
auth_mode="$(docker exec "${COMPOSE_CONTAINER}" stat -c '%a' /run/samba/healthcheck.auth)"
[ "${auth_mode}" = "600" ] || fail "healthcheck auth mode is ${auth_mode}, expected 600"

output="$(docker exec "${COMPOSE_CONTAINER}" smbclient -N -L //127.0.0.1 2>&1)"
printf '%s\n' "${output}"
printf '%s\n' "${output}" | grep -q "public" || fail "share public was not listed"

output="$(docker run --rm \
  --network "${COMPOSE_PROJECT}_default" \
  --entrypoint smbclient \
  "${LOCAL_IMAGE}" \
  -U 'samba%test-password' //samba/public -c ls 2>&1)"
printf '%s\n' "${output}"
printf '%s\n' "${output}" | grep -Eq '^  \.|blocks of size' \
  || fail "a client container could not access the share over the Compose network"

docker exec "${COMPOSE_CONTAINER}" smbclient -U 'samba%test-password' //127.0.0.1/public \
  -c 'put /etc/hostname test-file.txt' 2>&1
docker exec "${COMPOSE_CONTAINER}" smbclient -U 'samba%test-password' //127.0.0.1/public \
  -c 'get test-file.txt /tmp/downloaded.txt' 2>&1
docker exec "${COMPOSE_CONTAINER}" cmp -s /etc/hostname /tmp/downloaded.txt \
  || fail "downloaded file differs from the uploaded file"

assert_vetoed "${COMPOSE_CONTAINER}" ".DS_Store"
assert_vetoed "${COMPOSE_CONTAINER}" "Thumbs.db"
assert_vetoed "${COMPOSE_CONTAINER}" ".Thumbs.db"

set +e
guest_output="$(docker exec "${COMPOSE_CONTAINER}" smbclient -N //127.0.0.1/public -c ls 2>&1)"
guest_rc=$?
set -e
printf '%s\n' "${guest_output}"
[ "${guest_rc}" -ne 0 ] || fail "guest access should be denied"
printf '%s\n' "${guest_output}" | grep -Eqi 'NT_STATUS_ACCESS_DENIED|Access denied|tree connect failed' \
  || fail "guest denial returned an unexpected error"

docker exec "${COMPOSE_CONTAINER}" /command/s6-svstat /var/run/s6/legacy-services/wsdd 2>&1 \
  | grep -q '^down' || fail "wsdd should be disabled by default"
docker exec "${COMPOSE_CONTAINER}" /command/s6-svstat /var/run/s6/legacy-services/avahi 2>&1 \
  | grep -q '^down' || fail "avahi should be disabled by default"

docker compose -p "${COMPOSE_PROJECT}" -f "${COMPOSE_FILE}" down -v --remove-orphans

if [ "${SMOKE_SCOPE}" = "minimal" ]; then
  log "Minimal Samba smoke tests passed"
  exit 0
fi

log "Hosts allow"
new_volume hosts-allow
volume="${LAST_VOLUME}"
start_container hosts-allow \
  -e SAMBA_PASSWORD=test-password \
  -e SAMBA_HOSTS_ALLOW=127.0.0.0/8 \
  -v "${volume}:/share"
name="${LAST_CONTAINER}"
wait_healthy "${name}"
config="$(docker exec "${name}" testparm -s /etc/samba/smb.conf 2>/dev/null)"
printf '%s\n' "${config}" | grep -Fq 'hosts allow = 127.0.0.0/8' \
  || fail "hosts allow was not rendered"
docker exec "${name}" smbclient -U 'samba%test-password' //127.0.0.1/public -c ls 2>&1
remove_container "${name}"
remove_volume "${volume}"

log "SMB transport protection"
new_volume smb-protection
volume="${LAST_VOLUME}"
start_container smb-protection \
  -e SAMBA_PASSWORD=test-password \
  -e SMB_ENCRYPT=desired \
  -e SMB_SIGNING=mandatory \
  -v "${volume}:/share"
name="${LAST_CONTAINER}"
wait_healthy "${name}"
docker exec "${name}" grep -Fq 'server smb encrypt = desired' /etc/samba/smb.conf
docker exec "${name}" grep -Fq 'server signing = mandatory' /etc/samba/smb.conf
docker exec "${name}" smbclient -U 'samba%test-password' //127.0.0.1/public -c ls 2>&1
remove_container "${name}"
remove_volume "${volume}"

log "Discovery without elevated network capabilities"
new_volume discovery
volume="${LAST_VOLUME}"
start_container discovery \
  --cap-drop NET_RAW \
  -e SAMBA_PASSWORD=test-password \
  -e WORKGROUP=TESTWG \
  -e WSDD2_ENABLE=1 \
  -e WSDD2_HOSTNAME=testhost \
  -e WSDD2_NETBIOS_NAME=TESTHOST \
  -e WSDD2_WORKGROUP=TESTWG \
  -e AVAHI_ENABLE=1 \
  -v "${volume}:/share"
name="${LAST_CONTAINER}"
wait_healthy "${name}"
docker exec "${name}" /command/s6-svstat /var/run/s6/legacy-services/wsdd 2>&1 \
  | grep -q '^up' || fail "wsdd did not start"
docker exec "${name}" /command/s6-svstat /var/run/s6/legacy-services/avahi 2>&1 \
  | grep -q '^up' || fail "avahi did not start"
assert_log_contains "${name}" 'Starting wsdd2 -w -H testhost -N TESTHOST -G TESTWG'
remove_container "${name}"
remove_volume "${volume}"

log "Guest read/write access"
new_volume guest
volume="${LAST_VOLUME}"
start_container guest -e GUEST_OK=1 -v "${volume}:/share"
name="${LAST_CONTAINER}"
wait_healthy "${name}"
docker exec "${name}" smbclient -N //127.0.0.1/public \
  -c 'put /etc/hostname guest-test.txt' 2>&1
docker exec "${name}" cmp -s /etc/hostname /share/guest-test.txt
remove_container "${name}"
remove_volume "${volume}"

log "Guest mode conflicts with configured credentials"
start_container guest-password-conflict \
  -e GUEST_OK=1 \
  -e SAMBA_PASSWORD=test-password
name="${LAST_CONTAINER}"
wait_exited "${name}"
assert_log_contains "${name}" 'GUEST_OK cannot be enabled together with SAMBA_PASSWORD'
remove_container "${name}"

log "Password file"
new_temp_dir
password_dir="${LAST_TEMP_DIR}"
printf '%s\n' 'file-password' > "${password_dir}/password"
chmod 600 "${password_dir}/password"
new_volume password-file
volume="${LAST_VOLUME}"
start_container password-file \
  -e SAMBA_PASSWORD_FILE=/run/secrets/samba_password \
  -v "${password_dir}/password:/run/secrets/samba_password:ro" \
  -v "${volume}:/share"
name="${LAST_CONTAINER}"
wait_healthy "${name}"
set +e
password_output="$(docker exec "${name}" smbclient -U 'samba%file-password' //127.0.0.1/public \
  -c 'put /etc/hostname password-file.txt' 2>&1)"
password_rc=$?
set -e
printf '%s\n' "${password_output}"
docker exec "${name}" cmp -s /etc/hostname /share/password-file.txt \
  || fail "password-file upload did not create the expected file"
if [ "${password_rc}" -ne 0 ]; then
  printf 'smbclient returned %s after creating the expected file\n' "${password_rc}"
fi
docker exec "${name}" test -s /run/samba/healthcheck.auth
remove_container "${name}"
remove_volume "${volume}"

log "Multiline password file fails fast"
new_temp_dir
multiline_password_dir="${LAST_TEMP_DIR}"
printf '%s\n%s\n' 'first-line' 'second-line' > "${multiline_password_dir}/password"
chmod 600 "${multiline_password_dir}/password"
start_container multiline-password-file \
  -e SAMBA_PASSWORD_FILE=/run/secrets/samba_password \
  -v "${multiline_password_dir}/password:/run/secrets/samba_password:ro"
name="${LAST_CONTAINER}"
wait_exited "${name}"
assert_log_contains "${name}" 'SAMBA_PASSWORD_FILE must contain exactly one line'
remove_container "${name}"

log "Bound Samba interfaces"
new_volume bind-interfaces
volume="${LAST_VOLUME}"
start_container bind-interfaces \
  -e SAMBA_PASSWORD=test-password \
  -e SAMBA_INTERFACES=lo \
  -e SAMBA_BIND_INTERFACES_ONLY=1 \
  -v "${volume}:/share"
name="${LAST_CONTAINER}"
wait_healthy "${name}"
config="$(docker exec "${name}" testparm -s /etc/samba/smb.conf 2>/dev/null)"
printf '%s\n' "${config}" | grep -Fq 'interfaces = lo' || fail "interfaces was not rendered"
printf '%s\n' "${config}" | grep -Fq 'bind interfaces only = Yes' \
  || fail "bind interfaces only was not enabled"
remove_container "${name}"
remove_volume "${volume}"

log "Delayed interface readiness and external healthcheck"
new_volume delayed-interface
volume="${LAST_VOLUME}"
network="${PREFIX}-delayed-ready"
docker network create "${network}" >/dev/null
NETWORKS+=("${network}")
start_container delayed-interface \
  -e GUEST_OK=1 \
  -e SAMBA_INTERFACES='lo eth1' \
  -e SAMBA_BIND_INTERFACES_ONLY=1 \
  -e SAMBA_READY_INTERFACE=eth1 \
  -e SAMBA_READY_TIMEOUT=15 \
  -v "${volume}:/share"
name="${LAST_CONTAINER}"
sleep 2
[ "$(docker inspect -f '{{.State.Status}}' "${name}")" = "running" ] \
  || fail "${name} exited instead of waiting for eth1"
if docker top "${name}" -eo pid,cmd | grep -q 'smbd --foreground'; then
  fail "smbd started before eth1 acquired an address"
fi
assert_log_contains "${name}" 'Waiting up to 15s for eth1'
docker network connect "${network}" "${name}"
wait_healthy "${name}"
docker exec "${name}" /etc/samba-healthcheck
docker network disconnect "${network}" "${name}"
set +e
health_output="$(docker exec "${name}" /etc/samba-healthcheck 2>&1)"
health_rc=$?
set -e
printf '%s\n' "${health_output}"
[ "${health_rc}" -ne 0 ] || fail "healthcheck passed without the ready interface"
printf '%s\n' "${health_output}" | grep -Fq "SAMBA_READY_INTERFACE 'eth1' has no global IPv4 address" \
  || fail "healthcheck did not report the missing ready interface"
remove_container "${name}"
remove_volume "${volume}"
docker network rm "${network}" >/dev/null

log "Ready interface timeout fails startup"
start_container ready-interface-timeout \
  --network none \
  -e GUEST_OK=1 \
  -e SAMBA_READY_INTERFACE=eth0 \
  -e SAMBA_READY_TIMEOUT=2
name="${LAST_CONTAINER}"
wait_exited "${name}"
assert_log_contains "${name}" "SAMBA_READY_INTERFACE 'eth0' did not acquire a global IPv4 address within 2s"
remove_container "${name}"

log "Ready interface timeout must be positive"
start_container ready-interface-zero-timeout \
  -e GUEST_OK=1 \
  -e SAMBA_READY_TIMEOUT=0
name="${LAST_CONTAINER}"
wait_exited "${name}"
assert_log_contains "${name}" 'SAMBA_READY_TIMEOUT must be greater than zero'
remove_container "${name}"

log "Wide-link opt-in"
new_volume symlinks
volume="${LAST_VOLUME}"
start_container symlinks \
  -e SAMBA_PASSWORD=test-password \
  -e FOLLOW_SYMLINKS=1 \
  -v "${volume}:/share"
name="${LAST_CONTAINER}"
wait_healthy "${name}"
config="$(docker exec "${name}" testparm -s /etc/samba/smb.conf 2>/dev/null)"
printf '%s\n' "${config}" | grep -Fq 'wide links = Yes' || fail "wide links was not enabled"
printf '%s\n' "${config}" | grep -Fq 'smb1 unix extensions = No' \
  || fail "SMB1 unix extensions were not disabled"
docker exec "${name}" sh -c \
  'printf "%s\n" linked-target > /tmp/outside-share.txt && ln -s /tmp/outside-share.txt /share/outside-link.txt'
docker exec "${name}" smbclient -U 'samba%test-password' //127.0.0.1/public \
  -c 'get outside-link.txt /tmp/symlink-download.txt' 2>&1
docker exec "${name}" grep -q linked-target /tmp/symlink-download.txt
remove_container "${name}"
remove_volume "${volume}"

log "Multiline password fails fast"
new_volume multiline-password
volume="${LAST_VOLUME}"
start_container multiline-password \
  -e $'SAMBA_PASSWORD=bad\npassword' \
  -v "${volume}:/share"
name="${LAST_CONTAINER}"
wait_exited "${name}"
assert_log_contains "${name}" 'SAMBA_PASSWORD must not contain newlines'
remove_container "${name}"
remove_volume "${volume}"

log "Invalid SMB transport value fails fast"
start_container invalid-smb-protection \
  -e SAMBA_PASSWORD=test-password \
  -e SMB_ENCRYPT=enabled
name="${LAST_CONTAINER}"
wait_exited "${name}"
assert_log_contains "${name}" 'SMB_ENCRYPT must be one of'
remove_container "${name}"

log "Common true boolean spelling enables read-only mode"
new_volume readonly
volume="${LAST_VOLUME}"
start_container readonly \
  -e SAMBA_PASSWORD=test-password \
  -e READ_ONLY=true \
  -v "${volume}:/share"
name="${LAST_CONTAINER}"
wait_healthy "${name}"
docker exec "${name}" smbclient -U 'samba%test-password' //127.0.0.1/public -c ls 2>&1
set +e
readonly_output="$(docker exec "${name}" smbclient -U 'samba%test-password' //127.0.0.1/public \
  -c 'put /etc/hostname readonly.txt' 2>&1)"
readonly_rc=$?
set -e
printf '%s\n' "${readonly_output}"
[ "${readonly_rc}" -ne 0 ] || fail "read-only share accepted a write"
printf '%s\n' "${readonly_output}" \
  | grep -Eqi 'NT_STATUS_ACCESS_DENIED|Access denied|NT_STATUS_MEDIA_WRITE_PROTECTED' \
  || fail "read-only write returned an unexpected error"
remove_container "${name}"
remove_volume "${volume}"

log "Read-only bind mount works without permission management"
new_temp_dir
readonly_bind_dir="${LAST_TEMP_DIR}"
printf '%s\n' 'read-only bind content' > "${readonly_bind_dir}/existing.txt"
chmod 0755 "${readonly_bind_dir}"
chmod 0644 "${readonly_bind_dir}/existing.txt"
start_container readonly-bind \
  -e SAMBA_PASSWORD=test-password \
  -e READ_ONLY=true \
  -e MANAGE_SHARE_PERMISSIONS=off \
  -v "${readonly_bind_dir}:/share:ro"
name="${LAST_CONTAINER}"
wait_healthy "${name}"
mount_rw="$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/share"}}{{.RW}}{{end}}{{end}}' "${name}")"
[ "${mount_rw}" = "false" ] || fail "share bind mount should be read-only at the container boundary"
docker exec "${name}" smbclient -U 'samba%test-password' //127.0.0.1/public \
  -c 'get existing.txt /tmp/existing.txt' 2>&1
docker exec "${name}" grep -Fxq 'read-only bind content' /tmp/existing.txt
set +e
readonly_bind_output="$(docker exec "${name}" smbclient -U 'samba%test-password' //127.0.0.1/public \
  -c 'put /etc/hostname rejected.txt' 2>&1)"
readonly_bind_rc=$?
set -e
printf '%s\n' "${readonly_bind_output}"
[ "${readonly_bind_rc}" -ne 0 ] || fail "read-only bind mount accepted a write"
remove_container "${name}"

log "Unknown boolean spelling fails fast"
start_container invalid-boolean \
  -e SAMBA_PASSWORD=test-password \
  -e READ_ONLY=maybe
name="${LAST_CONTAINER}"
wait_exited "${name}"
assert_log_contains "${name}" 'READ_ONLY'
remove_container "${name}"

log "Recycle behavior and create masks"
new_volume options
volume="${LAST_VOLUME}"
start_container options \
  -e SAMBA_PASSWORD=test-password \
  -e RECYCLE_ENABLE=1 \
  -e RECYCLE_MAX_SIZE=1024 \
  -e 'RECYCLE_EXCLUDE=*.tmp|*.temp,*.bak' \
  -e 'RECYCLE_EXCLUDE_DIR=.recycle|tmp,cache' \
  -e CREATE_MASK=0640 \
  -e DIRECTORY_MASK=0750 \
  -v "${volume}:/share"
name="${LAST_CONTAINER}"
wait_healthy "${name}"
docker exec "${name}" smbclient -U 'samba%test-password' //127.0.0.1/public \
  -c 'mkdir maskdir; put /etc/hostname maskdir/mask-file.txt' 2>&1
dir_mode="$(docker exec "${name}" stat -c '%a' /share/maskdir)"
file_mode="$(docker exec "${name}" stat -c '%a' /share/maskdir/mask-file.txt)"
[ "${dir_mode}" = "750" ] || fail "directory mode is ${dir_mode}, expected 750"
[ "${file_mode}" = "640" ] || fail "file mode is ${file_mode}, expected 640"
docker exec "${name}" smbclient -U 'samba%test-password' //127.0.0.1/public \
  -c 'del maskdir/mask-file.txt' 2>&1
docker exec "${name}" test -f /share/.recycle/maskdir/mask-file.txt \
  || fail "ordinary deleted file was not recycled"

for extension in tmp temp bak; do
  docker exec "${name}" smbclient -U 'samba%test-password' //127.0.0.1/public \
    -c "put /etc/hostname excluded.${extension}; del excluded.${extension}" 2>&1
  docker exec "${name}" test ! -e "/share/.recycle/excluded.${extension}" \
    || fail "excluded.${extension} should have bypassed recycle"
done

for excluded_dir in tmp cache; do
  docker exec "${name}" smbclient -U 'samba%test-password' //127.0.0.1/public \
    -c "mkdir ${excluded_dir}; put /etc/hostname ${excluded_dir}/excluded.txt; del ${excluded_dir}/excluded.txt" 2>&1
  docker exec "${name}" test ! -e "/share/.recycle/${excluded_dir}/excluded.txt" \
    || fail "${excluded_dir}/excluded.txt should have bypassed recycle"
done
remove_container "${name}"
remove_volume "${volume}"

log "Bind-mount UID/GID mapping"
new_temp_dir
bind_dir="${LAST_TEMP_DIR}"
start_container bind-uid \
  -e SAMBA_PASSWORD=test-password \
  -e FORCE_USER_UID=1234 \
  -e FORCE_GROUP_GID=1234 \
  -v "${bind_dir}:/share"
name="${LAST_CONTAINER}"
wait_healthy "${name}"
docker exec "${name}" smbclient -U 'samba%test-password' //127.0.0.1/public \
  -c 'put /etc/hostname uid-test.txt' 2>&1
samba_uid="$(docker exec "${name}" id -u samba)"
samba_gid="$(docker exec "${name}" id -g samba)"
[ "${samba_uid}:${samba_gid}" = "1234:1234" ] \
  || fail "samba UID:GID is ${samba_uid}:${samba_gid}, expected 1234:1234"
docker exec "${name}" test -f /share/uid-test.txt
remove_container "${name}"

log "UID with a leading zero fails fast"
start_container noncanonical-uid \
  -e SAMBA_PASSWORD=test-password \
  -e FORCE_USER_UID=01000 \
  -e FORCE_GROUP_GID=1000
name="${LAST_CONTAINER}"
wait_exited "${name}"
assert_log_contains "${name}" 'FORCE_USER_UID must be a non-zero canonical decimal integer'
remove_container "${name}"

log "Invalid UID/GID fails fast"
start_container invalid-uid \
  -e FORCE_USER_UID=0 \
  -e FORCE_GROUP_GID=0
name="${LAST_CONTAINER}"
wait_exited "${name}"
assert_log_contains "${name}" 'FORCE_USER_UID|FORCE_GROUP_GID|Group samba already exists|User samba already exists'
remove_container "${name}"

log "All Samba smoke tests passed"
