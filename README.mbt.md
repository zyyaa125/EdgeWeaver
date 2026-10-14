# EdgeWeaver

EdgeWeaver 是面向弱网边缘设备的 MoonBit 自治核心库与平台原型。当前版本提供节点端与控制面的共享领域模型，以及面向 Linux native 用户态进程的运行档案。

## 当前交付边界

核心库包含登记、心跳、配置与命令模型、有界事件队列、checkpoint/restore、幂等回放、重连退避、白名单执行和离线策略预算。`cmd/main` 是同进程模拟示例，发送结果由回调模拟；运行档案只约定参数和资源限制。真实云边网络服务、checkpoint 磁盘序列化与重启加载、设备驱动、TLS 凭证和进程编排仍需部署适配器实现。

[KubeEdge](https://kubeedge.io/docs/) 基于 Kubernetes，已有容器编排、设备管理、云边同步和边缘自治能力。EdgeWeaver 聚焦无 Kubernetes 前置的 MoonBit 弱网状态与安全执行规则，提供可组合、可测试的核心库；两者功能有交集，当前原型不承担 KubeEdge 的平台功能。

## 首期决策

- **语言与后端：** 使用 MoonBit，首期选择 `native` 后端，面向需要访问本地文件系统和网络的边缘节点进程。
- **部署类别：** 首期以标准 Linux 用户态设备为目标；具体发行版、CPU 架构和硬件型号待目标设备确认后验证。裸机 MCU、Windows 服务和浏览器/Wasm 部署不在当前范围。
- **运行角色：** `node` 用于边缘节点，`control-plane` 用于控制面；两者使用独立的数据、配置、事件日志和诊断目录。
- **仓库远端：** [GitHub](https://github.com/zyyaa125/EdgeWeaver)。
- **许可证：** MIT，详见 [`LICENSE`](LICENSE)。

## 部署运行档案

`deploy.mbt` 定义了两个角色的默认运行档案和启动参数解析：

- `node`：默认数据目录为 `/var/lib/edgeweaver/node`，配置路径为 `/etc/edgeweaver/node.toml`，允许有限的事件、日志和重连预算。
- `control-plane`：默认数据目录为 `/var/lib/edgeweaver/control-plane`，配置路径为 `/etc/edgeweaver/control-plane.toml`，使用更大的事件和日志预算。

配置样例见 [`deploy/`](deploy/README.md)。启动参数约定为 `--profile node|control-plane`、`--data-dir <path>` 和 `--config <path>`，由 `LaunchOptions::parse` 解析并由 `RunProfile::validate` 校验。

本阶段不包含 systemd/Kubernetes 编排、真实网络配置下发、TLS 凭证管理或进程守护；这些能力在运行档案稳定后再接入。

弱网运行、离线自治、重连退避、事件回放和恢复验收步骤见 [`docs/weak-network-operations.md`](docs/weak-network-operations.md)。

## 目录职责

- `edgeweaver.mbt`、`moon.pkg`：根 package，承载共享领域类型与接口。
- `cmd/main/`：命令行程序入口，提供节点登记、心跳、事件入队、能力握手和回放的最小闭环示例。
- `deploy.mbt`：节点端与控制面运行档案、资源边界和启动参数解析。
- `deploy/`：部署说明与不含凭证的配置样例。
- `.github/workflows/ci.yml`：GitHub Actions 格式、检查、构建和测试流程。
- `LICENSE`：MIT 开源许可证文本。
- `moon.mod`：模块名称、版本、首选目标后端和项目元数据。
- `AGENTS.md`：本仓库的代码组织、变更范围和验证约定。

## 开发

需要已安装 MoonBit 工具链。常用命令：

```sh
moon fmt --check
moon check --deny-warn
moon test --deny-warn
moon run cmd/main
```

预期 52 项测试通过；`moon run cmd/main` 应输出 `acknowledged events: 1` 和 `pending events: 0`，验证模拟的节点登记、心跳与事件回放路径。队列满载、恢复去重、握手拒绝和离线预算分别由 `store_test.mbt`、`sync_test.mbt`、`transport_test.mbt` 和 `policy_test.mbt` 覆盖。

每次推送和 Pull Request 都会触发 GitHub Actions，使用 MoonBit `latest` 工具链运行同一组格式、检查、构建和测试命令。

后续增加行为时，为相关 package 增加针对性测试；修改公开 API 时运行 `moon info` 并审阅生成的接口摘要。
