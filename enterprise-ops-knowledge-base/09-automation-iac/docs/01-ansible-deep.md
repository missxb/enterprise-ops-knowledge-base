# Ansible 深入

## 一、Ansible 架构概述

### 1.1 设计哲学

Ansible 是一个开源的自动化工具，其核心设计理念包括：

- **无Agent（Agentless）** — 不需要在被管理节点安装任何客户端软件
- **幂等性（Idempotency）** — 多次执行结果一致
- **声明式（Declarative）** — 描述期望状态，而非步骤
- **简单性** — YAML 格式，易于阅读和编写

### 1.2 架构组件

```
┌─────────────────────────────────────────────────────┐
│                  控制节点 (Control Node)               │
│  ┌───────────┐  ┌───────────┐  ┌───────────────┐    │
│  │ Ansible   │  │ Inventory │  │  Playbook/    │    │
│  │ CLI       │  │ (清单)    │  │  Role         │    │
│  └─────┬─────┘  └─────┬─────┘  └───────┬───────┘    │
│        │              │                │            │
│        └──────────────┼────────────────┘            │
│                       │                             │
│                 ┌─────▼─────┐                       │
│                 │ Ansible   │                       │
│                 │ Engine    │                       │
│                 └─────┬─────┘                       │
└───────────────────────┼─────────────────────────────┘
                        │ SSH (默认)
           ┌────────────┼────────────┐
           │            │            │
     ┌─────▼─────┐ ┌───▼─────┐ ┌───▼─────┐
     │ 被管理节点 │ │ 被管理  │ │ 被管理  │
     │ Node A    │ │ 节点 B  │ │ 节点 C  │
     └───────────┘ └─────────┘ └─────────┘
```

**核心组件说明：**

| 组件 | 说明 |
|------|------|
| **控制节点** | 运行 Ansible 的机器，安装 Python 和 Ansible |
| **Inventory** | 定义被管理的主机和主机组 |
| **Module** | 执行具体任务的功能单元（2000+ 内置模块） |
| **Plugin** | 扩展 Ansible 功能（连接、回调、过滤器等） |
| **Playbook** | 用 YAML 编写的自动化剧本 |
| **Galaxy** | 社区共享的 Role 和 Collection 仓库 |

### 1.3 执行流程

1. **解析 Inventory** — 确定目标主机
2. **解析 Playbook** — 确定要执行的任务
3. **生成 Python 脚本** — 将模块转换为 Python 代码
4. **传输到目标** — 通过 SSH 传输到被管理节点
5. **执行并返回** — 在目标节点执行，返回 JSON 结果
6. **清理** — 删除临时文件

## 二、安装与配置

### 2.1 安装方式

```bash
# 方式一：pip 安装（推荐）
pip3 install ansible

# 方式二：系统包管理器
# CentOS/RHEL
sudo yum install -y epel-release
sudo yum install -y ansible

# Ubuntu/Debian
sudo apt-add-repository ppa:ansible/ansible
sudo apt-get update
sudo apt-get install -y ansible

# 方式三：pip 安装指定版本
pip3 install ansible==6.7.0

# 验证安装
ansible --version
ansible-playbook --version
```

### 2.2 配置文件优先级

Ansible 按以下优先级查找配置（从高到低）：

1. `ANSIBLE_CONFIG` 环境变量指定的文件
2. 当前目录下的 `ansible.cfg`
3. 用户主目录下的 `~/.ansible.cfg`
4. 系统级 `/etc/ansible/ansible.cfg`

### 2.3 核心配置项

```ini
# ansible.cfg
[defaults]
inventory = ./inventory/hosts.yml
remote_user = deploy
private_key_file = ~/.ssh/id_rsa
host_key_checking = False
retry_files_enabled = False
timeout = 30
forks = 20
log_path = /var/log/ansible/ansible.log
gathering = smart
fact_caching = jsonfile
fact_caching_connection = /tmp/ansible_facts_cache
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
```

