# VPN 搭建 (WireGuard/OpenVPN)

## 1. VPN 方案选型

企业 VPN 是远程办公和多站点互联的基础。选择合适的 VPN 方案需要考虑安全性、性能、易用性和维护成本。

### 1.1 方案对比

| 特性 | WireGuard | OpenVPN | IPSec | Tailscale |
|------|-----------|---------|-------|-----------|
| 性能 | 极高（内核级） | 中（用户态） | 高（内核级） | 高 |
| 安全性 | 高（现代加密） | 高 | 高 | 高 |
| 配置复杂度 | 低 | 中 | 高 | 极低 |
| NAT 穿透 | 好 | 好 | 差 | 极好 |
| 移动端支持 | 好 | 好 | 一般 | 极好 |
| 适用场景 | 站点互联、远程接入 | 传统企业 | 站点互联 | 小团队 |

**推荐**：
- 远程办公接入 → WireGuard 或 Tailscale
- 站点互联（Site-to-Site）→ WireGuard 或 IPSec
- 需要复杂认证 → OpenVPN

## 2. WireGuard 部署

### 2.1 服务端配置

```bash
#!/bin/bash
# WireGuard 服务端安装配置

# 安装
yum install -y epel-release
yum install -y wireguard-tools

# 生成密钥
wg genkey | tee /etc/wireguard/server_private.key | wg pubkey > /etc/wireguard/server_public.key
chmod 600 /etc/wireguard/server_private.key

# 获取密钥
SERVER_PRIVATE_KEY=$(cat /etc/wireguard/server_private.key)
SERVER_PUBLIC_KEY=$(cat /etc/wireguard/server_public.key)

# 创建配置
cat > /etc/wireguard/wg0.conf << EOF
[Interface]
# 服务端私钥
PrivateKey = ${SERVER_PRIVATE_KEY}

# VPN 网段和监听端口
Address = 10.10.0.1/24
ListenPort = 51820

# 启用 IP 转发和 NAT
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

# 持久连接（NAT 穿透）
SaveConfig = false

# 客户端配置示例
[Peer]
# 客户端1
PublicKey = <CLIENT1_PUBLIC_KEY>
AllowedIPs = 10.10.0.2/32
PersistentKeepalive = 25

[Peer]
# 客户端2
PublicKey = <CLIENT2_PUBLIC_KEY>
AllowedIPs = 10.10.0.3/32
PersistentKeepalive = 25

# 站点互联（允许整个子网）
[Peer]
# 分支办公室
PublicKey = <SITE_B_PUBLIC_KEY>
AllowedIPs = 10.20.0.0/24, 10.10.0.0/24
Endpoint = site-b.example.com:51820
PersistentKeepalive = 25
EOF

# 启用内核转发
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
sysctl -p

# 启动服务
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

# 查看状态
wg show
```

### 2.2 客户端配置

```ini
# /etc/wireguard/wg0.conf (客户端)
[Interface]
PrivateKey = <CLIENT_PRIVATE_KEY>
Address = 10.10.0.2/24
DNS = 10.10.0.1

[Peer]
PublicKey = <SERVER_PUBLIC_KEY>
Endpoint = vpn.example.com:51820
AllowedIPs = 0.0.0.0/0        # 全流量模式
# AllowedIPs = 10.10.0.0/24   # 仅 VPN 网段
PersistentKeepalive = 25
```

### 2.3 客户端管理脚本

```bash
#!/bin/bash
# wg-client-manager.sh - WireGuard 客户端管理

set -euo pipefail

WG_DIR="/etc/wireguard"
WG_CONF="${WG_DIR}/wg0.conf"
VPN_SUBNET="10.10.0"
SERVER_ENDPOINT="vpn.example.com:51820"

add_client() {
    local client_name="$1"
    local client_ip="$2"
    
    # 生成密钥
    local private_key=$(wg genkey)
    local public_key=$(echo "$private_key" | wg pubkey)
    local preshared_key=$(wg genpsk)
    
    # 服务端配置
    cat >> "$WG_CONF" << EOF

[Peer]
# ${client_name}
PublicKey = ${public_key}
PresharedKey = ${preshared_key}
AllowedIPs = ${client_ip}/32
PersistentKeepalive = 25
EOF
    
    # 客户端配置
    local server_public_key=$(cat "${WG_DIR}/server_public.key")
    local client_conf="${WG_DIR}/clients/${client_name}.conf"
    
    mkdir -p "${WG_DIR}/clients"
    cat > "$client_conf" << EOF
[Interface]
PrivateKey = ${private_key}
Address = ${client_ip}/24
DNS = ${VPN_SUBNET}.1

[Peer]
PublicKey = ${server_public_key}
PresharedKey = ${preshared_key}
Endpoint = ${SERVER_ENDPOINT}
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
    
    # 生成二维码（方便移动端导入）
    qrencode -t ansiutf8 < "$client_conf"
    qrencode -o "${WG_DIR}/clients/${client_name}.png" < "$client_conf"
    
    # 重载 WireGuard
    wg set wg0 peer "$public_key" \
        preshared-key <(echo "$preshared_key") \
        allowed-ips "${client_ip}/32"
    
    echo "客户端 ${client_name} 创建成功"
    echo "配置文件: ${client_conf}"
    echo "IP 地址: ${client_ip}"
}

remove_client() {
    local client_name="$1"
    local client_pubkey="$2"
    
    wg set wg0 peer "$client_pubkey" remove
    sed -i "/# ${client_name}/,/^$/d" "$WG_CONF"
    
    echo "客户端 ${client_name} 已移除"
}

list_clients() {
    echo "=== WireGuard 客户端列表 ==="
    wg show wg0 peers | while read -r pubkey; do
        local endpoint=$(wg show wg0 endpoints | grep "$pubkey" | awk '{print $2}')
        local transfer=$(wg show wg0 transfer | grep "$pubkey")
        echo "Peer: $pubkey"
        echo "  Endpoint: $endpoint"
        echo "  Transfer: $transfer"
    done
}

# 使用示例
# add_client "zhangsan" "${VPN_SUBNET}.10"
# remove_client "zhangsan" "<public_key>"
# list_clients
```

