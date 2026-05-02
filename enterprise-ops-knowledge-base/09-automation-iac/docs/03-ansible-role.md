# Ansible Role 开发

## 一、Role 目录结构

### 1.1 标准目录结构

```
roles/
└── nginx/
    ├── defaults/
    │   └── main.yml          # 默认变量（优先级最低）
    ├── vars/
    │   └── main.yml          # 角色变量（优先级高）
    ├── tasks/
    │   └── main.yml          # 主任务
    ├── handlers/
    │   └── main.yml          # Handler 定义
    ├── templates/
    │   ├── nginx.conf.j2     # Jinja2 模板
    │   └── vhost.conf.j2
    ├── files/
    │   ├── ssl.crt           # 静态文件
    │   └── ssl.key
    ├── meta/
    │   └── main.yml          # 角色元数据
    ├── tests/
    │   ├── inventory          # 测试清单
    │   └── test.yml          # 测试 Playbook
    ├── molecule/
    │   └── default/
    │       ├── molecule.yml   # Molecule 配置
    │       ├── converge.yml   # 汇聚 Playbook
    │       └── verify.yml     # 验证 Playbook
    └── README.md             # 角色文档
```

### 1.2 各目录详细说明

**defaults/main.yml** — 默认变量

```yaml
---
# Nginx 默认配置
nginx_user: nginx
nginx_worker_processes: "{{ ansible_processor_vcpus }}"
nginx_worker_connections: 1024
nginx_keepalive_timeout: 65
nginx_client_max_body_size: "50m"
nginx_gzip_enabled: true
nginx_ssl_protocols:
  - TLSv1.2
  - TLSv1.3
nginx_server_tokens: "off"

# 虚拟主机列表
nginx_vhosts: []
# 示例：
# nginx_vhosts:
#   - server_name: example.com
#     listen: 80
#     root: /var/www/example
#     locations:
#       - path: /
#         proxy_pass: http://127.0.0.1:8080
```

**vars/main.yml** — 角色内部变量

```yaml
---
# 内部变量，不应被外部覆盖
nginx_package_name: "nginx"
nginx_config_path: "/etc/nginx"
nginx_log_path: "/var/log/nginx"
nginx_pid_file: "/run/nginx.pid"

_nginx_required_packages:
  - nginx
  - openssl
  - openssl-devel
```

**meta/main.yml** — 角色元数据

```yaml
---
galaxy_info:
  author: ops-team
  description: Nginx 安装和配置角色
  company: Example Corp
  license: MIT
  min_ansible_version: "2.12"
  platforms:
    - name: EL
      versions:
        - 7
        - 8
        - 9
    - name: Ubuntu
      versions:
        - focal
        - jammy
  galaxy_tags:
    - web
    - nginx
    - http
    - reverse-proxy

dependencies:
  - role: common
  - role: ssl-cert
    vars:
      cert_domain: "{{ nginx_domain }}"
    when: nginx_ssl_enabled | default(false)
```

## 二、Role 开发实践

### 2.1 Nginx Role 完整示例

```yaml
# roles/nginx/tasks/main.yml
---
- name: 安装前置依赖
  package:
    name: "{{ _nginx_required_packages }}"
    state: present

- name: 添加 Nginx 官方仓库
  yum_repository:
    name: nginx-stable
    description: Nginx Stable Repository
    baseurl: "http://nginx.org/packages/centos/$releasever/$basearch/"
    gpgcheck: yes
    gpgkey: "https://nginx.org/keys/nginx_signing.key"
    enabled: yes
  when: ansible_os_family == "RedHat"

- name: 安装 Nginx
  package:
    name: "{{ nginx_package_name }}"
    state: present

- name: 创建必要目录
  file:
    path: "{{ item }}"
    state: directory
    owner: "{{ nginx_user }}"
    group: "{{ nginx_user }}"
    mode: '0755'
  loop:
    - "{{ nginx_config_path }}/conf.d"
    - "{{ nginx_config_path }}/ssl"
    - "{{ nginx_log_path }}"
    - /var/www

- name: 部署主配置文件
  template:
    src: nginx.conf.j2
    dest: "{{ nginx_config_path }}/nginx.conf"
    owner: root
    group: root
    mode: '0644'
    validate: "nginx -t -c %s"
  notify: reload nginx

- name: 部署虚拟主机配置
  template:
    src: vhost.conf.j2
    dest: "{{ nginx_config_path }}/conf.d/{{ item.server_name }}.conf"
    owner: root
    group: root
    mode: '0644'
    validate: "nginx -t"
  loop: "{{ nginx_vhosts }}"
  loop_control:
    label: "{{ item.server_name }}"
  notify: reload nginx
  when: nginx_vhosts | length > 0

- name: 确保 Nginx 服务运行
  service:
    name: nginx
    state: started
    enabled: yes

- name: 配置日志轮转
  template:
    src: logrotate-nginx.j2
    dest: /etc/logrotate.d/nginx
    owner: root
    group: root
    mode: '0644'
```

