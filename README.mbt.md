# EdgeWeaver

弱网边缘设备自治平台。当前版本提供节点端与控制面的共享领域模型，以及面向 Linux native 用户态进程的运行档案。

## 首期决策

- **语言与后端：** 使用 MoonBit，首期选择 `native` 后端，面向需要访问本地文件系统和网络的边缘节点进程。
- **部署类别：** 首期以标准 Linux 用户态设备为目标；具体发行版、CPU 架构和硬件型号待目标设备确认后验证。裸机 MCU、Windows 服务和浏览器/Wasm 部署不在当前范围。
- **运行角色：** `node` 用于边缘节点，`control-plane` 用于控制面；两者使用独立的数据、配置、事件日志和诊断目录。
- **仓库远端：** [GitHub](https://github.com/zyyaa125/EdgeWeaver)。
- **许可证：** MIT，详见 [`LICENSE`](LICENSE)。

## 部署运行档案

`deploy.mbt` 定义了两个角色的默认运行档案和启动参数解析：

- `node`：默认写入 `/var/lib/edgeweaver/node`，配置为 `/etc/edgeweaver/node.toml`，允许有限的事件、日志和重连预算。
- `control-plane`：默认写入 `/var/lib/edgeweaver/control-plane`，配置为 `/etc/edgeweaver/control-plane.toml`，使用更大的事件和日志预算。

配置样例见 [`deploy/`](deploy/README.md)。启动参数约定为 `--profile node|control-plane`、`--data-dir <path>` 和 `--config <path>`，由 `LaunchOptions::parse` 解析并由 `RunProfile::validate` 校验。

本阶段不包含 systemd/Kubernetes 编排、远程配置下发、TLS 凭证管理或真实进程守护；这些能力在运行档案稳定后再接入。

弱网运行、离线自治、重连退避、事件回放和恢复验收步骤见 [`docs/weak-network-operations.md`](docs/weak-network-operations.md)。

## 目录职责

- `edgeweaver.mbt`、`moon.pkg`：根 package，后续放置跨模块共享的领域类型与接口。
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
moon fmt
moon check --deny-warn
moon test
moon run cmd/main
```

其中 `moon run cmd/main` 会输出已登记节点、确认回放的事件数和剩余待处理事件数，用于快速验证节点到控制面的本地同步路径。

每次推送和 Pull Request 都会触发 GitHub Actions，使用 MoonBit `latest` 工具链运行同一组格式、检查、构建和测试命令。

后续增加行为时，为相关 package 增加针对性测试；修改公开 API 时运行 `moon info` 并审阅生成的接口摘要。
