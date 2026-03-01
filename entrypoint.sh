#!/bin/sh
set -e

# Defaults
: "${SHARE_NAME:=public}"
: "${SHARE_PATH:=/share}"
: "${WORKGROUP:=WORKGROUP}"
: "${SERVER_STRING:=Samba Server}"
: "${FORCE_USER_UID:=1000}"
: "${FORCE_GROUP_GID:=1000}"
: "${LOG_LEVEL:=1}"

# Create samba group and user with configurable UID/GID
groupadd -g "${FORCE_GROUP_GID}" samba 2>/dev/null || true
useradd -u "${FORCE_USER_UID}" -g samba -M -s /sbin/nologin samba 2>/dev/null || true

# Ensure share directory exists with correct ownership
mkdir -p "${SHARE_PATH}"
chown samba:samba "${SHARE_PATH}"
chmod 0777 "${SHARE_PATH}"

# Optional: restrict access to specific networks
if [ -n "${SAMBA_HOSTS_ALLOW}" ]; then
  HOSTS_ALLOW_LINE="  hosts allow = ${SAMBA_HOSTS_ALLOW}"
else
  HOSTS_ALLOW_LINE=""
fi

# Generate smb.conf from template
export SHARE_NAME SHARE_PATH WORKGROUP SERVER_STRING LOG_LEVEL HOSTS_ALLOW_LINE
envsubst < /etc/samba/smb.conf.template > /etc/samba/smb.conf

# Validate configuration
echo "--- Samba configuration ---"
testparm -s /etc/samba/smb.conf 2>/dev/null
echo "---"

exec smbd --foreground --debug-stdout --no-process-group --configfile=/etc/samba/smb.conf
