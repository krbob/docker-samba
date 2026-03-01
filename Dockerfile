FROM debian:12.13-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      samba \
      samba-vfs-modules \
      smbclient \
      gettext-base \
    && rm -rf /var/lib/apt/lists/*

COPY smb.conf.template /etc/samba/smb.conf.template
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 445/tcp

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD smbclient -N -L //127.0.0.1 2>&1 | grep -qi "disk" || exit 1

ENTRYPOINT ["/entrypoint.sh"]
