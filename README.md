# Zabbix for IT-MANAGER — Portainer (symlink-free branch)

This **portainer** branch contains only a standalone Compose stack plus documentation. The original 7.4 branch has 168 symlinks and Portainer rejects it with "repository contains a symlink". Do **not** disable Portainer security.

**Portainer → Stacks → Add stack → Repository**

- Name: `zabbix-it`
- Repository URL: `https://github.com/hoangthang0106/zabbix-docker`
- Repository reference: `refs/heads/portainer`
- Compose path: `docker-compose.yml`
- Stack environment variable (required): `ZABBIX_DB_PASSWORD` (random strong password, 24+ chars)

Portainer uses the official Zabbix 7.4 Docker images. **Per the user's latest explicit correction, the Ubuntu/Portainer LAN address to use is `192.168.20.194`, not `192.168.20.206`.** The web frontend defaults to binding specifically to `192.168.20.194:8380`.

**Open from a PC on the authorized LAN:** http://192.168.20.194:8380

Login (only on a fresh Zabbix DB): `Admin` / `zabbix`. **Change the password immediately** and restrict this port with an appropriate host or network firewall policy to trusted administrative IPs. Do not forward port 8380 to the public Internet. Plain HTTP is not encrypted; use HTTPS reverse proxy or VPN for ongoing administration.

**Important:** Binding `192.168.20.194` only works if that IP is actually assigned to the Ubuntu Docker host. Changing the Docker Compose file does **not** assign an address or update MikroTik DHCP. Verify on Ubuntu using `ip -4 addr`. If still bound to another IP, fix the host's network/DHCP reservation first; do not blindly deploy. If Portainer has an existing Stack environment variable `IT_ZABBIX_BIND_IP`, update it to `192.168.20.194` or remove it to use the new default, then **Update / Pull and redeploy**.


Docker bridge subnets `10.253.74.0/24` and `10.253.75.0/24` do not assign another address in **192.168.20.0/24**. They are candidate internal Docker networks, not proven free; host/Docker network overlap still needs to be checked on Ubuntu. The service publishes no database or Zabbix 10051 ingress ports. No Docker socket, privileged host mode or SNMP trap listener.

**IP notes:** see `IP-192.168.20.md`; those entries are historical records, not a live lease or ARP scan. The latest intended Ubuntu management address is `192.168.20.194`; inspect the host to ensure it is currently assigned.

Original upstream: `https://github.com/zabbix/zabbix-docker`. All upstream work remains on branch `7.4`.