## 三、Inventory 详解

### 3.1 INI 格式

```ini
# inventory/hosts.ini
[webservers]
web01 ansible_host=192.168.1.10 ansible_port=22
web02 ansible_host=192.168.1.11
web03 ansible_host=192.168.1.12

[dbservers]
db01 ansible_host=192.168.1.20
db02 ansible_host=192.168.1.21

[staging:children]
webservers
dbservers

[all:vars]
ansible_user=deploy
ansible_python_interpreter=/usr/bin/python3
```

### 3.2 YAML 格式（推荐）

```yaml
# inventory/hosts.yml
all:
  children:
    webservers:
      hosts:
        web01:
          ansible_host: 192.168.1.10
          ansible_port: 22
          http_port: 80
        web02:
          ansible_host: 192.168.1.11
          http_port: 8080
        web03:
          ansible_host: 192.168.1.12
      vars:
        ansible_user: deploy
        nginx_version: "1.24.0"
    
    dbservers:
      hosts:
        db01:
          ansible_host: 192.168.1.20
          mysql_role: master
        db02:
          ansible_host: 192.168.1.21
          mysql_role: slave
      vars:
        mysql_version: "8.0"
    
    monitoring:
      hosts:
        mon01:
          ansible_host: 192.168.1.30
    
    # 环境分组
    production:
      children:
        webservers:
        dbservers:
    
    staging:
      children:
        staging_webservers:
        staging_dbservers:
  
  vars:
    ansible_python_interpreter: /usr/bin/python3
    ntp_server: ntp.aliyun.com
```

### 3.3 动态 Inventory

```python
#!/usr/bin/env python3
# dynamic_inventory.py — 动态 Inventory 脚本示例

import json
import argparse
import subprocess

def get_hosts_from_api():
    """从 CMDB API 获取主机列表"""
    # 实际环境中从 API 获取
    return {
        "webservers": ["192.168.1.10", "192.168.1.11"],
        "dbservers": ["192.168.1.20"]
    }

def build_inventory():
    hosts = get_hosts_from_api()
    inventory = {
        "_meta": {
            "hostvars": {}
        }
    }
    
    for group, ips in hosts.items():
        inventory[group] = {
            "hosts": ips,
            "vars": {
                "ansible_user": "deploy"
            }
        }
    
    return inventory

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--host", type=str)
    args = parser.parse_args()
    
    if args.list:
        print(json.dumps(build_inventory(), indent=2))
    elif args.host:
        print(json.dumps({}))
```

## 四、模块深入

### 4.1 常用模块分类

**文件管理类：**

```yaml
# copy — 复制文件
- name: 复制配置文件
  copy:
    src: files/nginx.conf
    dest: /etc/nginx/nginx.conf
    owner: root
    group: root
    mode: '0644'
    backup: yes

# template — 模板渲染
- name: 渲染配置模板
  template:
    src: templates/nginx.conf.j2
    dest: /etc/nginx/nginx.conf
    validate: "nginx -t -c %s"
    notify: restart nginx

# file — 文件/目录操作
- name: 创建目录
  file:
    path: /data/app
    state: directory
    owner: app
    group: app
    mode: '0755'

# lineinfile — 行编辑
- name: 修改 SSH 配置
  lineinfile:
    path: /etc/ssh/sshd_config
    regexp: '^#?PermitRootLogin'
    line: 'PermitRootLogin no'
    validate: '/usr/sbin/sshd -t -f %s'
  notify: restart sshd
```

**包管理类：**

```yaml
# yum/apt — 包安装
- name: 安装软件包
  yum:
    name:
      - nginx
      - python3
      - vim
    state: present
    update_cache: yes

# pip — Python 包
- name: 安装 Python 包
  pip:
    name:
      - requests
      - flask
    virtualenv: /opt/venv
    virtualenv_command: python3 -m venv
```

**系统管理类：**

