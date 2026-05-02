# DNS 管理 (CoreDNS/BIND)

## 1. DNS 架构概述

DNS 是互联网的基础服务，企业内部 DNS 的可靠性直接影响所有业务的可用性。本文档涵盖 BIND（传统 DNS）和 CoreDNS（云原生 DNS）两大主流方案。

### 1.1 企业 DNS 架构

```
                  ┌─────────────────┐
                  │   公网 DNS       │  ← 权威 DNS（域名注册商）
                  └────────┬────────┘
                           │
                  ┌────────┴────────┐
                  │   递归 DNS       │  ← 企业出口 DNS
                  │  (BIND/Unbound) │
                  └────────┬────────┘
                           │
            ┌──────────────┼──────────────┐
            │              │              │
   ┌────────┴───┐  ┌──────┴─────┐  ┌────┴────────┐
   │ 内部权威 DNS │  │ K8s DNS    │  │ 服务发现    │
   │   (BIND)    │  │ (CoreDNS)  │  │ (Consul)    │
   └─────────────┘  └────────────┘  └─────────────┘
```

## 2. BIND 配置

### 2.1 安装与基础配置

```bash
# 安装 BIND
yum install -y bind bind-utils bind-chroot

# 主配置文件
cat > /etc/named.conf << 'EOF'
options {
    listen-on port 53 { any; };
    listen-on-v6 port 53 { any; };
    directory "/var/named";
    dump-file "/var/named/data/cache_dump.db";
    statistics-file "/var/named/data/named_stats.txt";
    memstatistics-file "/var/named/data/named_mem_stats.txt";
    
    # 允许查询的客户端
    allow-query { trusted; };
    allow-query-cache { trusted; };
    
    # 转发器
    forwarders {
        223.5.5.5;      # 阿里 DNS
        119.29.29.29;   # 腾讯 DNS
    };
    forward first;
    
    # 安全配置
    dnssec-validation auto;
    auth-nxdomain no;
    version "Not Available";
    hostname "Not Available";
    server-id "Not Available";
    
    # 速率限制
    rate-limit {
        responses-per-second 10;
        window 5;
    };
    
    # 递归限制
    max-ncache-ttl 3600;
    max-cache-ttl 86400;
};

# ACL 定义
acl "trusted" {
    127.0.0.1;
    10.0.0.0/8;
    172.16.0.0/12;
    192.168.0.0/16;
};

# 日志配置
logging {
    channel default_log {
        file "/var/log/named/named.log" versions 3 size 100m;
        severity info;
        print-time yes;
        print-category yes;
        print-severity yes;
    };
    channel query_log {
        file "/var/log/named/query.log" versions 5 size 200m;
        severity info;
        print-time yes;
    };
    category default { default_log; };
    category queries { query_log; };
};

# 区域配置
zone "." IN {
    type hint;
    file "named.ca";
};

zone "example.com" IN {
    type master;
    file "zones/example.com.zone";
    allow-transfer { 10.1.1.2; };
    also-notify { 10.1.1.2; };
};

zone "1.10.in-addr.arpa" IN {
    type master;
    file "zones/10.1.rev";
    allow-transfer { 10.1.1.2; };
};

zone "internal.example.com" IN {
    type master;
    file "zones/internal.example.com.zone";
    allow-update { key rndc-key; };
};
EOF
```

### 2.2 区域文件配置

```bash
# /var/named/zones/example.com.zone
$TTL 86400
@   IN  SOA  ns1.example.com. admin.example.com. (
            2024020301  ; Serial (YYYYMMDDNN)
            3600        ; Refresh
            1800        ; Retry
            604800      ; Expire
            86400       ; Minimum TTL
)

; 名称服务器
@       IN  NS      ns1.example.com.
@       IN  NS      ns2.example.com.

; A 记录
ns1     IN  A       10.1.1.1
ns2     IN  A       10.1.1.2
@       IN  A       10.1.1.100
www     IN  A       10.1.1.100
mail    IN  A       10.1.1.200

; 负载均衡（多 A 记录）
api     IN  A       10.1.1.10
api     IN  A       10.1.1.11
api     IN  A       10.1.1.12

; CNAME 记录
cdn     IN  CNAME   cdn.example.com.cdncloud.com.
blog    IN  CNAME   www.example.com.

; MX 记录
@       IN  MX  10  mail.example.com.
@       IN  MX  20  mail2.example.com.

; TXT 记录（SPF）
@       IN  TXT     "v=spf1 mx ip4:10.1.1.200 -all"

; SRV 记录
_sip._tcp   IN  SRV 10 60 5060 sip.example.com.

; 服务发现
_api._tcp   IN  SRV 10 60 8080 api-01.example.com.
_api._tcp   IN  SRV 10 60 8080 api-02.example.com.
```

### 2.3 反向解析区域

