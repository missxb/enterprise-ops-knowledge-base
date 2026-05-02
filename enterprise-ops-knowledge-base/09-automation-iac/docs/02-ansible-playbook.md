# Playbook 编写深入

## 一、Playbook 基础结构

### 1.1 完整 Playbook 结构

```yaml
---
# site.yml — 主 Playbook
- name: 配置 Web 服务器
  hosts: webservers
  become: yes
  gather_facts: yes
  any_errors_fatal: no
  max_fail_percentage: 30
  serial: "50%"
  
  vars:
    http_port: 80
    app_env: production
  
  vars_files:
    - vars/common.yml
    - "vars/{{ ansible_os_family }}.yml"
  
  pre_tasks:
    - name: 验证前置条件
      assert:
        that:
          - ansible_memtotal_mb >= 1024
          - ansible_processor_vcpus >= 2
        fail_msg: "服务器资源不满足最低要求"
  
  roles:
    - common
    - nginx
    - docker
  
  tasks:
    - name: 部署应用
      include_tasks: tasks/deploy.yml
  
  post_tasks:
    - name: 健康检查
      uri:
        url: "http://localhost:{{ http_port }}/health"
        status_code: 200
      retries: 5
      delay: 10
  
  handlers:
    - name: restart nginx
      service:
        name: nginx
        state: restarted
```

## 二、条件判断 (When)

### 2.1 基础条件

```yaml
# 基于变量
- name: 仅在生产环境执行
  debug:
    msg: "生产环境任务"
  when: app_env == "production"

# 基于操作系统
- name: CentOS 专用任务
  yum:
    name: httpd
    state: present
  when: ansible_distribution == "CentOS"

- name: Ubuntu 专用任务
  apt:
    name: apache2
    state: present
  when: ansible_distribution == "Ubuntu"

# 基于主机变量
- name: 仅主节点执行
  command: /opt/scripts/init-cluster.sh
  when: mysql_role == "master"
```

### 2.2 复杂条件

```yaml
# 多条件组合
- name: 生产环境且内存大于 4GB 的服务器
  debug:
    msg: "配置高性能模式"
  when:
    - app_env == "production"
    - ansible_memtotal_mb >= 4096
    - ansible_processor_vcpus >= 4

# 逻辑或
- name: CentOS 或 RHEL
  yum:
    name: httpd
    state: present
  when: ansible_os_family == "RedHat"

# 取反
- name: 非容器环境
  debug:
    msg: "物理机/虚拟机环境"
  when: not is_container | default(false)

# 变量存在性检查
- name: 仅当 SSL 证书路径定义时
  template:
    src: ssl.conf.j2
    dest: /etc/nginx/ssl.conf
  when: ssl_cert_path is defined and ssl_cert_path

# 字符串匹配
- name: 匹配特定主机名
  debug:
    msg: "匹配的主机"
  when: inventory_hostname is match('web.*')

# 列表包含
- name: 检查角色
  debug:
    msg: "数据库服务器"
  when: "'dbservers' in group_names"
```

### 2.3 条件与循环组合

```yaml
- name: 安装可选包
  yum:
    name: "{{ item.name }}"
    state: present
  loop:
    - { name: "git", when: true }
    - { name: "htop", when: true }
    - { name: "strace", when: "{{ install_debug_tools | default(false) }}" }
  when: item.when
```

## 三、循环 (Loop)

### 3.1 基础循环

```yaml
# 简单列表循环
- name: 安装多个包
  yum:
    name: "{{ item }}"
    state: present
  loop:
    - nginx
    - python3
    - vim
    - htop

# 字典列表循环
- name: 创建多个用户
  user:
    name: "{{ item.name }}"
    groups: "{{ item.groups }}"
    shell: "{{ item.shell }}"
  loop:
    - { name: "deploy", groups: "wheel", shell: "/bin/bash" }
    - { name: "monitor", groups: "monitoring", shell: "/bin/bash" }
    - { name: "backup", groups: "backup", shell: "/bin/bash" }
```

### 3.2 高级循环