```yaml
# service — 服务管理
- name: 启动并启用服务
  service:
    name: nginx
    state: started
    enabled: yes

# user — 用户管理
- name: 创建应用用户
  user:
    name: app
    shell: /bin/bash
    home: /home/app
    create_home: yes
    groups: docker
    append: yes

# cron — 定时任务
- name: 添加定时备份任务
  cron:
    name: "daily backup"
    minute: "0"
    hour: "2"
    job: "/opt/scripts/backup.sh >> /var/log/backup.log 2>&1"
    user: root
```

**网络类：**

```yaml
# uri — HTTP 请求
- name: 健康检查
  uri:
    url: "http://{{ ansible_host }}:{{ http_port }}/health"
    method: GET
    status_code: 200
    timeout: 10
  register: health_check
  retries: 3
  delay: 5
  until: health_check.status == 200

# wait_for — 等待条件
- name: 等待端口监听
  wait_for:
    host: "{{ ansible_host }}"
    port: "{{ http_port }}"
    state: started
    timeout: 60
```

### 4.2 自定义模块

```python
#!/usr/bin/python3
# library/check_port.py — 自定义端口检查模块

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
        ),
        supports_check_mode=True
    )

    host = module.params['host']
    port = module.params['port']
    timeout = module.params['timeout']

    is_open = check_port(host, port, timeout)

    module.exit_json(
        changed=False,
        port_open=is_open,
        host=host,
        port=port
    )

if __name__ == '__main__':
    main()
```

## 五、变量系统

### 5.1 变量优先级（从低到高）

1. 角色默认变量 (`roles/x/defaults/main.yml`)
2. Inventory 文件变量
3. Inventory `group_vars` 变量
4. Inventory `host_vars` 变量
5. Playbook `group_vars` 变量
6. Playbook `host_vars` 变量
7. `set_fact` / 注册变量
8. 额外变量 (`-e` 或 `--extra-vars`)

### 5.2 变量文件组织

```
project/
├── inventory/
│   ├── hosts.yml
│   ├── group_vars/
│   │   ├── all.yml          # 所有主机共享变量
│   │   ├── webservers.yml   # web 服务器组变量
│   │   └── dbservers.yml    # 数据库服务器组变量
│   └── host_vars/
│       ├── web01.yml        # web01 主机特定变量
│       └── db01.yml         # db01 主机特定变量
└── playbooks/
    ├── group_vars/
    │   └── all.yml          # Playbook 级变量
    └── host_vars/
        └── web01.yml
```

### 5.3 Facts 与 Magic Variables

```yaml
# 使用 Facts
- name: 根据操作系统选择包管理器
  yum:
    name: nginx
    state: present
  when: ansible_os_family == "RedHat"

- name: 根据内存大小调整配置
  template:
    src: my.cnf.j2
    dest: /etc/my.cnf
  vars:
    buffer_pool_size: "{{ (ansible_memtotal_mb * 0.7) | int }}M"

# 常用 Magic Variables
# inventory_hostname — 当前主机名
# inventory_hostname_short — 短主机名
# groups — 所有组和主机
# group_names — 当前主机所属的组
# hostvars — 所有主机的变量
# ansible_play_hosts — 当前 play 的所有主机

# 示例：获取同组其他主机
- name: 配置集群节点列表
  template:
    src: cluster.conf.j2
    dest: /etc/app/cluster.conf
  vars:
    cluster_nodes: "{{ groups['webservers'] | map('extract', hostvars, 'ansible_host') | list }}"
```

### 5.4 变量加密（Ansible Vault）

```bash
# 创建加密文件
ansible-vault create secrets.yml

# 编辑加密文件
ansible-vault edit secrets.yml

# 加密已有文件
ansible-vault encrypt vars/secrets.yml

# 解密
ansible-vault decrypt vars/secrets.yml

# 使用加密变量运行
ansible-playbook site.yml --ask-vault-pass
ansible-playbook site.yml --vault-password-file ~/.vault_pass

# 加密单个变量（内联加密）
ansible-vault encrypt_string 'my_secret_password' --name 'db_password'
```

