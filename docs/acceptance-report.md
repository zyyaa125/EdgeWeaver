# EdgeWeaver 本地验收记录（2026-10-24）

环境：Windows 本地 native；`moon 0.1.20261012`、`moonc v0.10.15`。`moon fmt --check`、`moon check --deny-warn`、`moon build` 已通过；增加诊断 JSON 测试后 `moon test --deny-warn` 为 **78/78 通过**。以下只报告本机真实执行；GitHub Actions 修改后的 Linux 运行结果尚待远端 CI 确认。

| 场景 | 结果 | 证据与限制 |
| --- | --- | --- |
| 1. 登记、心跳、事件同步 | 通过（本机 TCP） | `cmd/netdemo` 的 `serve`/`send` 两进程完成握手、登记、心跳和远端 `Accepted`。只绑定 loopback。 |
| 2. 断网期间持续产生事件 | 通过（有界三事件） | 无服务端时 `queue` 逐条保存 3 条待处理事件；尚无长期持续采集或负载试验。 |
| 3. 进程退出后恢复 checkpoint | 通过 | 两个独立 `cmd/recovery` 进程分别执行 `write`、`replay`；第二进程得到 `deduplicated=1; pending=0`。 |
| 4. 接收成功但本地确认丢失 | 通过（本机 TCP） | `cmd/netdemo send` 得到 `remote accepted; local pending=1`；节点进程退出后重新加载该文件。 |
| 5. 重复回放不重复接收 | 通过（本机 TCP） | 同一收据文件在控制端重启后返回 `remote duplicate; local pending=0`；检查收据 ID 数为 1。 |
| 6. 连接恢复后按序继续同步 | 通过（本机 TCP） | 控制端只处理第 1 条便退出，checkpoint 保留 2 条；重启两端后 `drained=2; pending=0`，收据顺序为 `network-event-1,2,3`。 |
| 7. 协议版本不匹配 | 通过（解码/状态机） | `protocol_wire_test.mbt` 拒绝 2.0；`transport_test.mbt` 握手拒绝不兼容版本。真实 socket 注入版本错误尚未实测。 |
| 8. 队列容量上限 | 通过 | `store_test.mbt` 覆盖拒绝新事件和丢弃最旧待处理事件。 |
| 9. 重连预算耗尽 | 通过（本机 TCP） | `transport_test.mbt` 覆盖状态机；`drain` 在无监听端口上按 1 秒、2 秒退避，最终返回 `ReconnectExhausted`，磁盘仍保留 1 条待处理。 |
| 10. 离线自治预算耗尽 | 通过（核心与磁盘） | `policy_test.mbt` 覆盖上限/恢复/时钟倒退/重复评估；`disk/safety_wbtest.mbt` 验证磁盘预算恢复。 |
| 11. 无效命令拒绝 | 通过（核心） | `edge_test.mbt` 覆盖未授权动作、Shell 形态名称、冲突 ID、过大输出、持久化失败；真实运行器未交付。 |
| 12. 真实网络超时和恢复 | 通过（本机 TCP 边界） | `network/socket_wbtest.mbt` 使无数据读取超时；控制端缺席时本地保留事件，启动后 `replay` 得到 `Accepted; pending=0`。无广域网/掉电试验。 |

补充故障注入：`disk/checkpoint_wbtest.mbt` 覆盖截断、缺字段、不兼容版本与无效内部状态；`disk/safety_wbtest.mbt` 验证损坏执行记录拒绝加载。`cmd/safety write` 写入 `InProgress`、模拟终态保存失败后结束；独立的 `resume` 进程得到 `runner_calls=0`，不重复未知副作用。

收据一致性补充：`disk/receipt_wbtest.mbt` 验证同 ID 同信封才返回 `Duplicate`；同 ID 不同负载返回永久冲突；旧版 ID-only 收据保留原文件并拒绝自动确认。

收据格式 2 上线后，再次以两个独立 `cmd/netdemo` 节点进程发送/回放：先得到 `remote accepted; local pending=1`，后得到 `remote duplicate; local pending=0`；控制端收据 `format=2`、消息数 1。本地 WSL Ubuntu 可访问仓库，但没有 Linux MoonBit 或 C 编译器；官方 MoonBit 安装源在本机连接超时。因此 Linux 原生构建、systemd 与干净环境恢复目前无实测结果，不能用 Windows native 结果代替。