```bash
# /var/named/zones/10.1.rev
$TTL 86400
@   IN  SOA  ns1.example.com. admin.example.com. (
            2024020301
            3600
            1800
            604800
            86400
)

@       IN  NS      ns1.example.com.
@       IN  NS      ns2.example.com.

1.1     IN  PTR     ns1.example.com.
2.1     IN  PTR     ns2.example.com.
100.1   IN  PTR     www.example.com.
200.1   IN  PTR     mail.example.com.
```

## 3. CoreDNS 配置

### 3.1 Corefile 配置

```corefile
# /etc/coredns/Corefile
.:53 {
    # 错误日志
    errors
    
    # 健康检查
    health {
        lameduck 5s
    }
    
    # 准备就绪检查
    ready
    
    # Prometheus 指标
    prometheus :9153
    
    # 日志配置
    log . "{remote} - {type} {name} {rcode} {size} {duration}"
    
    # 缓存配置
    cache 30 {
        success 9984 30
        denial 9984 5
        prefetch 1 1m 10%
    }
    
    # 转发配置
    forward . 223.5.5.5 119.29.29.29 {
        health_check 5s
        expire 3600
        max_concurrent 1000
    }
    
    # DNSSEC
    dnssec
    
    # 重写规则
    rewrite name suffix example.com.cluster.local example.com
    
    # 负载均衡
    loadbalance round_robin
    
    # 缓存
    loop
    reload 6s
}

# 企业内部域名
internal.example.com:53 {
    errors
    log
    file /etc/coredns/zones/internal.example.com.db
}

# Kubernetes 集群域名
cluster.local:53 {
    errors
    kubernetes {
        pods insecure
        fallthrough in-addr.arpa ip6.arpa
        ttl 30
    }
    forward . /etc/resolv.conf
}

# 反向解析
in-addr.arpa:53 {
    errors
    kubernetes {
        pods insecure
        fallthrough in-addr.arpa ip6.arpa
    }
}
```

### 3.2 Kubernetes CoreDNS ConfigMap

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
data:
  Corefile: |
    .:53 {
        errors
        health {
            lameduck 5s
        }
        ready
        kubernetes cluster.local in-addr.arpa ip6.arpa {
            pods insecure
            fallthrough in-addr.arpa ip6.arpa
            ttl 30
        }
        prometheus :9153
        forward . /etc/resolv.conf {
            max_concurrent 1000
        }
        cache 30
        loop
        reload
        loadbalance
    }
    
    # 自定义域名
    internal.example.com:53 {
        errors
        cache 30
        forward . 10.1.1.1 10.1.1.2
    }
```

## 4. DNS 高可用

### 4.1 主从同步

```bash
# 主服务器配置
zone "example.com" IN {
    type master;
    file "zones/example.com.zone";
    allow-transfer { 10.1.1.2; key transfer-key; };
    also-notify { 10.1.1.2; };
};

# 从服务器配置
zone "example.com" IN {
    type slave;
    file "slaves/example.com.zone";
    masters { 10.1.1.1 key transfer-key; };
};

# TSIG 密钥
key "transfer-key" {
    algorithm hmac-sha256;
    secret "your-base64-encoded-secret";
};
```

### 4.2 DNS 监控

```bash
# Prometheus 指标
# BIND stats
rndc stats
cat /var/named/data/named_stats.txt

# CoreDNS 指标
# coredns_dns_requests_total
# coredns_dns_responses_total
# coredns_dns_request_duration_seconds

# DNS 解析测试
dig @10.1.1.1 example.com A +short
dig @10.1.1.1 example.com A +trace
nslookup example.com 10.1.1.1
```

## 5. DNS 安全

### 5.1 DNSSEC 配置

```bash
# 生成密钥
cd /var/named/zones
dnssec-keygen -a ECDSAP256SHA256 -n ZONE example.com
dnssec-keygen -a ECDSAP256SHA256 -n ZONE -f KSK example.com

# 签名区域
dnssec-signzone -A -3 $(head -c 1000 /dev/urandom | sha1sum | cut -b 1-16) \
  -N INCREMENT -o example.com -t example.com.zone
```

### 5.2 DNS-over-TLS/HTTPS

```bash
# CoreDNS DoT 配置
tls://.:853 {
    tls /etc/coredns/cert.pem /etc/coredns/key.pem
    forward . 8.8.8.8
}
```

## 6. 故障排查

```bash
# 检查 DNS 解析
dig @10.1.1.1 example.com A +trace
dig @10.1.1.1 example.com ANY +noall +answer

# 检查反向解析
dig @10.1.1.1 -x 10.1.1.100

# 检查 DNS 服务器连通性
nmap -sU -p 53 10.1.1.1

# 检查区域文件语法
named-checkzone example.com /var/named/zones/example.com.zone
named-checkconf /etc/named.conf

# 查看 DNS 查询日志
tail -f /var/log/named/query.log | grep example.com
```
