# Security Policy

## Supported versions

Security fixes are provided for the latest published image and the latest
release tag. Older commit-tagged images are not maintained or republished with
newer operating-system packages; pin a recorded digest when immutable artifact
identity is required.

## Reporting a vulnerability

Do not disclose a suspected vulnerability in a public issue.

Use GitHub's private vulnerability reporting feature from the repository's
**Security** tab. If private reporting is unavailable, open a public issue that
contains no sensitive details and asks the maintainer to establish a private
contact channel.

Include, when possible:

- the affected image tag or digest;
- the configuration required to reproduce the problem;
- the observed and expected behavior;
- a minimal reproduction that does not contain real credentials or data;
- any suggested mitigation.

The maintainer will acknowledge a complete report, assess affected versions,
and coordinate disclosure after a fix or mitigation is available.

## Deployment boundary

This image is intended for trusted private networks. SMB, WSD, LLMNR, and mDNS
must not be exposed directly to the public Internet. Operators remain
responsible for host firewall rules, network segmentation, credential rotation,
backups, and restricting access to the mounted share.
