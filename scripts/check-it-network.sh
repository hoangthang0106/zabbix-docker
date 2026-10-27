#!/usr/bin/env bash
# Read-only audit: no iptables, network, Docker or route configuration changes.
set -euo pipefail

python3 - <<'PY'
import ipaddress
import json
import os
import re
import socket
import subprocess
import sys

LAN = ipaddress.ip_network("192.168.20.0/24")
KNOWN = {
    "Local camera / server LAN": "192.168.20.0/24",
}
# Historical record only, not live discovery or reservation.
RECORDED = {
    1: "MikroTik camera LAN gateway",
    42: "PoE switch G",
    43: "PoE switch T9",
    54: "PoE switch T5",
    55: "PoE switch T6",
    58: "PoE switch T8",
    69: "Recorded on both NVR01 and NVR02 lists; verify actual MAC",
    150: "Elevator device (historical)",
    151: "Elevator device (historical)",
    152: "Elevator device (historical)",
    153: "Elevator device (historical)",
    154: "Elevator device (historical)",
    155: "Elevator device (historical)",
    194: "Ubuntu desired reservation, previously Waiting — NOT confirmed assigned",
    200: "FaceID",
    201: "FaceID",
    202: "Door/access device",
    206: "Last reported Ubuntu/Portainer IP — check live",
    212: "Camera",
    213: "Camera",
    214: "Camera",
    215: "Camera",
    248: "Proxmox (confirmed screenshot in earlier chat)",
    252: "PoE switch T11",
    253: "NVR/other equipment previously reported — verify",
    254: "PoE switch T7 (corrected from NVR)",
}

DEFAULTS = {
    "IT_ZABBIX_MONITOR_SUBNET": "10.253.74.0/24",
    "IT_ZABBIX_DB_SUBNET": "10.253.75.0/24",
    "IT_ZABBIX_WEB_PORT": "8380",
    "IT_ZABBIX_BIND_IP": "127.0.0.1",
}
settings = {k: os.environ.get(k, default) for k, default in DEFAULTS.items()}
errors = []
warnings = []

def run(args):
    return subprocess.run(args, capture_output=True, text=True, check=False)

def parse_network(value, source):
    try:
        return ipaddress.ip_network(value, strict=False)
    except ValueError as exc:
        errors.append(f"{source}: invalid network {value!r}: {exc}")
        return None

def parse_json_command(args, label):
    p = run(args)
    if p.returncode:
        errors.append(f"{label}: command failed ({p.stderr.strip() or p.stdout.strip()})")
        return None
    try:
        return json.loads(p.stdout)
    except json.JSONDecodeError as exc:
        errors.append(f"{label}: invalid JSON ({exc})")
        return None

print("ZABBIX / IT-MANAGER — 192.168.20.x DEVICE INVENTORY & SAFE DOCKER PRE-FLIGHT")
print("Only relevant device LAN: 192.168.20.0/24. Historical addresses (NOT scanned):")
for octet, label in sorted(RECORDED.items()):
    print(f"  192.168.20.{octet:<3} {label}")

monitor = parse_network(settings["IT_ZABBIX_MONITOR_SUBNET"], "monitor")
db = parse_network(settings["IT_ZABBIX_DB_SUBNET"], "database")
candidates = [("monitor", monitor), ("database", db)]
candidates = [(k, n) for k, n in candidates if n]
for label, candidate in candidates:
    if candidate.version != 4:
        errors.append(f"{label}: expected IPv4 subnet")
    if not candidate.is_private:
        errors.append(f"{label}: use a private IPv4 subnet, got {candidate}")

if len(candidates) == 2 and candidates[0][1].overlaps(candidates[1][1]):
    errors.append("Zabbix monitoring and database subnets overlap")

for label, net in candidates:
    for area, cidr in KNOWN.items():
        known_net = ipaddress.ip_network(cidr)
        if net.overlaps(known_net):
            errors.append(f"{label} subnet {net} overlaps known/historical area {area}: {cidr}")

host_addrs = parse_json_command(["ip", "-j", "-4", "address", "show"], "host IPv4 addresses")
live_ipv4 = set()
if host_addrs is not None:
    print("\nIPv4 addresses on the LIVE Ubuntu host:")
    for iface in host_addrs:
        for item in iface.get("addr_info", []):
            addr = item.get("local")
            if addr:
                live_ipv4.add(addr)
                print(f"  {iface.get('ifname', '?'):18s} {addr}/{item.get('prefixlen', '?')}")
                net = parse_network(f"{addr}/{item.get('prefixlen', 32)}", "host interface")
                if net:
                    for label, cand in candidates:
                        if cand.overlaps(net):
                            errors.append(f"{label} {cand} overlaps interface {iface.get('ifname')} ({net})")

# Read-only neighbor table, not an ARP sweep; an absent entry does NOT mean a free IP.
neighbors = parse_json_command(["ip", "-j", "-4", "neigh", "show"], "LAN neighbor table")
if neighbors is not None:
    print("\\nCached neighbor entries in 192.168.20.0/24 (not a full scan):")
    for entry in neighbors:
        addr = entry.get("dst", "")
        try:
            candidate = ipaddress.ip_address(addr)
        except ValueError:
            continue
        if candidate in LAN:
            mac = entry.get("lladdr", "-")
            state = ",".join(entry.get("state", [])) if isinstance(entry.get("state", []), list) else str(entry.get("state", ""))
            print(f"  {addr:16s} MAC={mac:17s} interface={entry.get('dev', '-')}; state={state}")
