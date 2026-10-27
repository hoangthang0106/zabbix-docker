# IT-MANAGER — Zabbix 7.4: IP 192.168.20.x, IP collision checks and security

## 1. Phạm vi chỉ LAN `192.168.20.0/24`

Đọc [danh sách IP `192.168.20.x`](IP-192.168.20.md) đã lọc từ lịch sử. Tài liệu gồm IP gateway `.1`, switch PoE `.42/.43/.54/.55/.58/.252/.254`, camera và FaceID, Proxmox `.248`, Ubuntu gần nhất `.206`; IP `.194` là DHCP reservation anh muốn khôi phục nhưng lần cuối còn trạng thái `Waiting`. **Không coi `.194` là IP đang rảnh.**

**Không quét live được MikroTik/Ubuntu từ GitHub.** Tuyệt đối không tự đặt thêm IP LAN `192.168.20.x` cho container, sửa DHCP, NAT hay đổi IP Ubuntu khi chưa có chứng cứ.

Docker networks `10.253.74.0/24` và `10.253.75.0/24` là **bridge riêng bên trong Docker**, không phải VLAN/IP vật lý khác trong LAN `192.168.20.0/24`. Không gán bridge Docker vào `192.168.20.0/24` vì trùng subnet của Ubuntu.

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
  https://raw.githubusercontent.com/hoangthang0106/zabbix-docker/19100df55f939fe0a76d0da8cd581c822261f1b8/scripts/check-it-network.sh
sudo bash /tmp/check-it-network.sh
```

The download is pinned to the specific reviewed Git commit `19100df` rather than a moving branch. Review the file before executing if desired. The script is read-only. It prints:
- IPv4 IPs assigned to the Ubuntu host (so you can see whether `.194` or `.206` is currently active)
- Current Linux route table
- Existing Docker networks/subnets
- Docker published host ports
- Collision checks against Docker bridge candidates, active host routes/interfaces and `192.168.20.0/24` only as the historically relevant LAN
- Host port bind test for `127.0.0.1:8380`
- Read-only cached neighbor entries in `192.168.20.0/24` (not a live sweep; absence doesn't mean unused)
- Docker Engine version check: older than 28 is blocked because Docker documents an L2 exposure affecting localhost-published container ports

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

- On `192.168.20.0/24`, permit monitoring from the Ubuntu source IP to managed hosts only on the required protocols (e.g. UDP/161 and ICMP); do not open general management access from untrusted camera devices. Preserve established/related firewall responses.
- For SNMP use **SNMPv3 authPriv**, read-only access, and restrict allowed poller source to the actual Ubuntu host. Docker NAT generally presents the Ubuntu source IP for outgoing LAN SNMP polling.
- No SNMP trap UDP/162 host port, no Zabbix server TCP/10051 host port or PostgreSQL TCP/5432 is published by this stack.
- Passive Zabbix agents, if added later, allow Zabbix outbound to TCP/10050 on a managed endpoint. Active agents/proxies would require explicitly allowing the server TCP/10051 and setting ACLs. Do not publish 10051 for this minimal setup.
- MikroTik gateway `.1`, PoE switches `.42/.43/.54/.55/.58/.252/.254`, Proxmox `.248`, and other confirmed devices on `192.168.20.x`: add each host with the matching Zabbix SNMP/API/agent template after successful installation. This stack does not automatically discover names/models without SNMP/API credentials and allowed routing.

## 6. Security, backup and update checklist

- Review the [official Zabbix Docker image tags](https://www.zabbix.com/documentation/7.4/en/manual/installation/containers) before updates. Floating `alpine-7.4-latest` moves on patches; image signatures/dependencies are NOT audited by this repository customization.
- No published database or external Zabbix ports; internal PostgreSQL Docker network.
- Docker Engine < 28.0.0: **do not assume localhost-published ports are unreachable from same-L2 peers**. Upgrade Docker or apply separately audited network-level controls before deployment. See [Docker official documentation](https://docs.docker.com/engine/network/port-publishing/).
- No `privileged`, host PID, `/var/run/docker.sock`, untrusted application scripts, public `0.0.0.0` web binding, or insecure hard-coded application DB password in the custom stack.
- The upstream fork has sample `env_vars/.POSTGRES_PASSWORD` = `zabbix`, but **the new Portainer stack does not use that file**. Never deploy raw upstream example compose with its demo credentials.
- Zabbix admin is still a default account on first install. Change it before allowing general LAN connectivity.
- PostgreSQL named volume is persistent, **not an offline backup**. Use tested `pg_dump` backups and copy them to separate HDD/NAS.
- Validate backup restore and image/security updates periodically. Do not claim malware-free or hack-proof without full independent code/image/dependency audit and continued patching.
- Keep Portainer management and Docker host SSH restricted to trusted administrative networks/VPN.

Official references: https://www.zabbix.com/documentation/7.4/en/manual/installation/containers and https://github.com/zabbix/zabbix-docker