```yaml
# 嵌套循环
- name: 为每个用户配置每个项目目录
  file:
    path: "/home/{{ item.0.name }}/{{ item.1 }}"
    state: directory
    owner: "{{ item.0.name }}"
  loop: "{{ users | product(projects) | list }}"
  vars:
    users:
      - { name: "dev1" }
      - { name: "dev2" }
    projects:
      - project-a
      - project-b

# 使用 loop_control
- name: 带标签的循环
  debug:
    msg: "配置 {{ item.name }}"
  loop: "{{ servers }}"
  loop_control:
    label: "{{ item.name }}"     # 控制输出显示
    pause: 2                      # 每次循环暂停 2 秒
    index_var: idx                # 循环索引
    loop_var: server              # 重命名循环变量

# 使用 until 重试
- name: 等待服务启动
  uri:
    url: "http://localhost:{{ item }}/health"
    status_code: 200
  loop:
    - 8080
    - 8081
    - 8082
  register: health_result
  until: health_result.status == 200
  retries: 5
  delay: 10

# 使用 with_* 系列（旧语法，仍然有效）
- name: 遍历文件
  copy:
    src: "{{ item }}"
    dest: /etc/nginx/conf.d/
  with_fileglob:
    - "files/nginx/*.conf"

- name: 遍历字典
  debug:
    msg: "{{ item.key }} = {{ item.value }}"
  with_dict:
    name: web-server
    port: 80
    env: production
```

## 四、Handler

### 4.1 基础 Handler

```yaml
# tasks/main.yml
- name: 安装 Nginx
  yum:
    name: nginx
    state: present
  notify: restart nginx

- name: 部署 Nginx 配置
  template:
    src: nginx.conf.j2
    dest: /etc/nginx/nginx.conf
    validate: "nginx -t -c %s"
  notify:
    - reload nginx
    - log config change

- name: 确保 Nginx 运行
  service:
    name: nginx
    state: started
    enabled: yes

# handlers/main.yml
- name: restart nginx
  service:
    name: nginx
    state: restarted

- name: reload nginx
  service:
    name: nginx
    state: reloaded

- name: log config change
  lineinfile:
    path: /var/log/config-changes.log
    line: "{{ ansible_date_time.iso8601 }} - Nginx config updated"
    create: yes
```

### 4.2 Handler 特性

```yaml
# Handler 在所有任务执行完后才触发
# 可以使用 meta 强制立即执行
- name: 部署配置文件
  template:
    src: app.conf.j2
    dest: /etc/app/app.conf
  notify: restart app

- name: 立即重启服务（不等待所有任务完成）
  meta: flush_handlers

# Handler 可以被其他 Handler 调用
# handlers/main.yml
- name: restart app
  service:
    name: app
    state: restarted
  notify: verify app health

- name: verify app health
  uri:
    url: "http://localhost:8080/health"
    status_code: 200
  retries: 3
  delay: 5

# 使用 listen 使多个 handler 响应同一事件
- name: restart all services
  listen: "restart application services"
  service:
    name: "{{ item }}"
    state: restarted
  loop:
    - nginx
    - app
    - redis
```

## 五、Tag

### 5.1 Tag 使用

```yaml
- name: 安装软件包
  yum:
    name: "{{ item }}"
    state: present
  loop:
    - nginx
    - python3
  tags:
    - install
    - packages

- name: 配置 Nginx
  template:
    src: nginx.conf.j2
    dest: /etc/nginx/nginx.conf
  tags:
    - configure
    - nginx

- name: 部署应用代码
  git:
    repo: "{{ app_repo }}"
    dest: /opt/app
    version: "{{ app_version }}"
  tags:
    - deploy
    - code

- name: 安全加固
  include_tasks: security.yml
  tags:
    - security
    - hardening
```

### 5.2 Tag 命令行使用

```bash
# 仅执行特定 tag
ansible-playbook site.yml --tags "configure,deploy"

# 跳过特定 tag
ansible-playbook site.yml --skip-tags "install"

# 列出所有 tag
ansible-playbook site.yml --list-tags

# 列出特定 tag 的任务
ansible-playbook site.yml --tags "deploy" --list-tasks
```

### 5.3 特殊 Tag

```yaml
# always — 始终执行，除非明确跳过
- name: 清理临时文件
  file:
    path: /tmp/deploy
    state: absent
  tags:
    - always

# never — 从不执行，除非明确指定
- name: 危险操作
  command: /opt/scripts/dangerous.sh
  tags:
    - never
    - dangerous
```

## 六、错误处理

### 6.1 基础错误处理

```yaml
# ignore_errors — 忽略错误继续执行
- name: 尝试停止可能未运行的服务
  service:
    name: app
    state: stopped
  ignore_errors: yes

# failed_when — 自定义失败条件
- name: 检查磁盘使用率
  shell: df -h / | tail -1 | awk '{print $5}' | sed 's/%//'
  register: disk_usage
  failed_when: disk_usage.stdout | int > 90

# changed_when — 自定义变更条件
- name: 检查服务状态
  command: systemctl is-active nginx
  register: nginx_status
  changed_when: false

# check_mode — 检查模式安全任务
- name: 获取当前配置
  command: cat /etc/app/config.yml
  register: current_config
  check_mode: no
  changed_when: false
```

### 6.2 Block/Rescue/Always

