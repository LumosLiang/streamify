# Azure setup（最小基础设施版本）

本次只把 GCP IaC 换成 Azure，并更新本地 Azure SDK/Kafka Python 依赖。
原来的 Airflow、Kafka、Eventsim、Spark 业务脚本和 dbt 配置保持原样，
它们仍有 GCP 依赖，不能当作已经迁移完成的 Azure 流水线直接启动。
服务部署、Airflow/dbt 大版本升级、Snowflake 接入需要后续单独确认。

## 1. Account 和 access setup

1. 在 Visual Studio Benefits 中激活 Azure 月度额度（已激活则跳过）。
2. 在 Azure Portal → Subscriptions 中找到额度订阅，确认状态为 Enabled，记录 Subscription ID。
3. 在订阅 → Access control (IAM) → View my access 查看权限。
   当前 Terraform 既创建资源，也分配 VM 的存储权限。Owner 可以执行；
   仅 Contributor 不够，还需相应的角色分配权限，由订阅管理员授权。
4. 在 Mac 上通过 Azure CLI 登录。Terraform 使用你的登录身份，无需新建服务账号或下载密钥。

```bash
brew install azure-cli
az login
az account list --output table
az account set --subscription "你的订阅ID"
az account show --output table
```

身份分两类：你的账号用于 Terraform 部署；VM Managed Identity 用于程序访问 ADLS。
Terraform 会创建 VM 身份并授予 Spark 读写、Airflow 只读权限，不必提前手动创建。
程序使用该身份的连接配置尚待后续适配。Snowflake 的 Storage Integration、
Azure 授权及 Snowflake 用户/角色也留待后续配置。

AzureRM 会尝试注册常用 Resource Providers（类似 GCP 启用 API）；如遇未注册错误，
在订阅的 Resource providers 页面检查对应服务。默认五台 VM 合计需要 12 vCPU，
部署前可在订阅 Quotas 中确认新加坡区域总额度至少 12 vCPU，Dasv5 系列至少 10 vCPU、Easv5 系列至少 2 vCPU。

## 2. Terraform setup

在你的 Mac 安装，不在云 VM 安装：

```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
terraform version
```

当前要求 Terraform >= 1.16.1 且 < 2.0；AzureRM provider 锁定 5.4.0。
`.terraform.lock.hcl` 保存插件版本及校验值；`.terraform/` 是自动下载的缓存。

在项目根目录执行：

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

填写订阅 ID、全球唯一存储账号名、新加坡出口公网 IP（加 `/32`）及 SSH 公钥路径。
已有 SSH 公钥可以复用；没有时运行 `ssh-keygen -t ed25519`，不要覆盖已有密钥。
然后执行：

```bash
terraform init
terraform validate
terraform plan
```

`init` 下载插件；`validate` 检查配置；`plan` 预览资源变化。
只有你决定实际创建资源时，才执行 `terraform apply`。本次未部署任何云资源。

Azure 使用本地 `azure.tfstate`，与原 GCP 的 `terraform.tfstate` 分开。
如果此前初始化过 GCP backend，运行 `terraform init -reconfigure`，不要迁移 GCP state。
已有 GCP 资源仍需使用原 GCP 配置及其 state 管理。

## 3. 创建什么

| 原 GCP 资源 | Azure 对应 |
| --- | --- |
| Kafka VM | 1 台 D4as v5：4 核、16 GiB |
| Airflow VM | 1 台 E2as v5：2 核、16 GiB |
| Dataproc：1 Master + 2 Workers | 3 台 D2as v5：每台 2 核、8 GiB，后续自行安装 Spark |
| GCS bucket | 1 个 ADLS Gen2 Storage Account + `streamify` 容器 |
| BigQuery STG / PROD | 本次不创建；后续在现有 AWS Snowflake 中配置 |

每台 VM 使用 Ubuntu 24.04、32 GiB Standard SSD 系统盘。
Azure 还需要 Resource Group、VNet、Subnet 和 NIC；共享这些网络定义，
用一个简单的 VM 名称/规格表和 `for_each` 创建五台，避免复制五份配置。

每台 VM 的公网 IP 用于 SSH 和出站下载；SSH 只允许你填写的公网出口 IP。
Kafka/Spark 跨 VM 通信应使用各 VM 的私网 IP，可在 Portal 中查看。
容器、应用、数据源不自动启动。没有自动关机、Docker 初始化模板或额外托管服务。

数据湖与原 bucket 一样使用一个容器，后续可按以下路径组织：

- 数据：`abfss://streamify@<账号名>.dfs.core.windows.net/<事件类型>/`
- Checkpoint：`abfss://streamify@<账号名>.dfs.core.windows.net/checkpoint/<事件类型>/`
- Snowflake Stage：`azure://<账号名>.blob.core.windows.net/streamify/`

不沿用原来的全桶 30 天删除规则，以免删掉正在使用的 checkpoint；生命周期规则另行确认。

## 4. 实验结束

在 Portal 对五台 VM 分别执行 Stop，确认状态为 **Stopped (deallocated)**。
也可以逐台执行，例如：

```bash
az vm deallocate --resource-group streamify-rg --name streamify-kafka
```

本版本没有自动关机。解除分配停止计算计费，磁盘、公网 IP 和 ADLS 仍计费。
删除 VM/资源组则会失去相关数据；不要把删除资源当作日常关机。

参考：
- Azure CLI：https://learn.microsoft.com/cli/azure/install-azure-cli-macos
- Terraform：https://developer.hashicorp.com/terraform/install
- Azure CLI 认证：https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/guides/azure_cli
- Managed Identity：https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/overview
