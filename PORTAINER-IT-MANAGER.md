# IT-MANAGER — Zabbix 7.4: verified scope, VLANs, IP collision checks and security

## 1. Important: history is NOT live network discovery

This list was reconstructed from the IT-MANAGER network topology and chat history. **No remote scan of the user's live MikroTik, Proxmox or Ubuntu has been performed.**

| Network / item | Historical observation | Confidence |
| --- | --- | --- |
| VLAN 1, management | `10.10.10.0/24`; MikroTik/gateway `10.10.10.1`; Cisco core C1300 `10.10.10.2` | Network topology |
| VLAN 20, cameras | `192.168.20.0/24`; gateway `192.168.20.1` | Network topology |
| VLAN 12, staff | `172.16.200.0/23`; gateway `172.16.200.1` | Network topology |
| VLAN 13, guest | `172.16.100.0/23`; gateway `172.16.100.1` | Network topology |
| UniFi UCK G2 Plus | `172.16.1.248` via `172.16.1.1`, subnet `172.16.1.0/24` | Network topology |
| Ubuntu/Portainer | Initially `192.168.20.194`, later reported as `192.168.20.206`; user wants to restore `.194` | **Latest user-reported .206; not verified live today** |
| `192.168.10.0/24` | Examples in prior discussions; not established as active network | **Unverified** |
| Docker bridge networks | 172.x addresses observed by user; actual Docker subnets not provided | **Unknown** |
| LibreNMS host HTTP port | 8000 appeared in example/compose; not confirmed real host port | **Unknown** |

**Do not force DHCP reservation or static IP `192.168.20.194` through this Docker stack.** Configure the Ubuntu host's lease/reservation on MikroTik separately, after checking active leases, ARP and DHCP. Do not assume `.194` is free.

## 2. How the custom Portainer stack avoids known overlap

Use [portainer-it-manager.yml](portainer-it-manager.yml), **not** the upstream `compose.yaml`, which uses many auxiliary files, default ports 80/443, sample credentials, and example 172.16.238/239/240 IPAM pools.

The custom stack uses:
- `10.253.74.0/24` (Docker monitoring bridge)
- `10.253.75.0/24` (Docker *internal* database bridge)
- Web host TCP `8380`
- **Web binds to `127.0.0.1` by default**, never `0.0.0.0`
- Zabbix 7.4 official Docker images, PostgreSQL 17; persistent named database volume
- No Docker socket, `privileged`, host PID, SNMP-trap publishing, extra proxy/Elasticsearch/Selenium or agent container

The two `10.253.*` candidate bridges are outside the **listed** IP subnets but **cannot be certified unused** until checked on the real Ubuntu (existing Docker networks, routes, interfaces) and MikroTik.

## 3. Mandatory preflight, only SSH step

On the Ubuntu host (not inside Portainer):

```bash
curl -fsSLo /tmp/check-it-network.sh \
  https://raw.githubusercontent.com/hoangthang0106/zabbix-docker/7.4/scripts/check-it-network.sh
sudo bash /tmp/check-it-network.sh
```

The script is read-only. It prints:
- IPv4 IPs assigned to the Ubuntu host (so you can see whether `.194` or `.206` is currently active)
- Current Linux route table
- Existing Docker networks/subnets
- Docker published host ports
- Collision checks against the candidate Docker networks and known historical VLANs
- Host port bind test for `127.0.0.1:8380`

**If it prints FAIL, do not deploy.** Set unused subnets using the same two variables BOTH when running the script and in Portainer. Example:
```bash
sudo IT_ZABBIX_MONITOR_SUBNET=10.254.74.0/24 \
     IT_ZABBIX_DB_SUBNET=10.254.75.0/24 \
     bash /tmp/check-it-network.sh
```

These alternative addresses are **examples, not known-free allocations**; only choose ones that pass checks and don't appear in MikroTik route/VLAN/DHCP inventories. A successful PASS is local evidence, not a guarantee that a remote routed network is unused.

## 4. Portainer install, no port collision assumptions

Portainer → **Stacks** → **Add stack** → **Repository**:
- **Name:** `zabbix-it`
- **URL:** `https://github.com/hoangthang0106/zabbix-docker`
- **Repository reference:** `refs/heads/7.4`
- **Compose path:** `portainer-it-manager.yml`

