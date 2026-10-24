# EdgeWeaver 实现审计（2026-10-24）

## 已复现基线

在 `moon 0.1.20261012`、`moonc v0.10.15`、native 目标下，`moon fmt --check`、`moon check --deny-warn`、`moon build` 均通过，`moon test --deny-warn` 为 **52/52 通过**。`moon run cmd/main` 的同进程示例输出 `acknowledged events: 1`、`pending events: 0`。两次独立进程运行 `cmd/recovery`，先 `write` 后 `replay`，得到 `local pending=1`，随后 `deduplicated=1; pending=0`。这些结果证明本机模拟与磁盘重启路径可运行，不代表云边网络验收。

## 源码核对与优先级

| 模块 | 已实现 | 缺口及优先级 |
| --- | --- | --- |
| `store.mbt`、`disk/` | 有界待处理队列、版本 1 checkpoint、16 MiB 文件上限、临时文件写入和替换；单写者演示 | M1：恢复时尚未完整验证条目顺序、领域状态和收据一致性；已确认条目可持续增长；崩溃窗口与目录持久化边界需故障注入。 |
| `sync.mbt` | 按序尝试回放，Accepted/Duplicate 后确认；重试与错误结果 | M1：游标超前时可跳过未确认事件；游标仅在内存；本地确认与 checkpoint 保存之间存在窗口。 |
| `transport.mbt` | 能力握手、连接状态、指数退避 | M2–M3：无可注入的真实传输接口、超时或 socket；退避时间计算需边界验证。 |
| `protocol.mbt` | 版本化 Telemetry/Command/CommandResult 信封 | M2：登记、心跳、配置、事件确认、错误响应尚无统一 wire schema 和输入上限。 |
| `edge.mbt`、`command.mbt` | 命令白名单、生命周期、内存执行记录 | M4：执行前记录未落盘；未知执行结果、参数/输出/超时与权限缺少真实执行边界。 |
| `policy.mbt` | 离线窗口、健康检查、触发预算 | M4：恢复计数未校验；重复评估、时钟倒退、版本迁移需要不变量测试。 |
| `observability.mbt` | 有界内存诊断结构 | M6：无 JSON 输出、角色和最后成功连接时间。 |
| `deploy.mbt`、`deploy/` | 两种角色的运行档案和参数解析 | M6：无可安装服务、配置加载、权限检查或 Linux 干净环境验收。 |
| `adapters.mbt` | 可重复模拟设备 | M7：无真实 Linux 用户态信息适配器；不能声明硬件支持。 |
| `cmd/recovery/` | 两进程本地收据去重演示 | M1/M5：需损坏文件、确认丢失和收据冲突的自动故障注入；本地收据不是远端确认。 |
| CI、文档 | native 格式/检查/构建/测试；README 说明边界 | M5：CI 未运行跨进程验收；验收报告缺失。`moon.mod` 还需核对许可证元数据。 |

## 约束与风险

- 当前收据文件与 checkpoint 是两个独立文件，没有事务；接收成功、本地确认或保存失败后必须保留待处理事件，靠稳定消息 ID 重放。不能用游标静默跳过未确认条目。
- C 文件适配器使用固定 `.tmp` 路径，要求单写者和预先存在的目录；文件替换后未对 POSIX 目录执行 `fsync`，掉电耐久性尚未经验证。
- 真实网络、TLS、真实命令运行器、Linux 服务和设备驱动均未实现。后续每项按里程碑验证，未通过真实验收前不得宣称生产可用。