print("NOTE: For authoritative current occupancy, compare MikroTik DHCP leases, ARP, static-IP inventory.")

routes = parse_json_command(["ip", "-j", "-4", "route", "show", "table", "all"], "IPv4 route table")
if routes is not None:
    print("\nLive non-default IPv4 routes:")
    for route in routes:
        dst = route.get("dst", "default")
        if dst == "default":
            continue
        net = parse_network(dst, "system route")
        if not net:
            continue
        via = route.get("gateway") or route.get("dev") or "unknown"
        print(f"  {str(net):20s} via {via}")
        for label, cand in candidates:
            if net.overlaps(cand):
                errors.append(f"{label} {cand} overlaps existing host route {net} via {via}")

# Docker Engine releases older than 28.0.0 may expose localhost-published
# container ports to peers on the same L2 segment (Docker's documented warning).
ver = run(["docker", "version", "--format", "{{.Server.Version}}"])
if ver.returncode:
    errors.append("Cannot determine Docker Engine server version")
else:
    version_text = ver.stdout.strip()
    print(f"\nDocker Engine server version: {version_text}")
    match = re.match(r"^(\d+)\.", version_text)
    if not match:
        errors.append(f"Unrecognized Docker Engine version: {version_text}")
    elif int(match.group(1)) < 28:
        errors.append("Docker Engine < 28: localhost-published ports may be reachable from same-L2 devices; upgrade Docker before relying on 127.0.0.1 binding")

ids = run(["docker", "network", "ls", "-q"])
if ids.returncode:
    errors.append("docker network list unavailable: run this script with sudo on Docker host")
elif ids.stdout.strip():
    docker_networks = parse_json_command(
        ["docker", "network", "inspect", *ids.stdout.split()],
        "Docker network inspect"
    )
    if docker_networks is not None:
        print("\nExisting Docker network subnets:")
        for nw in docker_networks:
            for item in nw.get("IPAM", {}).get("Config") or []:
                cidr = item.get("Subnet")
                if not cidr:
                    continue
                existing = parse_network(cidr, "Docker network")
                if not existing or existing.version != 4:
                    continue
                print(f"  {nw.get('Name', '?'):28s} {existing}")
                for label, cand in candidates:
                    if cand.overlaps(existing):
                        errors.append(f"{label} {cand} overlaps existing Docker network {nw.get('Name')} {existing}")

try:
    port = int(settings["IT_ZABBIX_WEB_PORT"])
    if not (1024 <= port <= 65535):
        raise ValueError("port must be 1024..65535")
except ValueError as exc:
    errors.append(f"Invalid IT_ZABBIX_WEB_PORT: {exc}")
    port = None

bind_ip = settings["IT_ZABBIX_BIND_IP"]
try:
    bind_addr = ipaddress.ip_address(bind_ip)
    if bind_addr.version != 4:
        errors.append(f"Web bind address must be IPv4: {bind_ip}")
    if bind_ip not in live_ipv4 and bind_ip != "0.0.0.0":
        errors.append(f"Web bind IP {bind_ip} is not assigned to the Ubuntu host")
    if bind_ip == "0.0.0.0":
        warnings.append("Binding 0.0.0.0 exposes the web UI on EVERY host interface; avoid on camera/public networks.")
    elif bind_ip != "127.0.0.1":
        warnings.append(f"Web UI accessible on LAN address {bind_ip}; secure with LAN/VPN ACL + HTTPS and change default Admin password.")
except ValueError:
    errors.append(f"Invalid IT_ZABBIX_BIND_IP: {bind_ip}")

if port is not None:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        try:
            sock.bind((bind_ip, port))
        except OSError as exc:
            errors.append(f"Host TCP port bind {bind_ip}:{port} unavailable: {exc}")

ps = run(["docker", "ps", "--format", "{{.Names}}|{{.Ports}}"])
if ps.returncode:
    errors.append("Cannot inspect Docker published ports: run with sudo")
elif port is not None:
    print("\nContainers publishing host TCP ports:")
    for line in ps.stdout.splitlines():
        if "|" not in line:
            continue
        name, ports = line.split("|", 1)
        if "->" in ports:
            print(f"  {name}: {ports}")
        if re.search(rf"(?:^|[:,\s]){port}->", ports):
            errors.append(f"Requested port {port}/tcp already published by {name}")

print(f"\nPlanned: monitoring={monitor}; database={db}; web={bind_ip}:{port}")
for w in warnings:
    print("WARNING:", w)
for e in errors:
    print("ERROR:", e)
if errors:
    print(f"\nFAIL: {len(errors)} conflict(s). Fix the IP, subnet or port before deploying.")
    sys.exit(1)
print("\nPASS: No collision found in the known subnets, LIVE host routes/interfaces, Docker IPAM or published TCP port.")
print("NOTE: Cannot prove unused IP space behind a router or absence of attacks; check MikroTik routes/DHCP/firewall separately.")
PY
