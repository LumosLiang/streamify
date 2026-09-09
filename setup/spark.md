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

脚本安装 Java 11 和 Spark 3.5.6，并把环境变量写入 `~/.bashrc`。如果使用 Git 获取项目，
应在三台 VM 上都执行；本地未提交的修改不会自动出现在 VM 上。

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

### 3. 配置 Spark、Kafka 和 ADLS

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

### 4. 提交流处理作业

只在 master 上运行：

```bash
spark-submit \
  --master "${SPARK_MASTER_URL}" \
  --packages org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.6 \
  stream_all_events.py
  ```

正常运行后，ADLS 容器中会每两分钟为每个 topic 写入 Parquet 文件和 checkpoint。
路径形如：

```text
abfss://streamify@<storage-account-name>.dfs.core.windows.net/listen_events/
abfss://streamify@<storage-account-name>.dfs.core.windows.net/checkpoint/listen_events/
```

### 5. 停止集群

在 master 上停止 master，在每个 worker 上停止 worker：

```bash
"${SPARK_HOME}/sbin/stop-master.sh"
"${SPARK_HOME}/sbin/stop-worker.sh"
```

读取的 Kafka topics：`listen_events`、`page_view_events`、`auth_events`。