Stack environment:
- **Required** `ZABBIX_DB_PASSWORD`: generate/store a long random password locally; never commit to GitHub. Be aware Docker administrators can view container environment values in Inspect.
- Optional `IT_ZABBIX_WEB_PORT=8380`; only change after host conflict check.
- Optional `IT_ZABBIX_MONITOR_SUBNET=10.253.74.0/24`
- Optional `IT_ZABBIX_DB_SUBNET=10.253.75.0/24`
- Optional `IT_ZABBIX_BIND_IP=127.0.0.1` (default and recommended for first setup)
- Optional `IT_ZABBIX_IMAGE_TAG=alpine-7.4-latest`

**Deploy the stack**. The `zabbix-db-init` container exiting successfully is expected; DB/server/web remain running.

### Initial login without putting default Admin credentials on a camera LAN

The web UI is intentionally **not reachable via http://192.168.20.206:8380 by default**. Make a local SSH tunnel from the Windows PC that has access to Ubuntu:

```powershell
ssh -L 8380:127.0.0.1:8380 <ubuntu-ssh-user>@192.168.20.206
```

Replace `192.168.20.206` with the **actual live IPv4 shown by preflight**, not the old `.194` by assumption. With the tunnel open, access **http://127.0.0.1:8380** on that Windows PC.

On the *newly initialized* Zabbix database, default login is `Admin` / `zabbix`. Immediately change that password, configure roles/MFA if supported, set strong admin practices, and do not NAT any Zabbix management ports to the public Internet.

### LAN/VPN access only after hardening

For LAN access, set e.g. `IT_ZABBIX_BIND_IP=192.168.20.206` **only if the host actually owns that address**, then redeploy *after* configuring firewall/ACL and preferably an HTTPS reverse proxy. LAN exposure on camera VLAN 20 is **less desirable** than moving the Ubuntu host to a server/management VLAN or serving the UI only over VPN/HTTPS. Binding to one address is NOT the same as access control; devices within that VLAN could still reach it.

## 5. Firewall, SNMP and management

- Keep the camera VLAN unable to initiate toward staff/management. Monitoring needs a specific **allow rule from Ubuntu/Zabbix to managed hosts** (e.g. UDP/161 and ICMP) before broad camera-to-management deny rules; preserve stateful related/established traffic.
- For SNMP use **SNMPv3 authPriv**, read-only access, and restrict allowed poller source to the actual Ubuntu host. Docker NAT generally presents the Ubuntu source IP for outgoing LAN SNMP polling.
- No SNMP trap UDP/162 host port, no Zabbix server TCP/10051 host port or PostgreSQL TCP/5432 is published by this stack.
- Passive Zabbix agents, if added later, allow Zabbix outbound to TCP/10050 on a managed endpoint. Active agents/proxies would require explicitly allowing the server TCP/10051 and setting ACLs. Do not publish 10051 for this minimal setup.
- MikroTik, C1300, CBS250, UniFi UCK, Proxmox API 8006, Windows: add each host and the matching Zabbix SNMP/API/agent template after successful initial install. This stack does not automatically discover names/models without SNMP/API credentials and allowed routing.

## 6. Security, backup and update checklist

- Review the [official Zabbix Docker image tags](https://www.zabbix.com/documentation/7.4/en/manual/installation/containers) before updates. Floating `alpine-7.4-latest` moves on patches; image signatures/dependencies are NOT audited by this repository customization.
- No published database or external Zabbix ports; internal PostgreSQL Docker network.
- No `privileged`, host PID, `/var/run/docker.sock`, untrusted application scripts, public `0.0.0.0` web binding, or insecure hard-coded application DB password in the custom stack.
- The upstream fork has sample `env_vars/.POSTGRES_PASSWORD` = `zabbix`, but **the new Portainer stack does not use that file**. Never deploy raw upstream example compose with its demo credentials.
- Zabbix admin is still a default account on first install. Change it before allowing general LAN connectivity.
- PostgreSQL named volume is persistent, **not an offline backup**. Use tested `pg_dump` backups and copy them to separate HDD/NAS.
- Validate backup restore and image/security updates periodically. Do not claim malware-free or hack-proof without full independent code/image/dependency audit and continued patching.
- Keep Portainer management and Docker host SSH restricted to trusted administrative networks/VPN.

Official references: https://www.zabbix.com/documentation/7.4/en/manual/installation/containers and https://github.com/zabbix/zabbix-docker
