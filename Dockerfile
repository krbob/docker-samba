FROM debian:13.3-slim

ARG S6_OVERLAY_VERSION=3.2.1.0

RUN apt-get update && apt-get install -y --no-install-recommends \
      samba \
      samba-vfs-modules \
      smbclient \
      wsdd2 \
      avahi-daemon \
      tzdata \
      gettext-base \
      ca-certificates \
      wget \
      xz-utils \
    && rm -rf /var/lib/apt/lists/*

# s6-overlay uses x86_64/aarch64, dpkg uses amd64/arm64
RUN DPKG_ARCH="$(dpkg --print-architecture)" \
    && case "${DPKG_ARCH}" in \
      amd64) S6_ARCH="x86_64" ;; \
      arm64) S6_ARCH="aarch64" ;; \
      *) S6_ARCH="${DPKG_ARCH}" ;; \
    esac \
    && wget -q -O /tmp/s6-overlay-noarch.tar.xz \
       "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz" \
    && wget -q -O /tmp/s6-overlay-arch.tar.xz \
       "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_ARCH}.tar.xz" \
    && tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz \
    && tar -C / -Jxpf /tmp/s6-overlay-arch.tar.xz \
    && rm /tmp/s6-overlay-*.tar.xz

RUN sed -i 's/^#*enable-dbus=.*/enable-dbus=no/' /etc/avahi/avahi-daemon.conf

COPY smb.conf.template /etc/samba/smb.conf.template
COPY etc/ /etc/
RUN chmod +x /etc/cont-init.d/* /etc/services.d/*/run

EXPOSE 445/tcp

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD smbclient -N -L //127.0.0.1 2>&1 | grep -qi "disk" || exit 1

ENTRYPOINT ["/init"]
