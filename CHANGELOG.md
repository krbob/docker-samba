# Changelog

All notable changes to this project are documented in this file. The format is
based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

The project currently publishes validated `main` commits continuously as
`latest` and `sha-<full-git-commit>` images, without versioned releases. Until
the first release is cut, `[Unreleased]` is the cumulative changelog for that
continuously published line; use a `sha-*` image or digest for an exact build.

## [Unreleased]

### Breaking

- The default Compose deployment now pulls `ghcr.io/krbob/samba` instead of
  building locally, uses a bridge network, and publishes SMB only on
  `127.0.0.1`. LAN discovery and host networking moved to the explicit
  `docker-compose.discovery.yml` override.
- The default Compose deployment now requires a file-backed password secret at
  `.secrets/samba_password`, or at the path selected with
  `SAMBA_PASSWORD_SECRET_FILE`.
- LLMNR is disabled when WSDD2 is enabled unless
  `WSDD2_LLMNR_ENABLE=1` is explicitly set.
- Guest mode can no longer be combined with `SAMBA_PASSWORD` or
  `SAMBA_PASSWORD_FILE`. Passwords must contain exactly one line and cannot
  start or end with whitespace.
- Invalid configuration now stops startup. This includes unknown boolean
  values, non-canonical or zero UID/GID values, unsafe share paths and names,
  invalid interface lists, and out-of-range modes or log levels.
- `SHARE_PATH` must be an absolute path and cannot resolve to `/`. Deployments
  using prepared or read-only storage must set
  `MANAGE_SHARE_PERMISSIONS=0` and provide an existing directory.
- Published source-revision tags now use `sha-<full-git-commit>` instead of an
  abbreviated commit hash. Use an image digest when artifact identity must be
  immutable.

### Added

- Added `SAMBA_READY_INTERFACE` and `SAMBA_READY_TIMEOUT` so host-network
  deployments can wait for DHCP and healthcheck the selected LAN address.
- Added separate Compose overrides for local builds, read-only guest access,
  and trusted-LAN discovery.
- Added `MANAGE_SHARE_PERMISSIONS` for prepared and read-only mounts.
- Added OCI image metadata for source, version, and revision.
- Added reusable runtime smoke tests covering authenticated and guest access,
  password files, read-only mounts, UID/GID mapping, discovery services,
  recycle behavior, interface restrictions, and invalid input handling.
- Added a security policy and backup, restore, rollback, and UID/GID migration
  guidance.

### Changed

- Configuration is rendered to a temporary file, checked with `testparm`, and
  installed atomically before Samba starts. User, password, and share mutations
  happen only after validation succeeds.
- Boolean settings accept `0/1`, `false/true`, `no/yes`, and `off/on`, without
  silently treating unknown values as false.
- Recycle exclusions use Samba's comma-separated syntax. Legacy pipe-separated
  values remain accepted and are normalized at startup.
- Removed obsolete socket and asynchronous-I/O tuning so current Samba defaults
  remain effective.
- CI validates the exact multi-architecture candidate before promotion, runs a
  minimal arm64 runtime test, and performs scheduled vulnerability scans.
- Operator documentation is split into focused configuration, networking,
  operations, and data-recovery guides. Guest-mode and restore examples now
  remove inherited settings explicitly and preserve the current data volume.

### Fixed

- Host-network discovery deployments no longer report healthy when Samba
  started before the selected LAN interface received its IPv4 address.
- `Thumbs.db` is now covered by the veto-file rules in addition to
  `.Thumbs.db`.
- Recycle exclusions now affect actual delete behavior rather than only the
  rendered configuration.
- Read-only bind mounts can start without an unconditional ownership change.
- Leading-zero UID/GID values fail consistently instead of producing
  restart-dependent identity mismatches.
- Healthcheck credentials are written atomically with mode `0600`, and guest
  healthchecks consistently use anonymous authentication.

### Security

- Avahi now uses its built-in privilege drop and chroot behavior. WSDD2 runs as
  a dedicated unprivileged user and defaults to WSD-only mode.
- The default Compose service enables `no-new-privileges`, bounded log
  rotation, and a localhost-only bind address. The discovery override does not
  add `CAP_NET_ADMIN`.
- Added a build-context allowlist and ignored local secret paths so credentials
  are not sent to the image builder.
- Moved download and extraction tools into a separate build stage and pinned
  the Debian base image by digest.
- Startup rejects control characters, conflicting authentication modes,
  malformed password files, unsafe paths, and identity collisions before
  modifying container or share state.
