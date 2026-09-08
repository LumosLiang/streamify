# Kafka + Eventsim on Azure

Kafka 和 Eventsim 仍运行在同一台 VM 的独立容器中。
保留原 Confluent 5.4.0 / ZooKeeper 架构、镜像版本及原有数据卷设置。
本次只适配私网地址、Eventsim 堆内存以及 Ubuntu 24.04 安装/启动步骤。

## 1. 登录并准备项目

在 Mac 上运行：

```zsh
ssh streamify-kafka
```

将包含本次修改的项目放到 VM。后续命令在 **VM** 上、项目根目录执行。
如果用 Git 获取项目，应先确保远端分支包含这些修改；本地未提交的修改不会自动出现在 VM。
项目不必放在 `~/streamify`，启动脚本会根据自身位置找到 Eventsim。

## 2. 安装 Docker 和 Compose

```bash
bash scripts/vm_setup.sh
```

该脚本使用 Docker 官方 Ubuntu 软件源安装 Docker Engine 和 Compose 插件，
不再安装 Anaconda、旧版独立 Compose 或创建 GCP 凭据目录。
安装完成后执行 `exit`，从 Mac 重新 SSH 登录，使 Docker 用户组权限生效。
返回 VM 上的项目根目录，检查：

```bash
docker --version
docker compose version
```

## 3. 启动 Kafka

```bash
export KAFKA_ADDRESS=10.42.1.7
docker compose -f kafka/docker-compose.yml up -d
docker compose -f kafka/docker-compose.yml ps
```

`10.42.1.7` 是 2026-09-08 查询到的 Kafka VM **私网 IP**。
重建 VM 后请重新核对；每次新终端运行 Compose 前都要设置该环境变量。
Compose 现在要求明确设置地址，避免默认 localhost 导致另一台 VM 上的 Spark 连接失败。

`KAFKA_ADVERTISED_LISTENERS` 会把这个地址告知客户端。
Docker 内部组件仍使用 `broker:29092`；Spark 使用 `10.42.1.7:9092`。

等待 Broker 就绪，可用下面的命令验证；如果失败，先查看容器日志：

```bash
docker compose -f kafka/docker-compose.yml exec broker \
  kafka-topics --bootstrap-server broker:29092 --list
```

Kafka Control Center 的 SSH 转发和访问方式见 [SSH setup](ssh.md)。

## 4. 启动 Eventsim

在 VM 的项目根目录执行：

```bash
bash scripts/eventsim_startup.sh
docker logs --follow million_events
```

Eventsim 使用 host 网络，因此连接同机的 `localhost:9092` 保持不变。
Java 堆上限从 8 GB 改为 4 GB；容器内存上限仍为 5.5 GB，给非堆内存留空间。
原有 100 万用户、持续生成 24 小时等参数保持不变。

脚本用于首次创建容器；如果 `million_events` 已存在，不要重复执行创建命令。
查看现有容器状态：`docker ps -a --filter name=million_events`。
已停止的原容器可用 `docker start million_events` 启动（仍沿用其创建时的参数和镜像）。

启动后应能看到四个 Topic：`listen_events`、`page_view_events`、`auth_events`、`status_change_events`。

安装参考：https://docs.docker.com/engine/install/ubuntu/