### 2.2 条件化任务

```yaml
# roles/nginx/tasks/ssl.yml
---
- name: 创建 SSL 证书目录
  file:
    path: "{{ nginx_config_path }}/ssl"
    state: directory
    mode: '0700'

- name: 部署 SSL 证书
  copy:
    src: "{{ item.src }}"
    dest: "{{ nginx_config_path }}/ssl/{{ item.dest }}"
    owner: root
    group: root
    mode: '0600'
  loop:
    - { src: "files/{{ ssl_cert_file }}", dest: "{{ ssl_cert_file }}" }
    - { src: "files/{{ ssl_key_file }}", dest: "{{ ssl_key_file }}" }
  notify: reload nginx
  no_log: true

- name: 生成 DH 参数（如果不存在）
  command: >
    openssl dhparam -out {{ nginx_config_path }}/ssl/dhparam.pem 2048
  args:
    creates: "{{ nginx_config_path }}/ssl/dhparam.pem"

# 在主任务中条件包含
# roles/nginx/tasks/main.yml
- name: 配置 SSL
  include_tasks: ssl.yml
  when: nginx_ssl_enabled | default(false)
```

## 三、Ansible Galaxy

### 3.1 使用 Galaxy Role

```bash
# 安装单个 Role
ansible-galaxy install geerlingguy.nginx

# 安装指定版本
ansible-galaxy install geerlingguy.nginx,3.1.0

# 从 requirements.yml 批量安装
ansible-galaxy install -r requirements.yml

# 列出已安装的 Role
ansible-galaxy list

# 删除 Role
ansible-galaxy remove geerlingguy.nginx
```

### 3.2 requirements.yml

```yaml
---
roles:
  # 从 Galaxy 安装
  - name: geerlingguy.nginx
    version: "3.1.0"
  
  - name: geerlingguy.mysql
    version: "4.0.0"
  
  # 从 Git 仓库安装
  - name: custom-role
    src: https://github.com/company/ansible-role-custom.git
    version: v1.2.0
    scm: git
  
  # 从本地路径安装
  - name: local-role
    src: /opt/ansible-roles/local-role

collections:
  # 从 Galaxy 安装 Collection
  - name: community.general
    version: ">=5.0.0"
  
  - name: community.docker
    version: "3.0.0"
  
  # 从 Git 安装 Collection
  - name: company.internal
    src: https://github.com/company/ansible-collection-internal.git
    type: git
    version: main
```

### 3.3 发布到 Galaxy

```bash
# 1. 确保 Role 符合 Galaxy 规范
# - meta/main.yml 包含 galaxy_info
# - README.md 包含角色文档
# - 目录结构标准

# 2. 在 Galaxy 网站导入
# 访问 https://galaxy.ansible.com
# 登录 → My Content → Add Content → GitHub

# 3. 使用 ansible-lint 检查
pip install ansible-lint
ansible-lint roles/nginx/

# 4. 使用 yamllint 检查 YAML 语法
pip install yamllint
yamllint roles/nginx/
```

## 四、Role 测试（Molecule）

### 4.1 Molecule 概述

Molecule 是 Ansible Role 的测试框架，支持多种驱动：

- **Docker** — 使用 Docker 容器测试（推荐）
- **Podman** — 使用 Podman 容器测试
- **Vagrant** — 使用虚拟机测试
- **Delegated** — 委托到真实服务器测试
- **Cloud** — 使用云实例测试

### 4.2 初始化 Molecule

```bash
# 安装 Molecule
pip install molecule molecule-docker molecule-podman

# 在 Role 目录初始化
cd roles/nginx
molecule init scenario -r nginx -d docker

# 目录结构
molecule/
└── default/
    ├── molecule.yml      # 场景配置
    ├── converge.yml      # 汇聚 Playbook
    ├── verify.yml        # 验证 Playbook
    └── prepare.yml       # 准备 Playbook（可选）
```

### 4.3 Molecule 配置

