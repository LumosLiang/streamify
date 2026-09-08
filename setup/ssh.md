# Azure VM SSH Setup

根据 2026-09-08 的 Azure 实际查询生成：资源组 `STREAMIFY-RG`，
五台 VM 均为 Running，管理员用户名均为 `streamify`。
本地公钥路径为 `~/.ssh/id_ed25519.pub`，登录时使用对应的私钥
`~/.ssh/id_ed25519`。Terraform 已将公钥配置到 VM，无需重新生成或上传。

## 1. 在 Mac 配置 SSH 别名

打开 `~/.ssh/config`（没有该文件则新建），加入以下内容。
如果已有同名 Host，请替换对应条目，不要重复添加或覆盖其他主机配置。

```sshconfig
Host streamify-kafka
    HostName 40.65.148.236
    User streamify
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes

Host streamify-airflow
    HostName 4.193.148.173
    User streamify
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes

Host streamify-spark streamify-spark-master
    HostName 4.194.184.65
    User streamify
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes

Host streamify-spark-worker-1
    HostName 13.67.67.201
    User streamify
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes

Host streamify-spark-worker-2
    HostName 168.63.248.168
    User streamify
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
```

设置文件权限：

```zsh
chmod 700 ~/.ssh
chmod 600 ~/.ssh/config ~/.ssh/id_ed25519
```

`IdentityFile` 是私钥路径，不要填 `.pub` 文件。

## 2. 登录 VM

在 Mac 终端中执行，例如：

```zsh
ssh streamify-kafka
ssh streamify-airflow
ssh streamify-spark
ssh streamify-spark-worker-1
ssh streamify-spark-worker-2
```

每次选一条执行；进入 VM 后用 `exit` 回到 Mac。
`streamify-spark` 和 `streamify-spark-master` 是同一台机器的两个别名。
首次连接时核对主机指纹再接受；不要禁用 SSH 主机校验。

当前 NSG 只允许 `81.28.13.195/32` 通过 SSH 连接（来自本地 Terraform 参数）。
连接时使用同一新加坡网络出口。若出口 IP 变化，需要更新
`terraform.tfvars` 中的 `admin_source_cidr`，检查 plan 后再 apply。

## 3. 通过 SSH 访问 Web UI

这些命令在 **Mac** 上执行，保持终端打开，然后用浏览器访问 localhost。
只有在对应 VM 上安装并启动服务后，UI 才会有响应；VM Running 不代表应用已启动。
无需把 Web UI 端口开放到公网。

Airflow：

```zsh
ssh -N -o ExitOnForwardFailure=yes -L 127.0.0.1:8080:127.0.0.1:8080 streamify-airflow
```

浏览器访问 `http://localhost:8080`。

Spark Master（本机用 8082，避免与 Airflow 的 8080 冲突）：

```zsh
ssh -N -o ExitOnForwardFailure=yes -L 127.0.0.1:8082:127.0.0.1:8080 streamify-spark
```

浏览器访问 `http://localhost:8082`。

原项目的 Kafka Control Center（后续仍采用原 Compose 时）：

```zsh
ssh -N -o ExitOnForwardFailure=yes -L 127.0.0.1:9021:127.0.0.1:9021 streamify-kafka
```

浏览器访问 `http://localhost:9021`。Kafka Broker 的 9092 是消息通信端口，不是网页。
`Ctrl+C` 结束端口转发。

## 4. 公网和私网地址的区别

| VM | 公网 IP：Mac SSH 使用 | 私网 IP：VM 间通信使用 |
| --- | --- | --- |
| Kafka | 40.65.148.236 | 10.42.1.7 |
| Airflow | 4.193.148.173 | 10.42.1.5 |
| Spark Master | 4.194.184.65 | 10.42.1.4 |
| Spark Worker 1 | 13.67.67.201 | 10.42.1.8 |
| Spark Worker 2 | 168.63.248.168 | 10.42.1.6 |

例如 Spark 连接 Kafka 应使用 `10.42.1.7:9092`。
这些公网 IP 资源在 Terraform 中设为 Static；保留资源时普通重启/解除分配
不会更换公网 IP，删除并重建公网 IP 资源则可能变化。地址变化后再更新 SSH 配置。

需要重新查看时，在 Mac 执行：

```zsh
az vm list -d --resource-group STREAMIFY-RG \
  --query '[].{Name:name,PublicIP:publicIps,PrivateIP:privateIps,State:powerState}' \
  --output table
```

本次只读取 Azure 信息并生成文档，未修改本机 SSH 配置，也未登录 VM 或启动服务。
