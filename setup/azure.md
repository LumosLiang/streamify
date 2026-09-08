# Azure 账号与权限

中文 | [English](azure.en.md)

先准备一个可用的 Azure 订阅。如果使用 Visual Studio 月度额度，确认额度已激活。项目默认区域为新加坡，目标数仓为 AWS 上的 Snowflake。

## 1. 确认订阅

1. 在 [Visual Studio Benefits](https://my.visualstudio.com/benefits) 激活 Azure 月度额度；已激活则跳过。
2. 打开 [Azure Portal](https://portal.azure.com)，进入 **Subscriptions**，找到额度订阅。
3. 确认状态为 **Enabled**，记录 **Subscription ID**。

## 2. 确认部署权限

在订阅的 **Access control (IAM) → View my access** 中查看自己的角色。

Terraform 需要创建资源，也需要给 VM 分配存储访问权限。**Owner** 可以执行这些操作；只有 **Contributor** 时，还需要管理员授予相应的角色分配权限。

在 **Quotas** 中确认新加坡区域至少有 12 vCPU 额度，其中 Dasv5 系列需要 10 vCPU，Easv5 系列需要 2 vCPU。

AzureRM 会尝试注册常用 Resource Providers，作用类似 GCP 的启用 API。遇到未注册的报错时，在订阅的 **Resource providers** 页面检查对应服务。

## 3. 在 Mac 安装 Azure CLI

安装 Azure CLI：

```bash
brew install azure-cli
```

接下来按 Terraform 文档中的 [Azure 登录](terraform.md#azure-login) 选择订阅。VM 和 Snowflake 的权限说明统一放在 [运行身份与权限](terraform.md#runtime-identities)。

## 参考

- [Azure CLI 安装](https://learn.microsoft.com/cli/azure/install-azure-cli-macos)
