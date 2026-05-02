# Ansible自动化运维完整手册

## 目录

- [1. 项目背景与架构设计](#1-项目背景与架构设计)
- [2. Inventory管理](#2-inventory管理)
- [3. Role编写最佳实践](#3-role编写最佳实践)
- [4. 常用Playbook模板](#4-常用playbook模板)
- [5. Ansible Vault密钥管理](#5-ansible-vault密钥管理)
- [6. 自定义Module和Plugin](#6-自定义module和plugin)
- [7. AWX/Tower部署与使用](#7-awxtower部署与使用)
- [8. 批量服务器管理实战](#8-批量服务器管理实战)
- [9. 与CI/CD集成](#9-与cicd集成)
- [10. 最佳实践与故障排查](#10-最佳实践与故障排查)

---

## 1. 项目背景与架构设计

### 1.1 Ansible架构

```
┌─────────────────────────────────────────────┐
│              Control Node                    │
│  ┌──────────┐ ┌──────────┐ ┌─────────────┐ │
│  │ Inventory│ │Playbooks │ │ Roles       │ │
│  │          │ │          │ │ Collections │ │
│  └──────────┘ └──────────┘ └─────────────┘ │
│                    │                         │
│              ┌─────┴─────┐                  │
│              │  Ansible   │                  │
│              │  Engine    │                  │
│              └─────┬─────┘                  │
│                    │ SSH (Agentless)         │
└────────────────────┼────────────────────────┘
         ┌───────────┼───────────┐
         ▼           ▼           ▼
    ┌────────┐  ┌────────┐  ┌────────┐
    │Node 01 │  │Node 02 │  │Node 03 │
    │(Web)   │  │(DB)    │  │(Cache) │
    └────────┘  └────────┘  └────────┘
```

### 1.2 安装与配置

```bash
# 安装Ansible
pip install ansible==8.7.0
# 或
yum install -y epel-release && yum install -y ansible

# 配置文件 /etc/ansible/ansible.cfg
cat > /etc/ansible/ansible.cfg << 'EOF'
[defaults]
inventory = /etc/ansible/inventory
remote_user = ops
private_key_file = ~/.ssh/id_rsa
host_key_checking = False
timeout = 30
forks = 50
log_path = /var/log/ansible.log
retry_files_enabled = False
gathering = smart
fact_caching = jsonfile
fact_caching_connection = /tmp/ansible_facts
fact_caching_timeout = 86400

[privilege_escalation]
become = True
become_method = sudo
become_user = root
become_ask_pass = False

[ssh_connection]
ssh_args = -o ControlMaster=auto -o ControlPersist=60s -o StrictHostKeyChecking=no
pipelining = True
control_path_dir = /tmp/.ansible/cp
EOF
```

---

## 2. Inventory管理

### 2.1 静态Inventory

```ini
# /etc/ansible/inventory/hosts.ini

# ===== Web服务器 =====
[web]
web-01 ansible_host=10.10.1.11
web-02 ansible_host=10.10.1.12
web-03 ansible_host=10.10.1.13

# ===== 数据库服务器 =====
[db]
db-master ansible_host=10.10.2.11 mysql_role=master
db-slave-01 ansible_host=10.10.2.12 mysql_role=slave
db-slave-02 ansible_host=10.10.2.13 mysql_role=slave

# ===== 缓存服务器 =====
[redis]
redis-01 ansible_host=10.10.3.11 redis_role=master
redis-02 ansible_host=10.10.3.12 redis_role=slave
redis-03 ansible_host=10.10.3.13 redis_role=slave

# ===== 分组 =====
[production:children]
web
db
redis

# ===== 变量 =====
[all:vars]
ansible_user=ops
ansible_ssh_private_key_file=~/.ssh/id_rsa
ansible_python_interpreter=/usr/bin/python3
ntp_server=ntp.aliyun.com
dns_servers=223.5.5.5,114.114.114.114

[web:vars]
http_port=80
https_port=443
nginx_worker_processes=4

[db:vars]
mysql_port=3306
mysql_datadir=/data/mysql
innodb_buffer_pool_size=8G

[production:vars]
env=production
monitoring_server=10.10.1.100
log_server=10.10.1.101
```

### 2.2 动态Inventory（阿里云ECS）

```python
#!/usr/bin/env python3
# aliyun_ec2.py - 阿里云ECS动态Inventory

import json
import sys
from alibabacloud_ecs20140526.client import Client
from alibabacloud_ecs20140526 import models
from alibabacloud_tea_openapi import models as open_api_models

def create_client():
    config = open_api_models.Config()
    config.access_key_id = 'YOUR_ACCESS_KEY'
    config.access_key_secret = 'YOUR_SECRET'
    config.region_id = 'cn-beijing'
    return Client(config)

def get_instances(client):
    request = models.DescribeInstancesRequest()
    request.region_id = 'cn-beijing'
    request.page_size = 100
    response = client.describe_instances(request)
    return response.body.instances.instance

def build_inventory():
    client = create_client()
    instances = get_instances(client)
    
    inventory = {
        '_meta': {'hostvars': {}},
        'all': {'children': []}
    }
    
    groups = {}
    
    for inst in instances:
        if inst.status != 'Running':
            continue
        
        hostname = inst.instance_name
        ip = inst.vpc_attributes.private_ip_address.ip_address[0] if inst.vpc_attributes else inst.public_ip_address.ip_address[0] if inst.public_ip_address else None
        
        if not ip:
            continue
        
        # 按标签分组
        tags = {t.tag_key: t.tag_value for t in (inst.tags.tag if inst.tags else [])}
        role = tags.get('role', 'ungrouped')
        env = tags.get('environment', 'default')
        
        group_name = f"{env}_{role}"
        if group_name not in groups:
            groups[group_name] = {'hosts': [], 'vars': {}}
        groups[group_name]['hosts'].append(hostname)
        
        inventory['_meta']['hostvars'][hostname] = {
            'ansible_host': ip,
            'instance_id': inst.instance_id,
            'instance_type': inst.instance_type,
            'tags': tags
        }
    
    for name, group in groups.items():
        inventory[name] = group
        if name not in inventory['all']['children']:
            inventory['all']['children'].append(name)
    
    return inventory

if __name__ == '__main__':
    if len(sys.argv) == 2 and sys.argv[1] == '--list':
        print(json.dumps(build_inventory(), indent=2))
    elif len(sys.argv) == 3 and sys.argv[1] == '--host':
        print(json.dumps({}))
```

---

## 3. Role编写最佳实践

### 3.1 Role标准目录结构

```
roles/
└── nginx/
    ├── defaults/
    │   └── main.yml          # 默认变量（优先级最低）
    ├── vars/
    │   └── main.yml          # 变量（优先级高）
    ├── tasks/
    │   └── main.yml          # 主任务
    ├── handlers/
    │   └── main.yml          # 处理器
    ├── templates/
    │   └── nginx.conf.j2     # Jinja2模板
    ├── files/
    │   └── ssl.crt           # 静态文件
    ├── meta/
    │   └── main.yml          # 依赖关系
    └── README.md
```

### 3.2 Nginx Role示例

```yaml
# roles/nginx/defaults/main.yml
nginx_worker_processes: "auto"
nginx_worker_connections: 65535
nginx_keepalive_timeout: 65
nginx_client_max_body_size: "50m"
nginx_ssl_protocols: "TLSv1.2 TLSv1.3"
nginx_log_format: 'combined'

# roles/nginx/tasks/main.yml
---
- name: Install Nginx
  package:
    name: nginx
    state: present

- name: Ensure Nginx config directory
  file:
    path: "{{ item }}"
    state: directory
    owner: root
    group: root
    mode: '0755'
  loop:
    - /etc/nginx/conf.d
    - /etc/nginx/ssl
    - /var/log/nginx

- name: Deploy Nginx configuration
  template:
    src: nginx.conf.j2
    dest: /etc/nginx/nginx.conf
    owner: root
    group: root
    mode: '0644'
    validate: nginx -t -c %s
  notify: Reload Nginx

- name: Deploy site configurations
  template:
    src: "{{ item }}.conf.j2"
    dest: "/etc/nginx/conf.d/{{ item }}.conf"
    owner: root
    group: root
    mode: '0644'
  loop: "{{ nginx_sites | default([]) }}"
  notify: Reload Nginx

- name: Ensure Nginx is started and enabled
  service:
    name: nginx
    state: started
    enabled: yes

# roles/nginx/handlers/main.yml
---
- name: Reload Nginx
  service:
    name: nginx
    state: reloaded

- name: Restart Nginx
  service:
    name: nginx
    state: restarted

# roles/nginx/templates/nginx.conf.j2
user nginx;
worker_processes {{ nginx_worker_processes }};
error_log /var/log/nginx/error.log warn;
pid /run/nginx.pid;

events {
    worker_connections {{ nginx_worker_connections }};
    use epoll;
    multi_accept on;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for" '
                    '$request_time $upstream_response_time';

    access_log /var/log/nginx/access.log main;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout {{ nginx_keepalive_timeout }};
    client_max_body_size {{ nginx_client_max_body_size }};

    gzip on;
    gzip_types text/plain text/css application/json application/javascript;
    gzip_min_length 1000;

    include /etc/nginx/conf.d/*.conf;
}
```

### 3.3 MySQL Role示例

```yaml
# roles/mysql/defaults/main.yml
mysql_version: "8.0"
mysql_port: 3306
mysql_datadir: /data/mysql
mysql_root_password: "{{ vault_mysql_root_password }}"
mysql_innodb_buffer_pool_size: "4G"
mysql_max_connections: 500
mysql_character_set: "utf8mb4"
mysql_collation: "utf8mb4_unicode_ci"

# roles/mysql/tasks/main.yml
---
- name: Install MySQL
  package:
    name: "mysql-server"
    state: present

- name: Create MySQL data directory
  file:
    path: "{{ mysql_datadir }}"
    state: directory
    owner: mysql
    group: mysql
    mode: '0750'

- name: Deploy MySQL configuration
  template:
    src: my.cnf.j2
    dest: /etc/my.cnf
    owner: root
    group: root
    mode: '0644'
  notify: Restart MySQL

- name: Ensure MySQL is started
  service:
    name: mysqld
    state: started
    enabled: yes

- name: Set root password
  mysql_user:
    name: root
    password: "{{ mysql_root_password }}"
    host: localhost
    state: present
  ignore_errors: yes
```

---

## 4. 常用Playbook模板

### 4.1 系统初始化Playbook

```yaml
# playbooks/system-init.yml
---
- name: System Initialization
  hosts: all
  become: yes
  vars:
    timezone: "Asia/Shanghai"
    ntp_servers:
      - ntp.aliyun.com
      - ntp1.aliyun.com
    sysctl_params:
      net.core.somaxconn: 65535
      net.ipv4.tcp_max_syn_backlog: 65535
      net.ipv4.tcp_tw_reuse: 1
      net.ipv4.tcp_fin_timeout: 15
      net.ipv4.ip_local_port_range: "1024 65535"
      fs.file-max: 655360
      vm.swappiness: 10

  tasks:
    - name: Set timezone
      timezone:
        name: "{{ timezone }}"

    - name: Install base packages
      package:
        name:
          - vim
          - wget
          - curl
          - net-tools
          - htop
          - iotop
          - sysstat
          - lsof
          - tcpdump
          - strace
          - chrony
        state: present

    - name: Configure NTP
      template:
        src: chrony.conf.j2
        dest: /etc/chrony.conf
      notify: Restart chronyd

    - name: Apply sysctl parameters
      sysctl:
        name: "{{ item.key }}"
        value: "{{ item.value }}"
        sysctl_file: /etc/sysctl.d/99-custom.conf
        reload: yes
      loop: "{{ sysctl_params | dict2items }}"

    - name: Set ulimits
      pam_limits:
        domain: '*'
        limit_type: "{{ item.type }}"
        limit_item: "{{ item.item }}"
        value: "{{ item.value }}"
      loop:
        - { type: 'soft', item: 'nofile', value: '655360' }
        - { type: 'hard', item: 'nofile', value: '655360' }
        - { type: 'soft', item: 'nproc', value: '655360' }
        - { type: 'hard', item: 'nproc', value: '655360' }

    - name: Disable SELinux
      selinux:
        state: disabled
      when: ansible_os_family == "RedHat"

    - name: Disable swap
      command: swapoff -a
      changed_when: false

    - name: Remove swap from fstab
      lineinfile:
        path: /etc/fstab
        regexp: '.*swap.*'
        state: absent

  handlers:
    - name: Restart chronyd
      service:
        name: chronyd
        state: restarted
```

### 4.2 批量软件部署Playbook

```yaml
# playbooks/deploy-app.yml
---
- name: Deploy Application
  hosts: web
  become: yes
  vars:
    app_name: myapp
    app_version: "1.0.0"
    app_port: 8080
    app_user: myapp
    app_dir: /opt/{{ app_name }}
    jar_url: "https://nexus.example.com/releases/{{ app_name }}/{{ app_version }}/{{ app_name }}-{{ app_version }}.jar"

  tasks:
    - name: Create application user
      user:
        name: "{{ app_user }}"
        system: yes
        shell: /sbin/nologin

    - name: Create application directory
      file:
        path: "{{ app_dir }}"
        state: directory
        owner: "{{ app_user }}"
        group: "{{ app_user }}"
        mode: '0755'

    - name: Download application artifact
      get_url:
        url: "{{ jar_url }}"
        dest: "{{ app_dir }}/{{ app_name }}.jar"
        owner: "{{ app_user }}"
        mode: '0644'
      notify: Restart Application

    - name: Deploy application configuration
      template:
        src: "app.conf.j2"
        dest: "{{ app_dir }}/application.properties"
        owner: "{{ app_user }}"
        mode: '0644'
      notify: Restart Application

    - name: Deploy systemd service
      template:
        src: "app.service.j2"
        dest: "/etc/systemd/system/{{ app_name }}.service"
      notify:
        - Reload systemd
        - Restart Application

    - name: Ensure application is started
      service:
        name: "{{ app_name }}"
        state: started
        enabled: yes

  handlers:
    - name: Reload systemd
      systemd:
        daemon_reload: yes

    - name: Restart Application
      service:
        name: "{{ app_name }}"
        state: restarted
```

### 4.3 滚动更新Playbook

```yaml
# playbooks/rolling-update.yml
---
- name: Rolling Update Application
  hosts: web
  serial: 1              # 每次更新1台
  max_fail_percentage: 0  # 0容忍失败
  become: yes

  pre_tasks:
    - name: Remove from load balancer
      uri:
        url: "http://{{ lb_api }}/api/servers/{{ inventory_hostname }}/disable"
        method: POST
      delegate_to: localhost

    - name: Wait for connections to drain
      wait_for:
        timeout: 30

    - name: Check current health
      uri:
        url: "http://{{ ansible_host }}:{{ app_port }}/health"
        status_code: 200
      register: health_check
      retries: 3
      delay: 5

  roles:
    - role: deploy-app
      vars:
        app_version: "{{ new_version }}"

  post_tasks:
    - name: Wait for application to be ready
      uri:
        url: "http://{{ ansible_host }}:{{ app_port }}/health"
        status_code: 200
      register: health
      until: health.status == 200
      retries: 30
      delay: 10

    - name: Add back to load balancer
      uri:
        url: "http://{{ lb_api }}/api/servers/{{ inventory_hostname }}/enable"
        method: POST
      delegate_to: localhost

    - name: Verify traffic
      uri:
        url: "http://{{ ansible_host }}:{{ app_port }}/"
        status_code: 200
      delegate_to: localhost
```

---

## 5. Ansible Vault密钥管理

### 5.1 Vault操作

```bash
# 创建加密文件
ansible-vault create secrets.yml

# 加密已有文件
ansible-vault encrypt vars/secrets.yml

# 编辑加密文件
ansible-vault edit secrets.yml

# 解密文件
ansible-vault decrypt secrets.yml

# 查看加密文件
ansible-vault view secrets.yml

# 使用加密变量文件运行playbook
ansible-playbook site.yml --ask-vault-pass
ansible-playbook site.yml --vault-password-file ~/.vault_pass

# 加密单个变量
ansible-vault encrypt_string 'my_secret_password' --name 'db_password'
```

### 5.2 Vault最佳实践

```yaml
# group_vars/production/vault.yml (加密)
vault_mysql_root_password: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  6638643965323633646262656665306333...

# group_vars/production/vars.yml (明文，引用加密变量)
mysql_root_password: "{{ vault_mysql_root_password }}"

# 使用规范:
# 1. vault文件只包含敏感数据
# 2. 使用vault_前缀命名加密变量
# 3. vault密码文件权限设为600
# 4. 不要将vault密码提交到Git
# 5. 使用CI/CD的Secret管理vault密码
```

---

## 6. 自定义Module和Plugin

### 6.1 自定义Module示例

```python
#!/usr/bin/python3
# library/check_port.py - 自定义端口检查模块

from ansible.module_utils.basic import AnsibleModule
import socket

def check_port(host, port, timeout=5):
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(timeout)
        result = sock.connect_ex((host, int(port)))
        sock.close()
        return result == 0
    except Exception:
        return False

def main():
    module = AnsibleModule(
        argument_spec=dict(
            host=dict(type='str', required=True),
            port=dict(type='int', required=True),
            timeout=dict(type='int', default=5),
            state=dict(type='str', default='started', choices=['started', 'stopped']),
        ),
        supports_check_mode=True
    )

    host = module.params['host']
    port = module.params['port']
    timeout = module.params['timeout']
    state = module.params['state']

    is_open = check_port(host, port, timeout)

    if state == 'started' and not is_open:
        module.fail_json(msg=f"Port {host}:{port} is not open")
    elif state == 'stopped' and is_open:
        module.fail_json(msg=f"Port {host}:{port} is open")

    module.exit_json(
        changed=False,
        host=host,
        port=port,
        is_open=is_open
    )

if __name__ == '__main__':
    main()
```

```yaml
# 使用自定义模块
- name: Check MySQL port
  check_port:
    host: "{{ ansible_host }}"
    port: 3306
    state: started
```

---

## 7. AWX/Tower部署与使用

### 7.1 AWX部署

```yaml
# docker-compose-awx.yml
version: '3.8'
services:
  awx-web:
    image: ansible/awx:latest
    container_name: awx-web
    ports:
      - "8052:8052"
    environment:
      SECRET_KEY: your-secret-key
      DATABASE_NAME: awx
      DATABASE_USER: awx
      DATABASE_PASSWORD: awx_password
      DATABASE_HOST: awx-postgres
      DATABASE_PORT: 5432
      MEMCACHED_HOST: awx-memcached
      REDIS_HOST: awx-redis
    depends_on:
      - awx-postgres
      - awx-redis
      - awx-memcached

  awx-postgres:
    image: postgres:15-alpine
    environment:
      POSTGRES_DB: awx
      POSTGRES_USER: awx
      POSTGRES_PASSWORD: awx_password
    volumes:
      - awx-pg-data:/var/lib/postgresql/data

  awx-redis:
    image: redis:7-alpine

  awx-memcached:
    image: memcached:alpine

volumes:
  awx-pg-data:
```

### 7.2 AWX使用流程

```
1. 创建凭据 (Credentials)
   - SSH密钥凭据
   - Vault密码凭据
   - 云服务API凭据

2. 创建项目 (Projects)
   - 关联Git仓库
   - 同步Playbook

3. 创建Inventory
   - 手动或动态Inventory
   - 关联凭据

4. 创建模板 (Templates)
   - 关联Playbook
   - 关联Inventory和凭据
   - 配置变量

5. 执行任务
   - 手动执行或定时执行
   - 查看执行日志
```

---

## 8. 批量服务器管理实战

### 8.1 批量操作命令

```bash
# 批量执行命令
ansible web -m shell -a "df -h" --one-line
ansible all -m shell -a "uptime"

# 批量分发文件
ansible web -m copy -a "src=./app.conf dest=/opt/app/app.conf mode=0644"

# 批量安装软件
ansible web -m yum -a "name=nginx state=present"

# 批量重启服务
ansible web -m service -a "name=nginx state=restarted"

# 批量收集系统信息
ansible all -m setup -a "filter=ansible_distribution*"

# 并行执行（50并发）
ansible all -m ping -f 50

# 按条件执行
ansible web -m shell -a "free -m" --limit "web-01:web-03"

# 查看主机信息
ansible all --list-hosts
ansible web --list-hosts
```

### 8.2 Ad-hoc常用场景

```bash
# 1. 批量检查磁盘空间
ansible all -m shell -a "df -h | grep -E '/$|/data'" -f 30

# 2. 批量清理日志
ansible all -m shell -a "find /var/log -name '*.gz' -mtime +30 -delete" -f 20

# 3. 批量同步时间
ansible all -m shell -a "chronyc makestep" -f 50

# 4. 批量检查服务状态
ansible all -m shell -a "systemctl is-active sshd docker kubelet" -f 30

# 5. 批量更新配置并重启
ansible web -m template -a "src=nginx.conf.j2 dest=/etc/nginx/nginx.conf" --check  # dry-run
ansible web -m template -a "src=nginx.conf.j2 dest=/etc/nginx/nginx.conf"
ansible web -m service -a "name=nginx state=reloaded"

# 6. 批量收集系统信息生成报告
ansible all -m setup -a "filter=ansible_*" --tree /tmp/facts/
```

---

## 9. 与CI/CD集成

### 9.1 GitLab CI集成

```yaml
# .gitlab-ci.yml
deploy:
  stage: deploy
  image: cytopia/ansible:latest
  before_script:
    - mkdir -p ~/.ssh
    - echo "$SSH_PRIVATE_KEY" > ~/.ssh/id_rsa
    - chmod 600 ~/.ssh/id_rsa
    - echo "$VAULT_PASSWORD" > ~/.vault_pass
  script:
    - ansible-playbook -i inventory/production playbooks/deploy.yml
        --vault-password-file ~/.vault_pass
        --limit "$DEPLOY_TARGET"
        -e "app_version=$CI_COMMIT_TAG"
  environment:
    name: production
  only:
    - tags
```

### 9.2 Jenkins Pipeline集成

```groovy
// Jenkinsfile
pipeline {
    agent { label 'ansible' }
    
    environment {
        ANSIBLE_VAULT_PASSWORD = credentials('ansible-vault-pass')
        SSH_PRIVATE_KEY = credentials('ansible-ssh-key')
    }

    stages {
        stage('Deploy') {
            steps {
                sh '''
                    mkdir -p ~/.ssh
                    echo "$SSH_PRIVATE_KEY" > ~/.ssh/id_rsa
                    chmod 600 ~/.ssh/id_rsa
                    echo "$ANSIBLE_VAULT_PASSWORD" > ~/.vault_pass
                    
                    ansible-playbook -i inventory/production \
                        playbooks/deploy.yml \
                        --vault-password-file ~/.vault_pass \
                        -e "app_version=${TAG}"
                '''
            }
        }
    }
    
    post {
        always {
            sh 'rm -f ~/.ssh/id_rsa ~/.vault_pass'
        }
    }
}
```

---

## 10. 最佳实践与故障排查

### 10.1 最佳实践

1. **Role化** - 所有可复用逻辑封装为Role
2. **变量分层** - defaults < vars < inventory < extra-vars
3. **Vault管理** - 敏感数据必须用Vault加密
4. **幂等性** - Playbook必须支持重复执行
5. **测试先行** - 使用`--check`和`--diff`验证
6. **版本控制** - 所有Playbook和配置纳入Git
7. **标签管理** - 使用tags支持部分执行
8. **错误处理** - 使用block/rescue/always
9. **日志记录** - 配置log_path记录执行日志
10. **权限最小化** - 只在需要时使用become

### 10.2 常见问题

| 问题 | 原因 | 解决方案 |
|------|------|---------|
| SSH连接失败 | 密钥/网络问题 | 检查SSH配置和网络 |
| 权限不足 | become配置错误 | 检查sudoers配置 |
| 变量未定义 | 变量优先级问题 | 使用`-e`覆盖或检查defaults |
| 任务超时 | 网络慢或任务耗时 | 增加timeout参数 |
| 幂等性失败 | 模块使用不当 | 使用state参数而非command |
| Vault解密失败 | 密码错误 | 检查vault密码文件 |
| Jinja2模板错误 | 语法错误 | 检查模板语法 |

### 10.3 性能优化

```ini
# ansible.cfg 性能优化配置
[defaults]
forks = 50                    # 并发数
gathering = smart             # 智能收集facts
fact_caching = jsonfile       # 缓存facts
fact_caching_connection = /tmp/ansible_facts
fact_caching_timeout = 86400

[ssh_connection]
pipelining = True             # 管道化减少SSH连接
ssh_args = -o ControlMaster=auto -o ControlPersist=60s
control_path_dir = /tmp/.ansible/cp
```

---

> 📅 最后更新: 2026-05-02