## 六、Jinja2 模板引擎

### 6.1 基础语法

```jinja2
{# 注释 #}

{# 变量输出 #}
server_name {{ domain_name }};
listen {{ http_port | default(80) }};

{# 条件判断 #}
{% if enable_ssl %}
listen 443 ssl;
ssl_certificate {{ ssl_cert_path }};
{% endif %}

{# 循环 #}
{% for server in upstream_servers %}
server {{ server.host }}:{{ server.port }} weight={{ server.weight | default(1) }};
{% endfor %}
```

### 6.2 常用过滤器

```yaml
# 数据类型转换
{{ port | int }}
{{ debug_mode | bool }}
{{ server_list | list }}

# 字符串操作
{{ hostname | upper }}
{{ hostname | lower }}
{{ hostname | capitalize }}
{{ path | basename }}           # /etc/nginx/nginx.conf → nginx.conf
{{ path | dirname }}            # /etc/nginx/nginx.conf → /etc/nginx
{{ "hello" | regex_replace('h', 'H') }}

# 列表操作
{{ servers | join(',') }}       # 列表转逗号分隔字符串
{{ servers | first }}           # 第一个元素
{{ servers | last }}            # 最后一个元素
{{ servers | length }}          # 列表长度
{{ servers | unique }}          # 去重
{{ servers | sort }}            # 排序
{{ servers | map('upper') | list }}  # 映射

# 字典操作
{{ config | combine(override) }}  # 合并字典
{{ config | dict2items }}        # 字典转列表

# 默认值
{{ variable | default('fallback') }}
{{ variable | default(omit) }}   # 跳过该参数

# 哈希与加密
{{ password | password_hash('sha512') }}
{{ content | hash('sha256') }}

# 网络
{{ '192.168.1.0/24' | ipaddr('network') }}
{{ '192.168.1.1' | ipaddr('bool') }}

# JSON/YAML
{{ config | to_json }}
{{ config | to_yaml }}
{{ json_string | from_json }}
```

### 6.3 高级模板技巧

```jinja2
{# 条件块与默认值 #}
{% set worker_processes = ansible_processor_vcpus | default(4) %}
worker_processes {{ worker_processes }};

{# 复杂循环 #}
{% for interface in ansible_interfaces %}
{% set iface = hostvars[inventory_hostname]['ansible_' + interface] %}
{% if iface.ipv4 is defined %}
# {{ interface }}: {{ iface.ipv4.address }}
{% endif %}
{% endfor %}

{# 宏定义（类似函数） #}
{% macro server_block(domain, port, root_dir) %}
server {
    listen {{ port }};
    server_name {{ domain }};
    root {{ root_dir }};
    
    location / {
        try_files $uri $uri/ /index.html;
    }
}
{% endmacro %}

{{ server_block('example.com', 80, '/var/www/example') }}
{{ server_block('api.example.com', 8080, '/var/www/api') }}

{# 循环控制 #}
{% for item in list %}
{% if loop.first %}
# First item
{% endif %}
{{ item }}{% if not loop.last %},{% endif %}
{% endfor %}

{# 错误处理 #}
{% if my_var is defined and my_var %}
  value: {{ my_var }}
{% else %}
  # 使用默认配置
{% endif %}
```

## 七、最佳实践

1. **使用 YAML 格式 Inventory** — 更易读、更灵活
2. **合理组织变量** — 按环境、角色分层管理
3. **使用 Vault 加密敏感数据** — 永远不要明文存储密码
4. **启用 Fact 缓存** — 减少重复收集时间
5. **使用 Pipelining** — 提升 SSH 执行效率
6. **限制 forks 数量** — 根据控制节点性能调整
7. **使用 --check 模式** — 预览变更
8. **编写幂等任务** — 确保重复执行安全
