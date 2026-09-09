# Set Up a Spark Standalone Cluster on Azure VMs

[中文](spark.md) | English

![spark](../images/spark.jpg)

This project does not use Dataproc, EMR, or HDInsight. Terraform creates three ordinary Azure VMs for Spark: one master and two workers. Spark runs in standalone mode. Kafka runs on a separate VM, and Spark accesses it through the Kafka VM's private address on port `9092`.

Terraform creates the infrastructure only. It does not install or start Spark. Complete the [Terraform deployment](terraform.en.md), [SSH setup](ssh.en.md), and [Kafka deployment](kafka.en.md) first.

## 1. Install Spark on all three VMs

Run the following commands separately on the master, worker-1, and worker-2:

```bash
ssh spark-master-vm
bash scripts/spark_setup.sh
```

The script installs Java 17 and Spark 4.2.0, then writes the environment variables to `~/.bashrc`. If you clone the repository, run this on all three VMs. Uncommitted local changes are not copied automatically.

Spark 4.2 is built for Scala 2.13, so the Kafka connector must use the `_2.13` artifact. Do not use the `_2.12` artifact from Spark 3.x. Spark 4.2 also requires Python 3.10 or newer; Ubuntu 24.04 provides a compatible Python version.

## 2. Start the master and workers

First, find the master's private IP:

```bash
hostname -I
```

On the master, start the standalone master:

```bash
source ~/.spark_env
"${SPARK_HOME}/sbin/start-master.sh"
```

On each worker, replace the placeholder with the master's private IP:

```bash
source ~/.spark_env
"${SPARK_HOME}/sbin/start-worker.sh" spark://<spark-master-private-ip>:7077
```

Return to the master and check the cluster:

```bash
jps
curl http://localhost:8080
```

The Spark Web UI listens on the master's port `8080` by default. See the [SSH guide](ssh.en.md) for forwarding it to local port `8082`.

## 3. Validate the installation

Check the versions separately on all three VMs. The Java major version should be `17` and the
Spark version should be `4.2.0` on every node:

```bash
java -version
"${SPARK_HOME}/bin/spark-submit" --version
```

On the master, verify that both workers are registered and `ALIVE`:

```bash
curl -fsS http://localhost:8080/json/ | python3 -c \
  'import json, sys; data=json.load(sys.stdin); workers=data["workers"]; assert len(workers) == 2 and all(worker["state"] == "ALIVE" for worker in workers); print("Spark master-worker validation passed")'
```

If this check fails, run `jps` on each worker and inspect the newest worker log:

```bash
jps
ls -lt "${SPARK_HOME}/work" | head
```

From the master, check that the Kafka private address accepts TCP connections:

```bash
nc -vz -w 5 "${KAFKA_ADDRESS}" 9092
```

Then run the Kafka smoke test. It submits a Spark job through the standalone master and uses the
Kafka connector to fetch topic metadata, validating the master-to-worker and master-to-Kafka paths
together:

```bash
spark-submit \
  --master "${SPARK_MASTER_URL}" \
  --packages org.apache.spark:spark-sql-kafka-0-10_2.13:4.2.0 \
  validate_kafka.py
```

The command should print `Kafka metadata validation passed`. A `ClassNotFoundException` usually
means the connector coordinate or Scala suffix is wrong. A `Connection refused` error means that
the Kafka private address, broker status, or port `9092` listener needs checking.

## 4. Configure Spark, Kafka, and ADLS

On the master, change to the `spark_streaming` directory and set these variables:

```bash
cd ~/streamify/spark_streaming
export SPARK_MASTER_URL="spark://<spark-master-private-ip>:7077"
export KAFKA_ADDRESS="<kafka-private-ip>"
export AZURE_STORAGE_ACCOUNT="<storage-account-name>"
export AZURE_STORAGE_CONTAINER="streamify"
```

`KAFKA_ADDRESS` must be the Kafka VM's private IP, not its public IP. Kafka port `9092` only needs to be reachable from VMs in the Azure VNet. The current NSG default rules allow traffic between resources in the same VNet.

Terraform grants each Spark VM's system-assigned managed identity the `Storage Blob Data Contributor` role on the `streamify` container. Do not download or store an Azure key. Spark uses ABFS OAuth with the VM managed identity to write to ADLS Gen2.

## 5. Submit the streaming job

Run this only on the master:

```bash
spark-submit \
  --master "${SPARK_MASTER_URL}" \
  --packages org.apache.spark:spark-sql-kafka-0-10_2.13:4.2.0 \
  stream_all_events.py
```

When the job is running, it writes Parquet files and checkpoints for each topic every two minutes. The paths look like this:

```text
abfss://streamify@<storage-account-name>.dfs.core.windows.net/listen_events/
abfss://streamify@<storage-account-name>.dfs.core.windows.net/checkpoint/listen_events/
```

## 6. Stop the cluster

On the master, stop the master process. On each worker, stop its worker process:

```bash
"${SPARK_HOME}/sbin/stop-master.sh"
"${SPARK_HOME}/sbin/stop-worker.sh"
```

The job reads these Kafka topics: `listen_events`, `page_view_events`, and `auth_events`.