```yaml
# molecule/default/molecule.yml
---
dependency:
  name: galaxy
  options:
    requirements-file: requirements.yml

driver:
  name: docker
  options:
    managed: true

platforms:
  - name: nginx-centos9
    image: quay.io/centos/centos:stream9
    dockerfile: ../Dockerfile.j2
    command: /usr/sbin/init
    privileged: true
    cgroupns_mode: host
    volumes:
      - /sys/fs/cgroup:/sys/fs/cgroup:rw
    pre_build_image: false
    groups:
      - webservers

  - name: nginx-ubuntu22
    image: ubuntu:22.04
    command: /sbin/init
    privileged: true
    groups:
      - webservers

provisioner:
  name: ansible
  config_options:
    defaults:
      host_key_checking: false
      stdout_callback: yaml
  inventory:
    group_vars:
      webservers:
        nginx_worker_processes: 2

verifier:
  name: ansible

scenario:
  name: default
  test_sequence:
    - dependency
    - cleanup
    - destroy
    - syntax
    - create
    - prepare
    - converge
    - idempotence
    - verify
    - cleanup
    - destroy
```

### 4.4 Molecule 测试 Playbook

```yaml
# molecule/default/converge.yml
---
- name: Converge
  hosts: all
  become: yes
  roles:
    - role: nginx
      vars:
        nginx_worker_processes: 2
        nginx_vhosts:
          - server_name: test.example.com
            listen: 80
            root: /var/www/test
            locations:
              - path: /
                proxy_pass: http://127.0.0.1:8080

# molecule/default/verify.yml
---
- name: Verify
  hosts: all
  become: yes
  tasks:
    - name: 验证 Nginx 已安装
      command: nginx -v
      register: nginx_version
      changed_when: false
      failed_when: nginx_version.rc != 0

    - name: 验证 Nginx 服务运行中
      service:
        name: nginx
        state: started
      check_mode: yes
      register: nginx_service

    - name: 验证配置文件语法
      command: nginx -t
      register: nginx_config_test
      changed_when: false

    - name: 验证端口监听
      wait_for:
        port: 80
        timeout: 10

    - name: 验证 HTTP 响应
      uri:
        url: "http://localhost:80"
        status_code: 200
      register: http_response

    - name: 验证虚拟主机配置
      command: "nginx -T"
      register: nginx_full_config
      changed_when: false

    - name: 断言配置内容
      assert:
        that:
          - "'test.example.com' in nginx_full_config.stdout"
          - "'proxy_pass' in nginx_full_config.stdout"
        fail_msg: "虚拟主机配置未正确部署"
```

### 4.5 Molecule 命令

```bash
# 完整测试流程
molecule test

# 分步执行
molecule create       # 创建测试环境
molecule converge     # 执行 Playbook
molecule idempotence  # 测试幂等性
molecule verify       # 执行验证
molecule destroy      # 销毁环境

# 调试
molecule login --host nginx-centos9  # 登录容器调试

# 仅语法检查
molecule syntax

# 清理
molecule cleanup
```

## 五、Role 开发最佳实践

### 5.1 设计原则

1. **单一职责** — 每个 Role 只负责一个服务或功能
2. **可复用** — 通过变量定制，避免硬编码
3. **幂等性** — 多次执行结果一致
4. **可测试** — 支持 Molecule 测试
5. **文档完善** — README 说明变量和用法

### 5.2 变量设计

```yaml
# defaults/main.yml — 用户可覆盖的变量
nginx_port: 80
nginx_user: nginx

# vars/main.yml — 内部变量（不建议覆盖）
_nginx_package_name: nginx
_nginx_config_dir: /etc/nginx

# 命名约定
# - 公共变量：使用角色名前缀（nginx_port）
# - 内部变量：使用下划线前缀（_nginx_internal_var）
# - 必需变量：在 tasks 中使用 assert 验证
```

### 5.3 角色依赖管理

```yaml
# meta/main.yml
dependencies:
  # 始终执行
  - role: common
  
  # 条件依赖
  - role: firewall
    vars:
      firewall_allowed_ports:
        - "{{ nginx_port }}/tcp"
    when: enable_firewall | default(true)
  
  # 可选依赖
  - role: monitoring-agent
    when: install_monitoring | default(false)
```

### 5.4 持续集成

```yaml
# .github/workflows/molecule.yml
---
name: Molecule Test
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  molecule:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        scenario:
          - default
          - centos9
          - ubuntu22
    steps:
      - uses: actions/checkout@v3
      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.10'
      - name: Install dependencies
        run: |
          pip install molecule molecule-docker ansible-lint
      - name: Run Molecule
        run: molecule test --scenario-name ${{ matrix.scenario }}
        env:
          ANSIBLE_FORCE_COLOR: 'true'
```
