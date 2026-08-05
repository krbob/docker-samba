FROM debian:13.6-slim@sha256:3a39a0592364683e6bab97937b72cad5a8fa6dcbbee90edb3bb48c7f8e94f258 AS s6-downloader

ARG S6_OVERLAY_VERSION=3.2.3.2
WORKDIR /tmp

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      wget \
      xz-utils \
    && DPKG_ARCH="$(dpkg --print-architecture)" \
    && case "${DPKG_ARCH}" in \
      amd64) S6_ARCH="x86_64" ;; \
      arm64) S6_ARCH="aarch64" ;; \
      *) S6_ARCH="${DPKG_ARCH}" ;; \
    esac \
    && S6_ARCHIVE="s6-overlay-${S6_ARCH}.tar.xz" \
    && wget -q -O s6-overlay-noarch.tar.xz \
       "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz" \
    && wget -q -O s6-overlay-noarch.tar.xz.sha256 \
       "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz.sha256" \
    && wget -q -O "${S6_ARCHIVE}" \
       "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_ARCH}.tar.xz" \
    && wget -q -O "${S6_ARCHIVE}.sha256" \
       "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_ARCH}.tar.xz.sha256" \
    && sha256sum -c s6-overlay-noarch.tar.xz.sha256 \
    && sha256sum -c "s6-overlay-${S6_ARCH}.tar.xz.sha256" \
    && mkdir /s6-root \
    && tar -C /s6-root -Jxpf s6-overlay-noarch.tar.xz \
    && tar -C /s6-root -Jxpf "s6-overlay-${S6_ARCH}.tar.xz"

FROM debian:13.6-slim@sha256:3a39a0592364683e6bab97937b72cad5a8fa6dcbbee90edb3bb48c7f8e94f258

ARG DEBIAN_FRONTEND=noninteractive

ENV S6_BEHAVIOUR_IF_STAGE2_FAILS=2

RUN apt-get update && apt-get install -y --no-install-recommends \
      samba \
      samba-vfs-modules \
      smbclient \
      wsdd2 \
      avahi-daemon \
      tzdata \
      gettext-base \
      ca-certificates \
    && groupadd --system wsdd2 \
    && useradd --system --gid wsdd2 --home-dir /nonexistent --no-create-home \
       --shell /usr/sbin/nologin wsdd2 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=s6-downloader /s6-root/ /

RUN sed -i 's/^#*enable-dbus=.*/enable-dbus=no/' /etc/avahi/avahi-daemon.conf

COPY --chmod=0644 smb.conf.template /etc/samba/smb.conf.template
COPY --chmod=0755 etc/cont-init.d/01-samba-init /etc/cont-init.d/01-samba-init
COPY --chmod=0644 etc/avahi/services/samba.service /etc/avahi/services/samba.service
COPY --chmod=0755 etc/samba-healthcheck /etc/samba-healthcheck
COPY --chmod=0755 etc/services.d/avahi/run /etc/services.d/avahi/run
COPY --chmod=0755 etc/services.d/smbd/run /etc/services.d/smbd/run
COPY --chmod=0755 etc/services.d/wsdd/run /etc/services.d/wsdd/run

ARG IMAGE_VERSION=dev
ARG VCS_REF=unknown

LABEL org.opencontainers.image.title="docker-samba" \
      org.opencontainers.image.description="Secure-by-default Samba SMB2/SMB3 file server with optional LAN discovery" \
      org.opencontainers.image.source="https://github.com/krbob/docker-samba" \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}"

EXPOSE 445/tcp

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD /etc/samba-healthcheck

ENTRYPOINT ["/init"]
