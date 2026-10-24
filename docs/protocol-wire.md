# 协议与传输契约（M2）

`WireFrame` 是 UTF-8 JSON 文档，`version` 必须恰为 `{ "major": 1, "minor": 0 }`；`message` 使用 MoonBit 派生 JSON 的单标签变体表示。例如错误响应为 `{ "version": { "major": 1, "minor": 0 }, "message": { "ErrorResponse": ["invalid", "bad request"] } }`。发送端调用 `encode_wire`，接收端调用 `decode_wire`；任一完整帧的 UTF-8 JSON 正文最多 **65,536 字节**。实际网络适配器还必须提供外部长度边界，不能靠读取到 EOF 判断消息结束。

| 消息种类 | 位置参数 | 语义 |
| --- | --- | --- |
| `Enroll` | 节点 ID、能力数组、时间戳 | 节点登记。 |
| `Heartbeat` | 节点 ID、健康状态、时间戳 | 心跳/健康观测。 |
| `ConfigUpdate` | 节点 ID、配置快照 | 版本化配置。 |
| `Command` | 节点 ID、命令 ID、操作名、到期时间 | 命令意图；操作名不是 Shell 文本。 |
| `EventReplay` | `MessageEnvelope` | 保留原消息 ID 的事件重放。 |
| `Receipt` | 消息 ID、`Accepted`/`Duplicate`/`Rejected(reason)` | 只有前两种且 ID 与请求相符才允许本地确认。 |
| `ErrorResponse` | 错误代码、原因 | 协议级拒绝。 |

缺字段、未知字段、未知消息种类、无效值或非法 JSON 返回 `InvalidData`；正文超限返回 `TooLarge`；非 1.0 版本返回 `UnsupportedVersion`。测试覆盖七种消息往返、未知字段与类别、缺字段、无效值、超限和版本拒绝。将来扩展格式须明确升级版本和兼容策略。

`TransportAdapter` 将连接、关闭、能力交换、有界批次发送与结果分别注入 `TransportManager`。连接失败安排原有退避；握手不兼容时关闭连接并停止同步。对每一事件，管理器要求恰好一个匹配消息 ID 的收据；超时、断连、空/多余/错位响应均保留待处理事件。`replay_with` 当前每次调用适配器发送一个事件的批次，批量窗口仍由 `SyncConfig` 控制。I/O 超时后调用方需要 `close_with` 标记链路断开。M2 的测试适配器只模拟 I/O；真实 socket 和服务端持久确认属于 M3。
