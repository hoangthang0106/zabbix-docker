# Zabbix for IT-MANAGER — Portainer (symlink-free branch)

This **portainer** branch contains only a standalone Compose stack plus documentation. The original 7.4 branch has 168 symlinks and Portainer rejects it with "repository contains a symlink". Do **not** disable Portainer security.

**Portainer → Stacks → Add stack → Repository**

- Name: `zabbix-it`
- Repository URL: `https://github.com/hoangthang0106/zabbix-docker`
- Repository reference: `refs/heads/portainer`
- Compose path: `docker-compose.yml`
- Stack environment variable (required): `ZABBIX_DB_PASSWORD` (random strong password, 24+ chars)

Portainer requires Compose-compatible Docker; use the official Zabbix 7.4 images. The web frontend is bound by default to **127.0.0.1:8380 on Ubuntu**, so a direct link to 192.168.20.206:8380 will not work until you deliberately enable a secure LAN access route.

Access securely from your Windows admin PC via an SSH tunnel to the Ubuntu Docker host:

```powershell
ssh -L 8380:127.0.0.1:8380 USER@192.168.20.206
```

Use the **actual current** Ubuntu IP and SSH username, not an assumed .206. Then open http://127.0.0.1:8380 on Windows. First login defaults to Admin / zabbix. Change it immediately before network exposure.

Docker bridge subnets `10.253.74.0/24` and `10.253.75.0/24` do not assign another address in **192.168.20.0/24**. They are candidate internal Docker networks, not proven free; host/Docker network overlap still needs to be checked on Ubuntu. The service publishes no database or Zabbix 10051 ingress ports. No Docker socket, privileged host mode or SNMP trap listener.

**IP notes:** see `IP-192.168.20.md`; those entries are historical records, not a live lease or ARP scan. `192.168.20.194` is a desired Ubuntu IP, not a confirmed free address.

Original upstream: `https://github.com/zabbix/zabbix-docker`. All upstream work remains on branch `7.4`.