```yaml
# 类似 try/catch/finally
- name: 带错误处理的部署流程
  block:
    - name: 拉取最新代码
      git:
        repo: "{{ app_repo }}"
        dest: /opt/app
        version: "{{ app_version }}"
    
    - name: 安装依赖
      pip:
        requirements: /opt/app/requirements.txt
        virtualenv: /opt/app/venv
    
    - name: 执行数据库迁移
      command: /opt/app/venv/bin/python manage.py migrate
    
    - name: 重启应用
      service:
        name: app
        state: restarted
  
  rescue:
    - name: 回滚到上一版本
      git:
        repo: "{{ app_repo }}"
        dest: /opt/app
        version: "{{ previous_version }}"
    
    - name: 重启应用（回滚版本）
      service:
        name: app
        state: restarted
    
    - name: 发送告警通知
      slack:
        token: "{{ slack_token }}"
        channel: "#ops-alerts"
        msg: "部署失败，已自动回滚: {{ ansible_hostname }}"
  
  always:
    - name: 清理临时文件
      file:
        path: /tmp/deploy-{{ app_version }}
        state: absent
    
    - name: 记录部署日志
      lineinfile:
        path: /var/log/deployments.log
        line: "{{ ansible_date_time.iso8601 }} - {{ app_version }} - {{ 'FAILED' if ansible_failed_task is defined else 'SUCCESS' }}"
        create: yes
```

### 6.3 错误处理最佳实践

```yaml
# 优雅降级
- name: 尝试安装可选组件
  block:
    - name: 安装监控 Agent
      yum:
        name: monitoring-agent
        state: present
  rescue:
    - name: 记录安装失败
      debug:
        msg: "监控 Agent 安装失败，跳过"

# 并行执行中的错误处理
- name: 配置所有服务器
  hosts: weervers
  serial: "30%"
  max_fail_percentage: 10
  tasks:
    - name: 配置任务
      include_tasks: configure.yml

# 委托任务的错误处理
- name: 检查负载均衡器
  uri:
    url: "http://{{ lb_host }}/health"
    status_code: 200
  delegate_to: localhost
  register: lb_health
  retries: 3
  delay: 5
  until: lb_health.status == 200
  ignore_errors: yes
```

## 七、高级特性

### 7.1 委托与本地执行

```yaml
# delegate_to — 委托到其他主机执行
- name: 从负载均衡器移除当前节点
  uri:
    url: "http://{{ lb_host }}/api/remove"
    method: POST
    body: '{"server": "{{ ansible_host }}"}'
    body_format: json
  delegate_to: localhost
  run_once: true

# local_action — 等效于 delegate_to localhost
- name: 本地执行备份
  local_action:
    module: copy
    src: /etc/app/config.yml
    dest: "backups/{{ inventory_hostname }}_config.yml"
```

### 7.2 异步任务

```yaml
# 长时间运行的任务
- name: 执行数据库备份（异步）
  command: /opt/scripts/backup.sh
  async: 3600      # 最长运行 1 小时
  poll: 0          # 不等待，立即返回
  register: backup_job

# 后续检查异步任务状态
- name: 等待备份完成
  async_status:
    jid: "{{ backup_job.ansible_job_id }}"
  register: job_result
  until: job_result.finished
  retries: 60
  delay: 60
```

### 7.3 动态任务包含

```yaml
# include_tasks — 动态包含（每次执行时解析）
- name: 根据操作系统包含任务
  include_tasks: "{{ ansible_os_family | lower }}.yml"

# import_tasks — 静态导入（解析时解析）
- name: 导入基础配置任务
  import_tasks: base-config.yml

# 区别：
# include_tasks — 条件和循环在执行时评估
# import_tasks — 条件和循环在解析时评估
```

## 八、实战 Playbook 模板

### 8.1 滚动更新 Playbook

```yaml
---
# rolling-update.yml
- name: 滚动更新应用
  hosts: webservers
  become: yes
  serial: 1
  max_fail_percentage: 0
  
  pre_tasks:
    - name: 从负载均衡器移除
      uri:
        url: "http://{{ lb_host }}/api/remove"
        method: POST
        body: '{"server": "{{ inventory_hostname }}"}'
        body_format: json
      delegate_to: localhost
    
    - name: 等待连接耗尽
      pause:
        seconds: 30
  
  roles:
    - app-deploy
  
  post_tasks:
    - name: 健康检查
      uri:
        url: "http://{{ ansible_host }}:{{ app_port }}/health"
        status_code: 200
      register: health
      until: health.status == 200
      retries: 10
      delay: 5
    
    - name: 加回负载均衡器
      uri:
        url: "http://{{ lb_host }}/api/add"
        method: POST
        body: '{"server": "{{ inventory_hostname }}"}'
        body_format: json
      delegate_to: localhost
```
