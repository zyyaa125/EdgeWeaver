# EdgeWeaver 本地验收记录（2026-10-24）

环境：Windows 本地 native；`moon 0.1.20261012`、`moonc v0.10.15`。`moon fmt --check`、`moon check --deny-warn`、`moon build` 已通过，`moon test --deny-warn` 为 **74/74 通过**。以下只报告本机真实执行；GitHub Actions 修改后的 Linux 运行结果尚待远端 CI 确认。

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
| 9. 重连预算耗尽 | 通过（状态机） | `transport_test.mbt` 覆盖重试时间和 `RetryExhausted`。网络 CLI 尚未接入自动退避调度。 |
| 10. 离线自治预算耗尽 | 通过（核心与磁盘） | `policy_test.mbt` 覆盖上限/恢复/时钟倒退/重复评估；`disk/safety_wbtest.mbt` 验证磁盘预算恢复。 |
| 11. 无效命令拒绝 | 通过（核心） | `edge_test.mbt` 覆盖未授权动作、Shell 形态名称、冲突 ID、过大输出、持久化失败；真实运行器未交付。 |
| 12. 真实网络超时和恢复 | 通过（本机 TCP 边界） | `network/socket_wbtest.mbt` 使无数据读取超时；控制端缺席时本地保留事件，启动后 `replay` 得到 `Accepted; pending=0`。无广域网/掉电试验。 |

补充故障注入：`disk/checkpoint_wbtest.mbt` 覆盖截断、缺字段、不兼容版本与无效内部状态；`disk/safety_wbtest.mbt` 验证损坏执行记录拒绝加载。`cmd/safety write` 写入 `InProgress`、模拟终态保存失败后结束；独立的 `resume` 进程得到 `runner_calls=0`，不重复未知副作用。

**尚未通过的总体验收项：** 长期持续采集、CLI 自动退避调度、实际命令运行器的超时与权限隔离，远程 TLS 与凭证，Linux 干净环境安装/重启恢复，真实硬件适配，掉电和多写者一致性。当前仍是本机单写者原型，不能作为生产部署或完整 P0/P1 完成证明。没有吞吐量或延迟性能数据。