目标边界检查：`moon check --target all --deny-warn` 未通过，首个相关错误来自 `disk/checkpoint_wbtest.mbt` 在非 native 目标中引用了 native 专用解码函数；尝试仅筛选源码目标后，非 native 空 package 又触发未使用导入诊断。仓库首选目标是 native，纯领域逻辑的跨后端可用性仍待单独拆包验证；本报告不宣称全目标通过。

**尚未通过的总体验收项：** 长期持续采集、实际命令运行器的超时与权限隔离，远程 TLS 与凭证，真实硬件适配，掉电和多写者一致性。当前仍是本机单写者原型，不能作为生产部署或完整 P0/P1 完成证明。没有吞吐量或延迟性能数据。下列新增记录补足了 Linux 本机服务验收，不覆盖这些限制。

## 2026-10-25：Ubuntu WSL2 本机服务补充验收

环境：Ubuntu 24.04 WSL2、用户目录隔离安装的 `moon 0.1.20261023`/`moonc v0.10.17`、Ubuntu `build-essential`。原生 `moon check --deny-warn`、`moon build`、`moon test --deny-warn` 通过，**79/79 测试通过**。两个独立 Linux 进程的 `cmd/recovery write`/`replay` 得到 `deduplicated=1; pending=0`；`cmd/safety write`/`resume` 得到 `runner_calls=1` 后 `runner_calls=0`。

按 [`../deploy/linux-service.md`](../deploy/linux-service.md) 将同一 Linux ELF 安装为节点与控制端两个角色，配置、systemd 单元和 `edgeweaver` 非特权账户均在 WSL 中实装。`systemd-analyze verify` 无诊断；服务可启动、停止、重启，角色数据目录及 `events` 子目录均为 `edgeweaver:edgeweaver 0700`，journald 即时记录启动和 `drained=1; pending=0`。以服务账户入队 1 条样例事件后自动回放；再停止节点，发送第 2 条事件使控制端接收但本地仍待确认，重启控制端和节点后本地队列清空，格式 2 收据仅含 2 条消息。模式 `0666` 的配置文件被拒绝，启动退出码为 2；把节点 `events` 目录临时改为 `0755` 也被拒绝，之后已恢复 `0700`。测试结束后服务已停止，安装文件和演示状态仍保留在 WSL 供复核。

这一验收只覆盖同机 loopback、样例节点和 systemd 用户态进程。没有验证远端网络、TLS、真实设备采集、实际命令运行器、掉电持久性或独立物理 Linux 主机。

## 2026-10-25：M7 设备适配与后端边界

新增的 `DeviceObservation` 将节点、设备、健康、指标、值、单位和时间统一为纯领域数据，并可编码成版本 1 Telemetry 信封。确定性模拟器、空字段/负时间拒绝及 JSON 回读均有测试。Linux native 的 `LinuxUptimeAdapter` 从固定 `/proc/uptime` 路径读取真实主机运行秒数；`moon run cmd/device` 在 Ubuntu WSL2 输出观测及事件 JSON，值随启动时间变化。这是主机信息适配器，**不是物理传感器驱动或整机健康诊断**；读取成功仍将健康标为 `Unknown`。

Windows 与 Ubuntu native 的 `moon test --deny-warn` 均为 **82/82 通过**。纯根 package 的 `moon check . --target all --deny-warn` 通过，`moon test . --target all --deny-warn` 在 wasm、wasm-gc、JS、native 各 **71/71 通过**。整模块 `moon check --target all --deny-warn` 的首个相关错误仍是 `disk/checkpoint_wbtest.mbt` 在非 native 后端引用 native 专用解码函数；native I/O 包不宣称可跨后端运行。新增适配器只依赖 MoonBit core 与 Linux procfs，没有额外第三方库；模块增加 MIT 许可元数据，Mooncakes 发布未执行。

## 2026-10-25：Mooncakes 0.1.0 发布验收

Ubuntu `moon 0.1.20261023`、`moonc v0.10.17` 对发布包执行 `moon package --list`，确认含 README、MIT 许可证且排除本地 `任务说明.md`。`moon publish --frozen` 对原包及解包后的内容均完成检查，Mooncakes 返回 `200 OK`；独立临时项目执行 `moon add zyyaa125/edgeweaver@0.1.0` 成功下载。公开[模块页面](https://mooncakes.io/docs/zyyaa125/edgeweaver%400.1.0)返回 HTTP 200；对应源码已推送 GitHub 标签 [`v0.1.0`](https://github.com/zyyaa125/EdgeWeaver/tree/v0.1.0)。此验收只证明包可发布与获取，native I/O 的后端限制仍按上节说明。
