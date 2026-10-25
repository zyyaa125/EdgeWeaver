# EdgeWeaver 实施进度

路线来源：仓库根目录 `任务说明.md`。每个里程碑单独提交；M6 的本机部署验收已独立完成，P0 未通过的项目仍保留为缺口。状态以本文件和可复现命令为准。

| 里程碑 | 状态 | 依赖与交付范围 | 文件、测试与验收 |
| --- | --- | --- | --- |
| M0 审计 | 已完成 | 核对基线和能力边界 | `docs/implementation-audit.md`、本文件；52 项测试、格式、检查、构建、两个 CLI 路径实跑。 |
| M1 持久化与同步 | 核心加固与收据冲突拒绝完成；掉电边界未验收 | 依赖 M0；严格顺序与消息校验、游标不得跳过待确认事件、序号溢出拒绝；格式 2 收据比对完整信封 | `store.mbt`、`sync.mbt`、`disk/`、相关测试、恢复文档；截断/缺字段/版本/冲突/旧格式拒绝，跨进程回放实测。 |
| M2 传输与 Schema | 已完成 | 依赖 M1；可注入连接/关闭/握手/发送、七类版本化 wire 消息 | `transport_adapter.mbt`、`protocol_wire.mbt`、相关测试、`docs/protocol-wire.md`；模拟超时/错位/重复响应及版本拒绝。真实网络属 M3。 |
| M3 本地网络 | loopback 闭环完成；安全/服务限制保留 | 依赖 M2；节点与控制面两个进程、控制端磁盘收据后确认 | `network/`、`cmd/netdemo/`、socket 测试及 `docs/network-loopback.md`；实测断连后首次确认、节点/控制端重启后去重。仅本机单写者，远程 TLS 服务未交付。 |
| M4 安全命令与策略 | 核心安全与磁盘恢复完成；真实运行器待实施 | 依赖 M1/M3；执行前/后持久状态、失败默认拒绝、预算不变量 | `edge.mbt`、`command.mbt`、`policy.mbt`、`disk/safety.mbt`、`cmd/safety/`、相关测试；跨进程未知执行结果不重试。真实动作超时/权限隔离未验收。 |
| M5 故障验收 | 部分通过 | 依赖 M1–M4；十二类验收场景逐项报告，CI 增加跨进程磁盘恢复 | `docs/acceptance-report.md`、CI；多事件及 Linux 本机服务重启已验证；真实运行器、掉电与远端部署未通过，故 P0 未宣布完成。 |
| M6 诊断与 Linux 部署 | 本机范围已验收；远端/生产边界保留 | JSON 诊断、Linux 本机双角色服务、配置与权限检查、systemd 启停/恢复 | `observability.mbt`、`diagnostics_json.mbt`、`cmd/netdemo/service.mbt`、`deploy/`、测试及 `docs/diagnostics-json.md`；Ubuntu WSL2 79 项测试通过，systemd 安装/启动/停止/重启、持久去重、日志和权限拒绝实测。仅 loopback 与样例节点，非远端生产服务。 |
| M7 适配与生态 | 本阶段完成；发布单独验收 | 统一观测契约、可重复模拟器、Linux procfs 只读适配器、模块许可与包边界 | `device_observation.mbt`、`linux_device/`、`cmd/device/`、`moon.mod`、`docs/device-adapters.md`；native 82 项通过，根 package 四后端各 71 项通过。整模块全目标仍因 native I/O 包及测试失败；未宣称 wasm/JS 支持这些适配器。 |

P0 的依赖主线为 **M0 → M1 → M2 → M3 → M4 → M5**。M4 的策略测试可复用 M1 的持久化契约，但不在早期里程碑提前扩展业务。每个增量执行与改动相符的 `moon fmt`、`moon check --deny-warn`、相关 `moon test`；公开 API 变化另查 `moon info` 与 `.mbti`。验收缺口保留为待实施，不能用模拟输出代替网络或 Linux 实测。
