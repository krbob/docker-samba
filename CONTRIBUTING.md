# Contributing

Contributions should keep the image small, preserve secure defaults, and avoid
adding configuration that cannot be exercised by an automated test.

Security vulnerabilities must be reported through the private process in
`SECURITY.md`, not through a public issue or pull request.

## Local requirements

The complete local workflow requires:

- Git;
- Docker Engine with BuildKit/buildx;
- Docker Compose 2.18.0 or newer;
- Bash and standard POSIX command-line tools;
- ShellCheck, Hadolint, and actionlint for the same static checks used by CI.

Linux is required to validate real host-network discovery behavior. Docker
Desktop is sufficient for normal image builds and most smoke tests, but it does
not prove that WSD or mDNS is visible to clients on a physical LAN.

Never commit `.env`, `.secrets/`, password files, share contents, or backup
archives. To run the development Compose stack, create a local secret first:

```sh
cp .env.example .env
mkdir -p .secrets
chmod 700 .secrets
(
  umask 077
  printf '%s\n' 'replace-with-a-local-test-password' > .secrets/samba_password
)
chmod 600 .secrets/samba_password
```

## Static checks

Run syntax and shell lint checks from the repository root:

```sh
sh -n \
  etc/cont-init.d/01-samba-init \
  etc/samba-healthcheck \
  etc/services.d/smbd/run \
  etc/services.d/wsdd/run \
  etc/services.d/avahi/run
bash -n tests/smoke.sh
shellcheck \
  etc/cont-init.d/01-samba-init \
  etc/samba-healthcheck \
  etc/services.d/smbd/run \
  etc/services.d/wsdd/run \
  etc/services.d/avahi/run \
  tests/smoke.sh
hadolint --ignore DL3008 Dockerfile
actionlint
git diff --check
```

Validate every supported Compose combination. The discovery values below are
documentation-only test values and do not authorize access from that network:

```sh
docker compose -f docker-compose.yml config --quiet
docker compose -f docker-compose-test.yml config --quiet
docker compose \
  -f docker-compose.yml \
  -f docker-compose.dev.yml \
  config --quiet
docker compose \
  -f docker-compose.yml \
  -f docker-compose.guest.yml \
  config --quiet
SAMBA_LAN_INTERFACE=eth0 SAMBA_LAN_NETWORK=192.0.2.0/24 \
  docker compose \
    -f docker-compose.yml \
    -f docker-compose.discovery.yml \
    config --quiet
```

If a lint tool is not installed locally, its pinned container image and exact
CI invocation are defined near the top of `.github/workflows/ci.yml`.

## Build and runtime tests

Build the image that the smoke suite expects:

```sh
docker build \
  --build-arg IMAGE_VERSION=dev \
  --build-arg VCS_REF="$(git rev-parse HEAD)" \
  -t local/samba:test .
```

Then run the complete smoke suite:

```sh
bash tests/smoke.sh
```

The full suite runs on amd64 in CI. The published arm64 child image receives
the baseline network, authentication, and runtime checks with
`SAMBA_SMOKE_SCOPE=minimal` under QEMU.

Advanced smoke controls are intended for CI and focused local diagnosis:

| Variable | Default | Contract |
|---|---|---|
| `SAMBA_TEST_IMAGE` | `local/samba:test` | Existing image to test; the suite retags it as `local/samba:test` |
| `SAMBA_TEST_COMPOSE_FILE` | `docker-compose-test.yml` | Must define service `samba`, share `public`, password `test-password`, and a reachable Compose network |
| `SAMBA_SMOKE_SCOPE` | `full` | `minimal` stops after baseline network and authentication checks |

The suite creates temporary containers, volumes, and directories and removes
them on exit. Do not run it against a Docker context containing production
workloads unless that context is intentionally used for development tests.

For an interactive local deployment built from the worktree:

```sh
docker compose \
  -f docker-compose.yml \
  -f docker-compose.dev.yml \
  up -d --build
docker compose logs --tail=100 samba
docker compose down
```

Do not claim LAN discovery support from a container-only smoke test. Test the
discovery override on a Linux host and a trusted physical LAN when changing
Avahi, WSDD2, interface filtering, host networking, or capabilities.

## Change guidelines

- Keep pull requests focused and use intentional commits.
- Add or update a smoke test for user-visible runtime behavior and regressions.
- Update `CHANGELOG.md` for notable, breaking, or security-relevant changes.
- Update operator documentation when defaults, secrets, storage ownership,
  ports, backup behavior, or upgrade steps change.
- Preserve compatibility where it does not weaken validation or security;
  document unavoidable breaking changes explicitly.
- Do not add a license or change licensing terms without an explicit maintainer
  decision. The repository currently has no declared project license.
