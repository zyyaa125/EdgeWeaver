# EdgeWeaver

弱网边缘设备自治平台。项目计划见 [PLAN.md](PLAN.md)。当前提交只建立 MoonBit 模块和最小可运行入口，尚未实现设备管理或联网功能。

## 首期决策

- **语言与后端：** 使用 MoonBit，首期选择 `native` 后端，面向需要访问本地文件系统和网络的边缘节点进程。
- **部署类别：** 首期以标准 Linux 用户态设备为目标；具体发行版、CPU 架构和硬件型号待目标设备确认后验证。裸机 MCU、Windows 服务和浏览器/Wasm 部署不在当前范围。
- **仓库远端：** 尚未配置；本地提交不依赖 GitHub 凭证。
- **许可证：** 尚未决定，因此暂不声明许可证。

## 目录职责

- `edgeweaver.mbt`、`moon.pkg`：根 package，后续放置跨模块共享的领域类型与接口。
- `cmd/main/`：命令行程序入口；当前仅用于验证构建链路。
- `moon.mod`：模块名称、版本、首选目标后端和项目元数据。
- `AGENTS.md`：本仓库的代码组织、变更范围和验证约定。
- `PLAN.md`：分阶段交付路线与提交里程碑。

## 开发

需要已安装 MoonBit 工具链。常用命令：

```sh
moon fmt
moon check --deny-warn
moon run cmd/main
```

后续增加行为时，为相关 package 增加针对性测试；修改公开 API 时运行 `moon info` 并审阅生成的接口摘要。
