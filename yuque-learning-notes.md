# 语雀运维知识库学习笔记汇总

> 抓取时间：2026-05-02
> 共访问 25 个语雀知识库链接，全部成功获取内容

---

## 目录

1. [云计算运维公开知识库](#1-云计算运维公开知识库)
2. [K8S学习笔记](#2-k8s学习笔记)
3. [Linux](#3-linux)
4. [Docker 学习记录](#4-docker-学习记录)
5. [运维devops](#5-运维devops)
6. [默认知识库（陈博学）](#6-默认知识库陈博学)
7. [学习知识库](#7-学习知识库)
8. [运维知识库（逝水fox）](#8-运维知识库逝水fox)
9. [运维知识库（刘晓东）](#9-运维知识库刘晓东)
10. [问题运维知识库](#10-问题运维知识库)
11. [运维知识库（爱吃鸭头的丫头）](#11-运维知识库爱吃鸭头的丫头)
12. [nginx 在 docker 下配置 ssl 访问](#12-nginx-在-docker-下配置-ssl-访问)
13. [数据库运维知识](#13-数据库运维知识)
14. [运维方向知识库](#14-运维方向知识库)
15. [运维技术v2知识库](#15-运维技术v2知识库)
16. [分布式](#16-分布式)
17. [linux学习笔记（予安）](#17-linux学习笔记予安)
18. [知识点（菲菲很甜）](#18-知识点菲菲很甜)
19. [Prometheus 详解](#19-prometheus-详解)
20. [云原生](#20-云原生)
21. [项目知识库](#21-项目知识库)
22. [运维相关（星弈）](#22-运维相关星弈)
23. [运维知识库（鱼岸争浪）](#23-运维知识库鱼岸争浪)
24. [技术沙龙](#24-技术沙龙)
25. [云原生(K8S+Devops)](#25-云原生k8sdevops)

---

## 1. 云计算运维公开知识库

- **链接**: https://www.yuque.com/zerd-xinghai/cloud
- **作者**: 混合云架构师星海
- **文档数**: 118 | **字数**: 596,482

### 目录结构

**容器云原生**
- 云原生架构图
- 搭建K8S高可用集群一般用keepalived+lvs还是HAProxy？有什么区别?
- centos7.9 部署k8s1.28
- 单 Master 改造至高可用三 Master 集群实战
- CentOS 7.9 Kubernetes 1.28 高可用部署方案（HAProxy + Keepalived）
- Kubernetes 高可用 Master 集群缩容通用实战教程
- Centos7.9 k8s 1.23高可用(Keepalived + LVS)

**linux入门课程**
- 运维基本导论与Linux系统部署
- Linux运维核心命令
- 基于云平台博客系统部署与监控运维实战
- 基于Ubuntu Server部署开源AI大模型聊天机器人

**网络**
- day01_网络基础
- day02_网络进阶

**系统运维**
- day01_SSH服务
- day02_数据同步服务
- day03_FTP与磁盘挂载
- day04_共享文件和目录服务
- day05_DNS服务器
- day06_RSYSLOG系统日志管理

**其他文档**
- 内网穿透部署手册：基于 Docker + Cpolar
- 云计算运维知识库（主文档）
- 面试辅导都要做什么？

### 关键技术要点
- K8S高可用集群部署方案对比：Keepalived+LVS vs HAProxy
- CentOS 7.9 + K8S 1.28 完整部署流程
- 单Master到三Master集群改造实战
- K8S集群缩容操作指南

---

## 2. K8S学习笔记

- **链接**: https://www.yuque.com/anson-e1puz/k8s
- **作者**: Anson
- **文档数**: 63 | **字数**: 245,748
- **简介**: K8S虐我千百遍, 我对K8S如初恋

### 目录结构

**基础**
- 简介
- 安装
- Pod 原理
- Pod 生命周期
- Pod 使用进阶

**控制器**
- ReplicaSet
- Deployment
- StatefulSet
- DaemonSet
- Job 与 CronJob
- HPA 控制器

**配置管理**
- ConfigMap
- Secret
- ServiceAccount

**安全**
- RBAC 权限控制
- Security Context
- Pod 安全策略
- 准入控制器

**网络**
- Flannel
- NetworkPolicy (网络策略)
- Service

### 关键技术要点
- K8S核心概念：Pod、控制器、配置管理、安全、网络
- Pod生命周期管理与使用进阶
- 各类控制器（ReplicaSet/Deployment/StatefulSet/DaemonSet）适用场景
- RBAC权限控制与安全策略配置
- Flannel网络方案与NetworkPolicy网络策略

---

## 3. Linux

- **链接**: https://www.yuque.com/skydeity/linux
- **作者**: 坼天栋（学不学IT）
- **文档数**: 240 | **字数**: 263,315

### 目录结构（部分）

- 什么是Verified Mark Certificate（VMC)
- 浏览器网络权限设置
- ssh 连接错误
- nginx 代理-跨域
- linux 定时清理磁盘脚本
- docker部署vscode
- glibc版本升级
- java启动参数配置
- gitlab设置多镜像仓库
- 子网划分
- git仓库加密git-crypt
- pod 服务日志输出到本地的风险
- nginx 配置文件下载
- linux 定时清理文件
- hertzbeat监控部署
- nessus 扫描器
- docker映射端口修改
- Mac终端下使用Corkscrew + SSH通过代理连接内网服务器
- 站点ssl协议扫描
- kubenetes pod崩溃分析
- DevSecOps
- 故障复盘
- shell 脚本加密

### 关键技术要点
- SSH连接问题排查与代理配置
- Nginx代理与跨域配置
- Docker部署与端口管理
- Git仓库加密（git-crypt）
- K8S Pod崩溃分析
- DevSecOps安全运维实践
- Shell脚本加密保护
- Linux定时清理脚本编写

---

## 4. Docker 学习记录

- **链接**: https://www.yuque.com/yongz/docker
- **作者**: 负五佰
- **文档数**: 40 | **字数**: 83,019

### 目录结构

**Docker Other**
**疑难杂症**
**Install**
**CTFd**

**Docker（从入门到实践）**
- 01. Docker基本概念
- 02. Docker软件安装
- 03. Docker镜像使用
- 04. Dockerfile构建
- 05. Docker容器管理
- 06. Docker仓库访问
- 07. Docker数据管理
- 08. Docker网络配置
- 09. Docker高级网络配置
- 10. Docker Compose

**Docker（编程不良人）**
- 01. Docker 概要
- 02. Docker 基础
- 03. Docker File
- 04. Docker Network
- 05. Docker Volume
- 06. Docker Compose
- 07. Docker Portainer

**Docker（周阳）**
- 01. Docker 简介
- 02. Docker 安装
- 03. Docker 常用命令

### 关键技术要点
- Docker从入门到实践完整学习路径
- Dockerfile构建与镜像管理
- Docker网络配置（基础+高级）
- Docker数据管理（Volume）
- Docker Compose编排
- Portainer可视化管理

---

## 5. 运维devops

- **链接**: https://www.yuque.com/sdliang/ops
- **作者**: 默客
- **文档数**: 8 | **字数**: 71,573

### 目录结构

- 防火墙
- 工具包
- Window
- Linux
- Debian
- PVE
- docker
- LXC容器
- Windows Subsystem Linux
- Systemd
- YUM - RPM管理
- Linux磁盘扩容
- ssh免密登录
- Linux文本文件操作
- DNS服务
- 漏洞安全
- Diff和Patch
- Git Reference
- Nginx/Openresty
- MySQL
- PostgresQL
- MongoDB
- Neo4j
- Prometheus
- Grafana
- StackStorm
- SaltStack Reference

### 关键技术要点
- 多平台运维：Linux/Debian/PVE/Windows/WSL
- 容器技术：Docker/LXC
- 数据库运维：MySQL/PostgreSQL/MongoDB/Neo4j
- 监控体系：Prometheus + Grafana
- 自动化工具：SaltStack/StackStorm
- 系统管理：Systemd/YUM-RPM/磁盘扩容

---

## 6. 默认知识库（陈博学）

- **链接**: https://www.yuque.com/chenboxue/kb
- **作者**: 陈博学👾👾
- **文档数**: 68 | **字数**: 301,701

### 目录结构（部分）

- 消息中间件面试题
- 本地缓存、redis优缺点
- select、poll、epoll区别
- 领域驱动设计
- 分布式事务
- Redis / redis 多线程 / redis cluster
- 并发复习脑图
- RocketMQ
- springboot、spring
- 常见限流算法
- 缓存算法（FIFO、LRU、LFU三种算法的区别）
- 零拷贝
- JVM
- mysql
- 线程池
- LinkedBlockingQueue / CopyOnWriteArrayList / Hashmap
- 排查Java问题工具清单
- 面经分享
- Stream
- 可重入分布式锁
- 代理模式、复合、策略、模板模式
- 布隆过滤器（Bloom Filter）原理以及应用
- 解释器、建造者、工厂模式

### 关键技术要点
- Java核心技术：JVM/并发/集合框架
- 分布式系统：分布式事务/分布式锁/分布式限流
- 中间件：Redis/RocketMQ/Kafka
- 缓存策略：FIFO/LRU/LFU算法对比
- 设计模式：代理/策略/模板/工厂/建造者
- 面试准备：消息中间件/缓存/限流算法

---

## 7. 学习知识库

- **链接**: https://www.yuque.com/desistdaydream/learning
- **作者**: DesistDaydream
- **文档数**: 1,222 | **字数**: 2,511,098
- **备注**: 已迁出语雀，更多文档详见 https://desistdaydream.github.io/docs/

### 目录结构

- ✏IT学习笔记
- 💻计算机（操作系统/编程/集群与分布式/数据通信/数据存储）
- 👀可观测性
- 🔐信息安全
- 📐通用技术
- 🛠️运维
- ☁️云原生
- 📹图形处理
- 🤖人工智能
- 🧰实用工具
- 🧊区块链
- 📚StandardizedGlossary(标准化术语)
- 语言

### 关键技术要点
- 超大规模知识库（1222篇文档，250万字）
- 涵盖IT全栈：操作系统→编程→分布式→存储→安全→云原生→AI
- 可观测性专题
- 信息安全专题
- 区块链技术

---

## 8. 运维知识库（逝水fox）

- **链接**: https://www.yuque.com/shishuifox/dev
- **作者**: 逝水fox
- **文档数**: 55 | **字数**: 183,114

### 目录结构

**技术笔记**
- 2026.03.25 国密支持Nginx安装
- 2026.03.16 Linux下隐藏进程检查
- 2025.09.28 Nacos集群服务注册信息检查
- 2025.07.17 性能建模
- 2025.05.30 Linux随机端口小计
- 2025.05.23 Linux内核本机数据发送网络层路由
- 2025.01.04 再看Linux glibc 64M内存问题
- 2024.11.14 Redis集群在k8s上使用固定ip的解决方案
- 2024.09.24 ping测试脚本
- 2024.09.19 Oracle PDB管理 / Oracle DBLink配置 / Oracle数据库常规管理
- 2024.09.18 分布式Hadoop环境搭建
- 2024.09.18 MySQL连接操作审计配置
- 2023.06.06 NFS网络文件系统配置和rsync备份方案
- 2021.12.14 Apache FTP Server服务器搭建
- 2021.06.01 rsync文件系统同步复制配置
- 2021.06.01 ffmpeg Linux安装手册
- 2021.06.01 Cacti Linux安装手册

**Linux基础**
- 1. Linux介绍
- 2. CentOS的安装
- 3. Linux服务器信息确认
- 4. Linux服务器初始化调整
- 5. Linux使用技巧

### 关键技术要点
- 国密支持的Nginx安装配置
- Linux隐藏进程检查方法
- Nacos集群服务注册信息检查
- 性能建模方法论
- Linux内核网络层路由原理
- Redis集群在K8S上使用固定IP的解决方案
- Oracle数据库管理（PDB/DBLink/常规管理）
- NFS+rsync备份方案

---

## 9. 运维知识库（刘晓东）

- **链接**: https://www.yuque.com/liuxiaodong-tpcfe/pme7qa
- **作者**: 刘晓东（团队协作知识库）
- **文档数**: 59 | **字数**: 33,487

### 目录结构

- 语雀操作规范
- 项目FAQ问题解决
- 部署智能双控中一些常见问题（拓展虚拟机内存）
- 虚拟机非正常情况关机，再次开启时无法打开
- 部署智能双控离线安装MySQL时报错
- 网络IP、掩码出现变化时，docker无法启动
- 新建虚拟机报错"Intel VT-x处于禁用状态"
- 平台数据库表ip和端口的问题
- 本机上传附件路径问题
- 服务器重启后时间重置
- CoalFileService服务无法启动问题排查方案
- CoalFileService服务配置文件
- 数据库连接错误数过多
- 提醒灯在路由情况下设置映射
- 动态扩容Linux根目录
- 服务器非正常关机后服务重启顺序
- 三种方法修改docker的默认存储位置

**知识点分享**
- 因容器内存占满导致手持机下载数据出错
- Win10投影仪扩展模式怎么用
- 打印机打印图片老是缺一半如何解决
- 如何防止软件自动安装到电脑中
- win10无法远程桌面连接的解决办法
- linux常用系统命令
- centos7配置本地的yum源
- docker容器的迁移
- Linux系统内存不够用怎么办？释放Linux内存的教程

### 关键技术要点
- Docker常见问题：网络IP变化导致无法启动、默认存储位置修改、容器迁移
- 虚拟机管理：非正常关机恢复、内存扩容
- MySQL离线安装与数据库连接问题排查
- Linux根目录动态扩容
- 服务器非正常关机后服务重启顺序

---

## 10. 问题运维知识库

- **链接**: https://www.yuque.com/spacex-aczuf/zsg2rh
- **作者**: spaceX
- **文档数**: 4 | **字数**: 6,786

### 目录结构

- windows常见问题
- veeam备份系统实施报告
- Veeam操作
- ERP-升级服务器问题点
- windows本地NTP时间同步服务器搭建
- Windows server磁盘扩容问题解决
- Veeam还原数据库报错问题
- 惠普老服务器驱动下载地址

**操作系统知识库**
- 域控批量用户建立
- 常见运维问题

### 关键技术要点
- Windows Server运维：磁盘扩容、NTP时间同步、域控管理
- Veeam备份系统实施与操作
- ERP系统升级问题处理

---

## 11. 运维知识库（爱吃鸭头的丫头）

- **链接**: https://www.yuque.com/yatou-qu3cw/cfkwvz
- **作者**: 爱吃鸭头的丫头
- **文档数**: 32 | **字数**: 30,335

### 目录结构

- 运维需要有哪些监控信息？
- 运维知识指南！
- redis有哪些应用场景？
- 词义解释
- 什么是数据库连接池？
- 什么是SQL server的CDC？
- DDOS攻击和CC攻击分别是怎样的？
- 生产中各类消息中间件（ActiveMQ、RabbitMQ、RocketMQ、Kafka）选用的特性
- 句柄及句柄泄露
- 十大消息推送方式
- 堡垒机
- 什么是数据库镜像？它有什么用途？
- 超详细的Canal入门！
- 计算机术语dump是什么意思？
- Cookie
- 什么是幂等？
- Pinpoint（全链路监控工具）
- 呼叫中心知识拓展
- 集群，分布式，微服务概念和区别
- 负载均衡、集群、分布式关系？
- 冷节点热节点概念
- 快照与备份的区别！
- kafka知识点
- 什么是高可用？
- 负载均衡
- 什么是集群,集群的概念介绍
- 专业词库收集（持续维护）

### 关键技术要点
- 运维基础知识体系：集群/分布式/微服务/负载均衡/高可用
- 消息中间件选型：ActiveMQ/RabbitMQ/RocketMQ/Kafka对比
- 监控工具：Pinpoint全链路监控
- 数据库技术：连接池/镜像/Canal数据同步
- 安全：DDOS/CC攻击防护、堡垒机

---

## 12. nginx 在 docker 下配置 ssl 访问

- **链接**: https://www.yuque.com/chentianyu/lnvtfu/yd8nxd
- **作者**: Daniel
- **类型**: 单篇文章

### 关键内容

**docker 安装指令**

**申请SSL证书并生成定时服务**
- 使用 acme.sh 申请证书

**映射必要目录**

**http 转 https**
1. 标准接口 http => https
2. 非标准接口 497 错误处理

### 配置要点
- Docker环境下Nginx SSL配置完整流程
- acme.sh证书申请与自动续期
- HTTP到HTTPS的标准与非标准端口转换

---

## 13. 数据库运维知识

- **链接**: https://www.yuque.com/donyu/yilzve
- **作者**: 冬雨
- **文档数**: 9 | **字数**: 24,096

### 目录结构

- MySQL主备搭建
- MySQL调优之innodb_buffer_pool_size大小设置

**MySQL运维基础知识**
- 第一篇 MySQL数据库基础
- 第二篇 数据库对象与应用
- 第三篇 MySQL事务与存储引擎
- 第四篇 MySQL应用优化
- 第五篇 MySQL运维实践
- 第六篇 MySQL高级架构技术
- mysql主从复制配置

### 关键技术要点
- MySQL完整运维知识体系（6篇系统性文章）
- MySQL主备搭建与主从复制配置
- innodb_buffer_pool_size调优
- MySQL事务与存储引擎
- MySQL高级架构技术

---

## 14. 运维方向知识库

- **链接**: https://www.yuque.com/dandanguaijiangjun/layth2
- **作者**: 蛋蛋怪将军
- **文档数**: 12 | **字数**: 6,670

### 目录结构

- 学习Docker
- 如何选择开源许可证
- nginx
- Docker重学
- 宿主机无法访问WSL2网络问题排查

### 关键技术要点
- Docker学习（两次学习记录）
- Nginx配置
- WSL2网络问题排查
- 开源许可证选择指南

---

## 15. 运维技术v2知识库

- **链接**: https://www.yuque.com/wesley-og4sq/ocgg5b
- **作者**: 樵夫
- **文档数**: 7 | **字数**: 9,618

### 目录结构

- WiFi贴项目详细执行计划

**脚本相关**
- 服务器免密脚本
- 集群安装ZKS脚本

**代理相关-公开**
- Shadowsocks正向代理

**iptables**
- iptables图谱
- 防火墙概念及iptables初识
- iptables基础认识-001

### 关键技术要点
- iptables防火墙配置与管理
- 服务器免密登录脚本
- ZooKeeper集群安装脚本
- Shadowsocks正向代理配置

---

## 16. 分布式

- **链接**: https://www.yuque.com/mengshirenshengfanwaipian/dszzf8
- **作者**: 梦是人生番外篇
- **文档数**: 22 | **字数**: 71,491

### 目录结构

- MySQL Group Replication
- Redis主从搭建与使用
- Mysql主从搭建与使用
- Mysql 与 Redis 在主从复制\集群的使用及所产生的问题
- 高可用
- 分布式
- seata
- sentinel
- 分布式旧笔记
- open feign
- 选择REST还是RPC
- springcloud gateway
- nacos
- redis集群/DB集群/MQ集群带来的问题
- 分布式消息中间件
- 分布式单点登录
- 分布式限流
- 分布式缓存
- 分布式幂
- 分布式锁
- 分布式事务
- 分布式全局ID
- 读写分离
- 分库分表

### 关键技术要点
- 分布式核心技术全覆盖：事务/锁/缓存/限流/幂等/全局ID/单点登录
- 数据库集群：MySQL主从/Group Replication、Redis主从/集群
- 微服务组件：Nacos/Seata/Sentinel/OpenFeign/SpringCloud Gateway
- 消息中间件与集群问题分析
- 分库分表与读写分离方案

---

## 17. linux学习笔记（予安）

- **链接**: https://www.yuque.com/u29257620/zfl
- **作者**: 予安
- **文档数**: 131 | **字数**: 271,426

### 目录结构（部分）

- 测试题
- jenkins / jenkins 实现CICD / jenkins安装及邮箱配置
- kvm / kvm脚本管理 / kvm部署
- docker / docker直接访问另外一个机器的镜像 / docker-compose安装 / docker-compose案例
- Kubernetes / Traefik-Midder-Router / Traefik-Ingress / Traefik
- K8s 网络刨析 / k8s 存储卷与数据持久化 / k8s基础学习理解
- Kubernetes+Haporxy高可用集群
- Prometheus（多篇：监控/配置文件和标签/发现机制和告警/告警/k8s部署prometheus）

### 关键技术要点
- CI/CD：Jenkins安装配置与CICD实现
- 虚拟化：KVM部署与脚本管理
- 容器：Docker/Docker Compose
- 云原生：Kubernetes完整学习（网络/存储/调度/安全）
- 服务网格：Traefik Ingress配置
- 监控：Prometheus完整学习（安装/配置/告警/K8S部署）

---

## 18. 知识点（菲菲很甜）

- **链接**: https://www.yuque.com/feifeihentian/bqz5zw
- **作者**: 菲菲很甜
- **文档数**: 85 | **字数**: 437,198

### 目录结构

**基础**
- linux基础
- 网络协议和通信
- 磁盘
- MYSQL
- keepalived
- 监控ZABBIX
- KVM
- 企业级堡垒机 JumpServer
- Docker
- 版本管理系统 Git 和 GitLab
- CICD 服务器 Jenkins
- Prometheus
- 微服务
- MinIO
- ELK日志
- kubernetes1
- mysql
- 证书

**复习**
**行业**
**具体场景步骤**
- 容器化平台搭建与迁移项目
- 博瑞尚格
- 结合简历面试题
- k8s场景化面试准备

### 关键技术要点
- 运维全栈知识：Linux/网络/磁盘/MySQL/Docker/K8S
- 监控体系：Zabbix + Prometheus
- CI/CD：Jenkins + Git/GitLab
- 日志系统：ELK
- 对象存储：MinIO
- 安全：JumpServer堡垒机/证书管理/keepalived高可用
- 面试准备：k8s场景化面试/简历面试题

---

## 19. Prometheus 详解

- **链接**: https://www.yuque.com/u21011333/ndkdqw/pfdmt1
- **作者**: 匿名
- **类型**: 单篇详细技术文章

### 关键内容

**1. Prometheus 介绍**
- 开源系统监控和报警系统，已加入CNCF基金会
- 支持多种exporter采集数据，支持pushgateway数据上报
- 性能可支撑上万台规模集群

**2. Prometheus 特点**
- 多维度数据模型
- 灵活的查询语言（PromQL）
- 本地部署，不依赖分布式存储
- HTTP pull方式采集时序数据
- pushgateway推送数据
- 服务发现或静态配置发现目标
- Grafana可视化
- 高效存储：每个采样约3.5 bytes，300万时间序列30s间隔保留60天约200G

**3. Prometheus 组件**
- Prometheus Server：收集和存储时间序列数据
- Client Library：客户端库
- Exporters：多种数据采集器
- Alertmanager：报警管理（支持邮件/微信/钉钉/Slack）
- Grafana：监控仪表盘
- pushgateway：数据上报网关

**4. 工作流程**
- Prometheus Server定期从目标主机拉取监控数据
- 数据保存到本地磁盘或数据库
- 配置报警规则触发报警发送到Alertmanager
- Alertmanager发送报警到邮件/微信/钉钉
- Grafana接入Prometheus数据源图形化展示

**5. 四种数据类型**
- **Counter**：计数器，累计值（请求次数/任务完成数/错误次数）
- **Gauge**：仪表盘，可增可减的值
- **Histogram**：直方图
- **Summary**：摘要

**6-9. Kubernetes监控部署**
- node-exporter组件安装配置
- Prometheus Server安装配置
- SA账号创建与RBAC授权
- ConfigMap存储Prometheus配置
- Deployment部署Prometheus
- Service暴露Prometheus
- Prometheus热加载配置

**10. Grafana安装配置**
- Grafana介绍与安装

### 配置示例

```yaml
# Prometheus查询示例
# 获取HTTP请求增长率
rate(http_requests_total[5m])

# 查询访问量前10的HTTP地址
topk(10, http_requests_total)
```

```bash
# Prometheus热加载命令
curl -X POST http://localhost:9090/-/reload
```

---

## 20. 云原生

- **链接**: https://www.yuque.com/ywbrother/ktdkzh
- **作者**: ywbrother
- **文档数**: 61 | **字数**: 549,503

### 目录结构

**helm部署应用**
- 部署redis
- 部署mariadb
- k8s中部署etcd
- kubectl 读取的文件格式
- 容器的限流和limit、request
- ubuntu 22.04 基于container安装k8s
- 文档
- 构建镜像-基础镜像
- 构建镜像 buildkit
- k8s 版本支持的docker版本

**harbor**
- lb代理harbor 时，返回404错误

**k8s开发**
- 文档地址

**client-go**
- Kubernetes API
- 资源类型 Scheme
- clientset 使用
- Informer 使用
- Informer 架构说明
- Reflector 源码分析
- DeltaFIFO 源码分析
- Indexer 源码分析
- Shared Informer 源码分析
- WorkQueue 源码分析

### 关键技术要点
- Helm应用部署：Redis/MariaDB/etcd
- K8S开发：client-go深度学习（Informer/Reflector/DeltaFIFO/Indexer源码分析）
- 镜像构建：Buildkit使用
- Harbor镜像仓库管理
- K8S版本兼容性

---

## 21. 项目知识库

- **链接**: https://www.yuque.com/xhaihua/hgy1v4
- **作者**: xhaihua
- **文档数**: 21 | **字数**: 95,398

### 目录结构

- 项目一：Harbor多实例高可用共享存储
- 项目二：RabbitMQ3.8镜像队列集群
- 项目三：Kafka集群部署及监控
- 项目四：prometheus监控系统
- 项目五：Redis5.0集群部署
- 项目六：基于二进制安装kubernetes1.19.3
- 项目七：openstack（Rocky 版）集群部署
- 项目八：通过阿里云ECS部署高可用k8s集群
- 项目九：通过rook部署Ceph分布式存储
- 项目十：Kubernetes云架构平台
- 项目十一：mongo4.4.2+副本集+认证部署
- 项目十二：系统架构设计
- 项目十三：SRE运维体系 / SRE
- 项目十五：.NET Core容器化
- 项目十六：运维体系化建设
- 项目十七：glusterfs存储
- 项目十八：mongodb
- 项目十九：rsync/lsyncd/sersync / LB+keepalived
- 基于kubeadm安装kubernetes1.21

### 关键技术要点
- 19个完整运维项目实战
- 容器平台：Harbor高可用/K8S二进制部署/kubeadm部署/OpenStack
- 中间件集群：RabbitMQ镜像队列/Kafka/Redis5.0/MongoDB
- 存储方案：Ceph(Rook)/GlusterFS
- 监控体系：Prometheus
- SRE运维体系与架构设计
- 负载均衡：LB+Keepalived
- 数据同步：rsync/lsyncd/sersync

---

## 22. 运维相关（星弈）

- **链接**: https://www.yuque.com/xingyi-wax8a/ngcg3g
- **作者**: 星弈
- **文档数**: 304 | **字数**: 534,044

### 目录结构

- 运维相关问题&解决方案
- K8s问题解决方案小记

**WEB 服务**
- 【keeplived】
- 【haproxy--配置】
- Nginx 相关

**Database**
- Redis
- mongo使用
- mysql常用笔记
- MySQL 设计规则
- 【Myslq安全配置】
- 【Mysql数据库安装】
- 【mysql--mgr集群】
- MYSQL 常用操作
- MySQL 参数设置和查看
- 数据库遇见问题汇总
- 数据库锁相关
- 数据库相关配置文件

**自动化部署流程**
- CICD规范
- 问题记录
- ansible
- jenkins

**K8S 相关**
- 【Container--常规使用】
- 【docker--常用命令集合】

### 关键技术要点
- 超大规模运维知识库（304篇，53万字）
- WEB服务：Keepalived/HAProxy/Nginx
- 数据库全栈：MySQL（安装/设计/安全/MGR集群/参数/锁）/Redis/MongoDB
- 自动化部署：Ansible/Jenkins/CICD规范
- K8S/Docker常用操作
- 运维问题解决方案汇总

---

## 23. 运维知识库（鱼岸争浪）

- **链接**: https://www.yuque.com/bairuijun/qb6lb5
- **作者**: 鱼岸争浪
- **文档数**: 31 | **字数**: 10,227

### 目录结构

- weblogic更新2020第四季度补丁问题处理
- WebLogic Server Side Request Forgery漏洞修复
- WEBLOGIC WLS 组件漏洞
- iptables 限制端口访问
- 同数据库备份表/恢复表
- weblogic补丁安装
- oracle用户密码过期
- oracle系统参数查询
- oracle连接数，参数
- linux_oracle定时备份数据
- for update死锁
- Weblogic进入控制台速度慢解决方法(linux)
- centos开通端口
- linux环境下使用oracle的常用命令及常见问题
- linux环境下安装rabbitmq
- Linux下安装部署Nginx反向代理服务器
- Windows下安装部署Nginx反向代理服务器
- 启动weblogic域不需要输入密码设置方法
- Oracle11g版本exp备份时不导出空表解决方法
- oracle数据库的字符集更改
- Linux操作系统定时任务设置删除日志
- Tomcat启动日志不写入catalina.out日志文件
- nohup启动服务不生成nohup.out文件命令
- linux服务器max user processes
- 优化zookeeper服务
- linux系统资源查看Top详解
- windows操作系统下tomcat服务启动时闪退

### 关键技术要点
- WebLogic运维：补丁安装/漏洞修复/控制台优化/免密启动
- Oracle数据库：用户管理/参数查询/定时备份/字符集/死锁处理
- Linux系统管理：端口管理/定时任务/进程管理/Top详解
- 中间件：Nginx反向代理/RabbitMQ安装/ZooKeeper优化/Tomcat问题排查

---

## 24. 技术沙龙

- **链接**: https://www.yuque.com/dataflux/nhkhqo
- **作者**: 观测云（团队协作）
- **文档数**: 124 | **字数**: 276,843

### 目录结构（近期文章）

- Linux实例内存使用率较高问题处理
- 跨可用区迁移服务器
- 7月 CloudCare DMS 运维报告
- Linux实例CPU使用率较高问题解决
- 服务器迁移（阿里云迁移腾讯云）
- AI 大模型选型指南
- Windows实例磁盘使用率告警解决
- VPC对等连接
- AI 智能体：开启数字化运维新篇章
- 阿里云CDN
- 如何降低AK泄露风险
- Redis 设计和使用规范
- 官网高可用改造
- 阿里云云监控核心能力解析
- MySQL 设计和使用规范
- 阿里云云监控的初体验
- WAF和云防火墙最佳实践
- CloudCare 企业 ITSM 平台 - 报告管理
- 智能化运维与DevOps
- 业务系统灾备与灾备演练
- CloudCare 企业 ITSM 平台 - 情报管理
- 容器化技术（Docker），重塑云计算运维格局
- 日志采集与安全审计
- 基于 Web 的 Linux 远程终端 - Ansi 转义序列
- ECS自建数据库的灾备与安全最佳实践
- 云计算环境下的智能运维（AIOps）
- Golang 基础赋能（四）

### 关键技术要点
- 云运维最佳实践：阿里云CDN/云监控/WAF/云防火墙
- 数据库规范：MySQL设计和使用规范/Redis设计和使用规范
- 智能运维：AIOps/AI智能体/AI大模型选型
- 安全：AK泄露风险/WAF/安全审计
- 灾备：业务系统灾备与演练/ECS数据库灾备
- 服务器迁移：跨可用区迁移/跨云迁移
- ITSM平台：CloudCare报告管理/情报管理

---

## 25. 云原生(K8S+Devops)

- **链接**: https://www.yuque.com/yuqueyonghupjeycu/zur1zw/umvusgigcksebq6d
- **作者**: Liufz
- **类型**: 单篇文章 + 知识库目录

### 文章内容：日常问题汇总

**1. k8s删除namespace卡住**
- 问题：删除namespace时资源状态卡在Terminating
- 解决：导出namespace为json，删除finalizers字段，通过API接口删除
```bash
# 导出namespace
kubectl get namespace 名称空间 -o json > temp.json

# 启动代理
kubectl proxy --port=8081

# 通过API删除
curl -k -H "Content-Type:application/json" -X PUT --data-binary @temp.json http://127.0.0.1:8081/api/v1/namespaces/名称空间/finalize
```

**2. 大量pod状态为Evicted**
- 原因：节点资源不足
```bash
kubectl get pods | grep Evicted | awk '{print $1}' | xargs kubectl delete pod
```

**3. 修改nodeport暴露的端口范围**
- 默认范围：30000-32767

**4. kubeadm部署指定端口**
- 需要在calico-node的变量增加配置

**5. 获取k8s访问真实ip**
- 需要在service增加对应字段（注意：会导致应用只能通过所在node节点访问）

### 知识库目录

- 云原生
- k8s自定义调度器
- k8s
- 日常问题汇总
- k8s支持nvidia的gpu
- k8s安装
- Kubernetes概念
- k8s基础入门
- k8s的dashboard
- K8S工作负载
- k8s网络和负载均衡
- k8s存储
- k8s调度原理
- k8s修改证书有效期
- k8s安全性
- helm应用商店
- k8s高可用安装

---

## 统计汇总

| # | 知识库名称 | 文档数 | 字数 | 主要主题 |
|---|-----------|--------|------|---------|
| 1 | 云计算运维公开知识库 | 118 | 596K | K8S高可用、Linux运维、网络 |
| 2 | K8S学习笔记 | 63 | 245K | K8S全栈（Pod/控制器/配置/安全/网络） |
| 3 | Linux | 240 | 263K | Linux运维、Docker、K8S、安全 |
| 4 | Docker学习记录 | 40 | 83K | Docker入门到实践 |
| 5 | 运维devops | 8 | 71K | 多平台运维、数据库、监控 |
| 6 | 默认知识库 | 68 | 301K | Java、分布式、中间件、设计模式 |
| 7 | 学习知识库 | 1222 | 2511K | IT全栈（最大知识库） |
| 8 | 运维知识库(逝水fox) | 55 | 183K | Linux运维、数据库、安全 |
| 9 | 运维知识库(刘晓东) | 59 | 33K | Docker问题排查、VM管理 |
| 10 | 问题运维知识库 | 4 | 6K | Windows Server、Veeam备份 |
| 11 | 运维知识库(丫头) | 32 | 30K | 运维基础概念、中间件选型 |
| 12 | nginx+docker ssl | 1 | - | Nginx SSL配置 |
| 13 | 数据库运维知识 | 9 | 24K | MySQL完整运维体系 |
| 14 | 运维方向知识库 | 12 | 6K | Docker、Nginx、WSL2 |
| 15 | 运维技术v2 | 7 | 9K | iptables、脚本、代理 |
| 16 | 分布式 | 22 | 71K | 分布式全栈技术 |
| 17 | linux学习笔记 | 131 | 271K | K8S、Jenkins、Prometheus |
| 18 | 知识点 | 85 | 437K | 运维全栈、面试准备 |
| 19 | Prometheus详解 | 1 | - | Prometheus完整教程 |
| 20 | 云原生 | 61 | 549K | Helm、client-go源码 |
| 21 | 项目知识库 | 21 | 95K | 19个运维项目实战 |
| 22 | 运维相关(星弈) | 304 | 534K | 数据库、WEB服务、自动化 |
| 23 | 运维知识库(鱼岸) | 31 | 10K | WebLogic、Oracle、Linux |
| 24 | 技术沙龙 | 124 | 276K | 云运维、AIOps、安全 |
| 25 | 云原生(K8S+Devops) | - | - | K8S日常问题、GPU支持 |

**总计**: 约 2,879 篇文档，约 590 万字

---

## 核心技术主题覆盖

### 🐧 Linux运维
- 系统管理：SSH/磁盘/定时任务/进程管理/内核调优
- 发行版：CentOS/Ubuntu/Debian
- 安全：iptables/SSL证书/漏洞修复/堡垒机

### 🐳 Docker & 容器
- Docker基础：镜像/容器/网络/存储/Dockerfile
- Docker Compose编排
- Harbor镜像仓库
- LXC容器

### ☸️ Kubernetes
- 核心概念：Pod/Service/Deployment/StatefulSet/DaemonSet
- 配置管理：ConfigMap/Secret/ServiceAccount
- 安全：RBAC/Security Context/Pod安全策略
- 网络：Flannel/Calico/NetworkPolicy/Ingress(Traefik)
- 存储：PV/PVC/StorageClass
- 高可用：多Master/HAProxy+Keepalived
- 开发：client-go/Helm

### 📊 监控体系
- Prometheus + Grafana
- Zabbix
- ELK日志系统
- Pinpoint全链路监控
- 阿里云云监控

### 🗄️ 数据库
- MySQL：安装/主从/MGR集群/调优/备份
- Redis：集群/主从/应用场景
- MongoDB：副本集/认证部署
- Oracle：PDB/DBLink/备份/参数管理

### 🔄 CI/CD & 自动化
- Jenkins安装配置与CICD
- Git/GitLab
- Ansible
- SaltStack

### 🏗️ 分布式系统
- 分布式事务/锁/缓存/限流/幂等/全局ID
- 微服务：Nacos/Seata/Sentinel/SpringCloud Gateway
- 消息中间件：Kafka/RabbitMQ/RocketMQ

### ☁️ 云原生 & 云服务
- OpenStack
- Ceph分布式存储
- 阿里云ECS/CDN/WAF/云监控
- 智能运维(AIOps)
