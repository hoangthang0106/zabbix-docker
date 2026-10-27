# IT-MANAGER — Zabbix 7.4 trên Ubuntu Docker/Portainer

**Dùng đúng `portainer-it-manager.yml` của fork này.** Không deploy `compose.yaml`/ `compose_pgsql.yaml` gốc trực tiếp vào Portainer: bản gốc sử dụng nhiều file `extends`, `env_file`, file secrets, mặc định HTTP 80/HTTPS 443 và Docker IPAM 172.16.238/239/240, dễ đụng hệ thống đang chạy. Khi bật profile `full`, image agent gốc còn sử dụng `privileged` và `pid: host`.

## Chức năng và phạm vi

- Zabbix Server 7.4 + PostgreSQL 17 + Nginx frontend; triển khai bằng image Zabbix **chính thức trên Docker Hub**.
- Theo dõi SNMP (MikroTik, Cisco, UniFi/switch), ICMP, HTTP(S), Zabbix agent passive; hỗ trợ thêm template Proxmox VE API nếu cấp đúng token/quyền.
- Không tự nhận biết VLAN/thiết bị nếu chưa thêm host/credential/template và firewall chưa cho phép.
- Không cài Agent/Java Gateway/Elasticsearch/Proxy/SNMP Trap Receiver trong bộ tối giản này. Không đưa Docker socket hoặc `privileged` vào container.
- DB, external scripts và alert scripts có named volumes. Volume **không thay thế backup sang HDD/NAS**.
- Không công bố DB 5432, trap 162/UDP hoặc Zabbix server 10051/TCP ra host. SNMP polling là kết nối **đi từ Zabbix tới thiết bị** qua UDP/161; không cần publish 161 trên host.

## Triển khai bằng Portainer

1. Portainer → môi trường Docker Ubuntu → **Stacks** → **Add stack** → **Repository**.
2. Điền:
   - **Name**: `zabbix-it`
   - **Repository URL**: `https://github.com/hoangthang0106/zabbix-docker`
   - **Repository reference**: `refs/heads/7.4`
   - **Compose path**: `portainer-it-manager.yml`
3. Phần **Environment variables**:
   - **BẮT BUỘC**: `ZABBIX_DB_PASSWORD` = mật khẩu ngẫu nhiên mạnh do anh tự lưu trong password manager, không ghi vào GitHub.
   - Tùy chọn: `IT_ZABBIX_WEB_PORT=8380` (mặc định 8380).
   - Tùy chọn: `IT_ZABBIX_BIND_IP=0.0.0.0` (mặc định tất cả địa chỉ của host; nên giới hạn bằng firewall LAN/VPN, hoặc thay bằng IP thực tế của Ubuntu khi đã cố định IP).
   - Tùy chọn: `IT_ZABBIX_MONITOR_SUBNET=10.253.74.0/24`.
   - Tùy chọn: `IT_ZABBIX_DB_SUBNET=10.253.75.0/24`.
   - Tùy chọn: `IT_ZABBIX_IMAGE_TAG=alpine-7.4-latest`.
4. Bấm **Deploy the stack**.
5. Vào **Containers** kiểm tra `zabbix-db` healthy, `zabbix-server` và `zabbix-web` running. Container `zabbix-db-init` dừng mã 0 sau khởi tạo là bình thường.
6. Mở `http://<IP-UBUNTU-HIỆN-TẠI>:8380`, không mặc định IP lịch sử còn đúng. Tài khoản Zabbix mặc định là `Admin` / `zabbix` khi mới khởi tạo: **đổi ngay mật khẩu**, tạo tài khoản riêng và bật HTTPS trước khi dùng ngoài LAN.

> Cổng `8380` chỉ là **lựa chọn chưa có trong danh sách cổng lịch sử**, không phải kết quả scan live. Nếu Portainer báo `address already in use` thì đặt `IT_ZABBIX_WEB_PORT` thành cổng host khác thực sự trống. Không sửa cổng bên trong `8080`.
>
> Nếu Portainer báo lỗi `overlapping IPv4 pools`, 2 subnet `10.253.74.0/24` và `10.253.75.0/24` cũng đã dùng ở máy này. Đổi **2 biến subnet** trên sang 2 dải chưa sử dụng. Không dùng 172.16.238/239/240 mặc định của upstream trong hệ thống có VLAN 172.16.x.x.

## Mạng/VLAN và firewall thực tế

- Ubuntu hiện nằm trong mạng `192.168.20.x` theo lịch sử, nhưng IP host đã từng thay đổi nên tài liệu **không cứng hóa .194 / .206**.
- Nếu trên MikroTik đang chặn camera VLAN khởi tạo kết nối tới mạng quản trị, Zabbix từ Ubuntu sẽ **không** giám sát được các VLAN khác trừ khi cho phép nguồn IP host Docker đi tới các IP/port giám sát cần thiết hoặc đặt Ubuntu vào server/management VLAN.
- Zabbix Docker dùng bridge + NAT mặc định; thiết bị trong LAN thường nhìn thấy nguồn là IP host Ubuntu.
- Thiết bị mạng: cho phép từ Ubuntu tới `UDP 161` (SNMP polling), ICMP; cấu hình SNMPv3 nếu thiết bị hỗ trợ, chỉ cấp quyền read-only và allowlist IP Zabbix.
- Agent passive: Zabbix Server đi tới TCP `10050` trên **máy được giám sát**. Không cần publish TCP `10051` của Zabbix server.
- Agent active/remote proxy: nếu triển khai sau cần **chủ động** publish/giới hạn TCP `10051` từ đúng VLAN/VPN và cấu hình agent tương ứng. Đừng mở ra Internet.
- Proxmox API: qua HTTPS `8006`, sử dụng template/API token quyền tối thiểu; không đưa token vào repo.

## Thêm host sau khi chạy

Zabbix → **Data collection → Hosts → Create host**:
- Group: ví dụ `Network / MikroTik / Cisco / UniFi / Proxmox / Server`.
- Interface SNMP: IP *thực* của thiết bị, thường port `161`.
- Template: chọn template chính thức tương ứng thiết bị/hệ điều hành; thiết bị SNMP-only chọn template SNMP phù hợp.
- Với Proxmox, dùng template `Proxmox VE by HTTP`/template hiện có phù hợp phiên bản, cấu hình API token ở host macros, không lưu token trong GitHub.
- Bật alert cho thiết bị offline, port uplink, CPU/RAM, storage; chỉnh thresholds theo môi trường thật.

## Vận hành

- Portainer → **Stacks** → `zabbix-it` → **Pull and redeploy** khi cần cập nhật 7.4 (sao lưu DB trước).
- Không xóa volumes khi update stack, đặc biệt `zabbix_postgres_data`.
- Sao lưu PostgreSQL bằng `pg_dump` có kiểm tra khả năng restore; chuyển file backup qua HDD/NAS **riêng khỏi SSD của VM**. Không coi volume mặc định là backup.
- Zabbix là monitoring/alerting; LibreNMS nếu đang dùng cũng giám sát SNMP. Hai hệ thống cùng polling tất cả thiết bị sẽ trùng dữ liệu/tốn tài nguyên; chỉ bật Zabbix cho nhóm/template/trigger thật sự cần bổ sung.

**Tài liệu gốc:** [Zabbix Docker](https://github.com/zabbix/zabbix-docker) · [Zabbix container install](https://www.zabbix.com/documentation/current/en/manual/installation/containers)