## 3. OpenVPN 部署

### 3.1 服务端配置

```bash
#!/bin/bash
# OpenVPN 服务端安装配置

# 安装
yum install -y openvpn easy-rsa

# 初始化 PKI
cd /etc/openvpn
cp -r /usr/share/easy-rsa/3 ./easy-rsa
cd easy-rsa
./easyrsa init-pki
./easyrsa build-ca nopass
./easyrsa gen-req server nopass
./easyrsa sign-req server server
./easyrsa gen-dh
openvpn --genkey secret /etc/openvpn/ta.key

# 生成服务端配置
cat > /etc/openvpn/server.conf << 'EOF'
# 监听端口和协议
port 1194
proto udp

# 设备类型
dev tun

# 证书配置
ca /etc/openvpn/easy-rsa/pki/ca.crt
cert /etc/openvpn/easy-rsa/pki/issued/server.crt
key /etc/openvpn/easy-rsa/pki/private/server.key
dh /etc/openvpn/easy-rsa/pki/dh.pem
tls-auth /etc/openvpn/ta.key 0

# VPN 网段
server 10.8.0.0 255.255.255.0

# 保持客户端 IP
ifconfig-pool-persist /var/log/openvpn/ipp.txt

# 推送路由
push "route 10.1.0.0 255.255.0.0"
push "dhcp-option DNS 10.1.1.1"
push "dhcp-option DOMAIN example.com"

# 全流量模式（可选）
# push "redirect-gateway def1 bypass-dhcp"

# 客户端间通信
client-to-client

# 长连接
keepalive 10 120

# 加密算法
cipher AES-256-GCM
auth SHA256

# 压缩
compress lz4-v2

# 权限
user nobody
group nobody
persist-key
persist-tun

# 日志
status /var/log/openvpn/openvpn-status.log
log-append /var/log/openvpn/openvpn.log
verb 3
mute 20

# 管理接口
management 127.0.0.1 7505
EOF

# 启动服务
systemctl enable openvpn@server
systemctl start openvpn@server
```

### 3.2 客户端证书管理

```bash
#!/bin/bash
# openvpn-client-manager.sh

EASYRSA_DIR="/etc/openvpn/easy-rsa"
OUTPUT_DIR="/etc/openvpn/clients"
SERVER_IP="vpn.example.com"

generate_client() {
    local client_name="$1"
    
    cd "$EASYRSA_DIR"
    
    # 生成客户端证书
    ./easyrsa gen-req "$client_name" nopass
    ./easyrsa sign-req client "$client_name"
    
    # 生成客户端配置
    cat > "${OUTPUT_DIR}/${client_name}.ovpn" << EOF
client
dev tun
proto udp
remote ${SERVER_IP} 1194
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-GCM
auth SHA256
key-direction 1
verb 3

<ca>
$(cat pki/ca.crt)
</ca>
<cert>
$(openssl x509 -in "pki/issued/${client_name}.crt")
</cert>
<key>
$(cat "pki/private/${client_name}.key")
</key>
<tls-auth>
$(cat /etc/openvpn/ta.key)
</tls-auth>
EOF
    
    echo "客户端配置已生成: ${OUTPUT_DIR}/${client_name}.ovpn"
}

revoke_client() {
    local client_name="$1"
    
    cd "$EASYRSA_DIR"
    ./easyrsa revoke "$client_name"
    ./easyrsa gen-crl
    
    # 复制 CRL
    cp pki/crl.pem /etc/openvpn/
    
    echo "客户端 ${client_name} 已吊销"
}
```

## 4. VPN 安全最佳实践

### 4.1 安全加固

- 使用强加密算法（AES-256-GCM、ChaCha20-Poly1305）
- 启用双因素认证（2FA）
- 限制 VPN 访问权限（最小权限原则）
- 定期轮换密钥和证书
- 启用连接日志审计
- 配置防火墙规则限制 VPN 流量

### 4.2 监控与告警

```bash
# WireGuard 监控
#!/bin/bash
# 监控 VPN 连接状态
wg show wg0 | while read -r line; do
    if [[ "$line" == "peer:"* ]]; then
        peer_pubkey=$(echo "$line" | awk '{print $2}')
        endpoint=$(wg show wg0 endpoints | grep "$peer_pubkey" | awk '{print $2}')
        latest_handshake=$(wg show wg0 latest-handshakes | grep "$peer_pubkey" | awk '{print $2}')
        
        # 检查是否超时（>3分钟无握手）
        if [ "$latest_handshake" != "0" ]; then
            now=$(date +%s)
            diff=$((now - latest_handshake))
            if [ "$diff" -gt 180 ]; then
                echo "WARNING: Peer $peer_pubkey 可能离线 (最后握手: ${diff}秒前)"
            fi
        fi
    fi
done
```

## 5. 故障排查

```bash
# WireGuard 调试
wg show                    # 查看接口状态
wg show wg0 dump           # 详细转储
ip addr show wg0           # 查看接口地址
ip route show table all | grep wg0  # 查看路由

# OpenVPN 调试
tail -f /var/log/openvpn/openvpn.log
openvpn --status /var/log/openvpn/openvpn-status.log

# 网络测试
ping 10.10.0.1             # 测试 VPN 网关
traceroute 10.1.0.100      # 测试到内网的路由
tcpdump -i wg0 -n          # 抓包分析
```
