## 在 Azure VM 上搭建 Spark Standalone 集群

[English](spark.en.md)

![spark](../images/spark.jpg)

这里不是 Dataproc、EMR 或 HDInsight。Terraform 创建的是三台普通 Azure VM：一台
Spark master 和两台 worker。Spark 使用 standalone 模式，Kafka 仍运行在独立的 Kafka VM
上，Spark 通过 Kafka VM 的私网地址访问 `9092`。

Terraform 只创建基础设施，不会自动安装或启动 Spark。先完成 [Terraform 部署](terraform.md)、
[SSH 配置](ssh.md) 和 [Kafka 部署](kafka.md)。

### 1. 在三台 VM 安装 Spark

在 master、worker-1、worker-2 上分别执行：
  
```bash
bash scripts/spark_setup.sh
```

脚本安装 Java 17 和 Spark 4.2.0，并把环境变量写入 `~/.bashrc`。如果使用 Git 获取项目，
应在三台 VM 上都执行；本地未提交的修改不会自动出现在 VM 上。

Spark 4.2 使用 Scala 2.13，因此 Kafka connector 必须使用 `_2.13` 构件，不能继续使用
Spark 3.x 的 `_2.12` 构件。Spark 4.2 还要求 Python 3.10 或更高版本；Ubuntu 24.04
自带的 Python 版本满足这一要求。

### 2. 启动 master 和 workers

先在 master 上查询私网 IP：

```bash
hostname -I
```

在 master 上启动 standalone master：

```bash
source ~/.spark_env
"${SPARK_HOME}/sbin/start-master.sh"
```

在两个 worker 上执行下面命令，把地址替换为 master 的私网 IP：

```bash
source ~/.spark_env
"${SPARK_HOME}/sbin/start-worker.sh" spark://<spark-master-private-ip>:7077
```

回到 master 检查集群：

```bash
jps
curl http://localhost:8080
```

Spark Web UI 默认监听 master 的 `8080`；通过 SSH 转发到本机 `8082` 的方法见 [SSH 配置](ssh.md)。

### 3. 安装后验证

先在三台 VM 上分别确认版本。三台输出中的 Java 主版本应为 `17`，Spark 版本应为 `4.2.0`：

```bash
java -version
"${SPARK_HOME}/bin/spark-submit" --version
```

在 master 上确认两个 worker 已注册并处于 `ALIVE` 状态：

```bash
curl -fsS http://localhost:8080/json/ | python3 -c \
  'import json, sys; data=json.load(sys.stdin); workers=data["workers"]; assert len(workers) == 2 and all(worker["state"] == "ALIVE" for worker in workers); print("Spark master-worker validation passed")'
```

这个检查失败时，先在 worker 上执行 `jps`，再查看 worker 日志目录中的最新日志：

```bash
jps
ls -lt "${SPARK_HOME}/work" | head
```

然后在 master 上检查 Kafka 的 TCP 端口：

```bash
nc -vz -w 5 "${KAFKA_ADDRESS}" 9092
```

最后运行 Kafka smoke test。它会通过 standalone master 调度一个 Spark 作业，并使用
Kafka connector 获取 topic metadata；因此比单纯的 `nc` 更能证明 master、worker、connector
和 Kafka 之间的链路正常：

```bash
spark-submit \
  --master "${SPARK_MASTER_URL}" \
  --packages org.apache.spark:spark-sql-kafka-0-10_2.13:4.2.0 \
  validate_kafka.py
```

成功时应看到 `Kafka metadata validation passed`。如果出现 `ClassNotFoundException`，通常是
connector 坐标或 Scala 后缀错误；如果出现 `Connection refused`，检查 Kafka 的私网地址、
Broker 状态和 `9092` 监听配置。

### 4. 配置 Spark、Kafka 和 ADLS

在 master 上进入项目的 `spark_streaming` 目录并设置：

```bash
cd ~/streamify/spark_streaming
export SPARK_MASTER_URL="spark://<spark-master-private-ip>:7077"
export KAFKA_ADDRESS="<kafka-private-ip>"
export AZURE_STORAGE_ACCOUNT="<storage-account-name>"
export AZURE_STORAGE_CONTAINER="streamify"
```

`KAFKA_ADDRESS` 必须是 Kafka VM 的私网 IP，不是公网 IP。Kafka 的 `9092` 只需允许 Azure
私网内的 VM 访问；当前 NSG 的默认规则已经允许同一 VNet 的私网流量。

Spark VM 的 system-assigned managed identity 已由 Terraform 授予该容器的
`Storage Blob Data Contributor` 权限，因此不需要下载 Azure 密钥。Spark 会通过 ABFS OAuth
和 VM managed identity 写入 ADLS Gen2。

### 5. 提交流处理作业

只在 master 上运行：

```bash
spark-submit \
  --master "${SPARK_MASTER_URL}" \
  --packages org.apache.spark:spark-sql-kafka-0-10_2.13:4.2.0 \
  stream_all_events.py
```

正常运行后，ADLS 容器中会每两分钟为每个 topic 写入 Parquet 文件和 checkpoint。
路径形如：

```text
abfss://streamify@<storage-account-name>.dfs.core.windows.net/listen_events/
abfss://streamify@<storage-account-name>.dfs.core.windows.net/checkpoint/listen_events/
```

### 6. 停止集群

在 master 上停止 master，在每个 worker 上停止 worker：

```bash
"${SPARK_HOME}/sbin/stop-master.sh"
"${SPARK_HOME}/sbin/stop-worker.sh"
```

读取的 Kafka topics：`listen_events`、`page_view_events`、`auth_events`。