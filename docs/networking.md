# Networking and discovery

SMB access and device discovery are separate concerns. Clients can always
connect directly to a reachable host address; WSD and mDNS only make the server
appear automatically in network browsers.

## Deployment modes

| Mode | SMB exposure | Discovery | Notes |
|---|---|---|---|
| Base configuration | `127.0.0.1:445` | Disabled | Safe local default; bridge networking |
| Bridge with LAN bind | One selected host LAN address | Disabled | Portable and simple; use an address or existing DNS name |
| Discovery override | Host network | WSD and mDNS/DNS-SD | Intended for native Linux and one trusted LAN segment |

The base configuration does not expose SMB to peer devices. To allow direct
LAN access while retaining bridge networking, bind TCP 445 to one specific host
address:

```bash
SAMBA_BIND_ADDRESS=192.0.2.10 docker compose up -d
```

Replace the documentation address and persist it in `.env` if needed:

```dotenv
SAMBA_BIND_ADDRESS=192.0.2.10
```

Avoid `0.0.0.0`. Restrict TCP 445 to trusted clients with the host firewall and
connect by address or an existing DNS name.

## LAN discovery override

The supplied `docker-compose.discovery.yml` override:

- switches the service to host networking and removes the bridge port mapping;
- enables WSD for Windows and mDNS/DNS-SD for macOS and Linux;
- limits Samba, WSDD2, and Avahi to the selected interface;
- waits for the selected interface to receive IPv4 before Samba starts and
  verifies that address in the healthcheck;
- limits Samba clients to the selected LAN CIDR and loopback;
- leaves LLMNR disabled by default.

Set the actual Linux interface and trusted client network:

```bash
export SAMBA_LAN_INTERFACE=eno1
export SAMBA_LAN_NETWORK=192.0.2.0/24

docker compose \
  -f docker-compose.yml \
  -f docker-compose.discovery.yml \
  config --quiet
docker compose \
  -f docker-compose.yml \
  -f docker-compose.discovery.yml \
  up -d
```

Docker Compose 2.18.0 or newer is required so `ports: !reset []` actually
removes the base port mapping. The supplied override does not require added
Linux capabilities.

Host networking shares the host network namespace. Multicast discovery and
host networking can be unavailable or behave differently under Docker Desktop,
rootless Docker, VPNs, or routed and VLAN-separated networks. Use direct SMB
access in those environments unless discovery has been verified on the real
LAN.

The readiness wait prevents a common boot race with DHCP: Docker can restore a
host-network container after the interface exists but before its IPv4 address
has arrived. If the address is not ready within `SAMBA_READY_TIMEOUT`, startup
fails and the Compose restart policy retries it.

## Routed VPN access

Point-to-point interfaces such as WireGuard are not broadcast-capable and are
not suitable entries in Samba's restricted `interfaces` list. Do not add
`wg0` to `SAMBA_INTERFACES`.

Instead, route the selected LAN address through the VPN and use the same SMB
URL on both networks. For example, a WireGuard peer with a route for
`192.0.2.10/32` connects to `smb://192.0.2.10/public`. Keep the VPN client CIDR
in `SAMBA_HOSTS_ALLOW` so Samba accepts the tunneled source address. Discovery
multicast is not required and usually does not cross the VPN; use the IP or a
unicast DNS name.

## Protocols and firewall ports

Allow only the required traffic on the trusted interface:

| Service | Ports | Required when |
|---|---|---|
| SMB | TCP 445 | Always |
| WSD | UDP 3702 multicast and TCP 3702 unicast | `WSDD2_ENABLE=true` |
| mDNS/DNS-SD | UDP 5353 multicast | `AVAHI_ENABLE=true` |
| LLMNR | UDP 5355 multicast and TCP 5355 unicast | `WSDD2_LLMNR_ENABLE=true` |

The [Debian WSDD2 manual](https://manpages.debian.org/wsdd2) documents its
multicast groups, ports, and interface options. Legacy SMB1 and NetBIOS ports
137-139 are not used by this image.

LLMNR increases the name-resolution attack surface. Leave it disabled unless a
client specifically requires it:

```dotenv
WSDD2_LLMNR_ENABLE=1
```

This setting affects only the discovery override. It does not enable SMB1 or
NetBIOS name service.

## Names clients should use

- direct SMB: the selected host IP address or a DNS name you already manage;
- mDNS/DNS-SD: `<hostname>.local` on clients that support Bonjour/mDNS;
- WSD: the server should appear in the Windows Network view;
- container peers in the base bridge network: `samba` as the Compose service
  name.

A bare hostname and its `.local` form can resolve through different mechanisms.
Test the exact name used by the SMB client rather than assuming they are
equivalent.

## Verification

First confirm that Samba itself works by address. Discovery cannot compensate
for failed authentication, a blocked TCP 445, or incorrect storage permissions.

Linux:

```bash
smbclient -L //192.0.2.10 -U samba
```

macOS:

```bash
smbutil view //samba@192.0.2.10
dns-sd -B _smb._tcp local.
```

For WSD, check that Windows network discovery is enabled and that the client
and server can exchange multicast on the same LAN segment.

## Troubleshooting

If direct SMB works but discovery does not:

1. confirm the deployment runs on native Linux when using host networking;
2. verify `SAMBA_LAN_INTERFACE` names the physical LAN interface, not a Docker,
   VPN, or loopback interface;
3. verify `SAMBA_LAN_NETWORK` contains the client address;
4. allow the discovery ports above on that interface in both directions;
5. check whether Wi-Fi isolation, a VLAN boundary, VPN, or multicast filtering
   separates the client and server;
6. inspect `docker compose logs samba` for the WSDD2 and Avahi startup lines;
7. connect directly by IP to distinguish discovery from SMB or authentication
   failures.

If the container is unhealthy or direct access also fails, continue with
[Operations and troubleshooting](operations.md).
