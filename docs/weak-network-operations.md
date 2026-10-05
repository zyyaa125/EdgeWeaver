# EdgeWeaver 弱网运行与恢复

本文是节点端（`node`）和控制面（`control-plane`）的运行手册。它描述当前模块已经提供的本地状态、重连、事件回放、离线策略和诊断边界。部署路径与角色默认值见 [`../deploy/README.md`](../deploy/README.md)。

## 架构与兼容决策

- **运行角色：** 节点负责本地状态、设备适配、命令执行和离线策略；控制面负责登记、心跳、配置/命令管理和同步接入。两端通过版本化消息信封交换数据。
- **实现目标：** 当前模块以 MoonBit `native` 和标准 Linux 用户态进程为目标；模拟器和适配器先验证闭环，真实硬件驱动、集群高可用和多租户编排不属于本版本。
- **协议兼容：** 当前接受 `ProtocolVersion::current()`（1.0）。握手版本不一致或没有共同能力时保持断开，不降级发送未知消息；新增协议版本必须先更新信封解析、能力协商和回放测试。
- **状态边界：** `LocalStore::checkpoint`、执行记录和策略 checkpoint 是持久化边界，文件、服务管理和密钥存储由部署适配器提供。当前核心模块不会自行创建目录或写入凭证。

## 运行不变量

弱网期间应保持以下不变量：

1. 本地事件按 journal sequence 顺序保留，只有收到 `Accepted` 或 `Duplicate` 才推进同步游标。
2. 传输握手完成且协商出 `EventReplay` 后才能回放；未连接或没有该能力时保留事件，不跳过队首。
3. 重连次数、事件批次和本地日志都有上限。达到上限时记录状态并等待人工处理，不通过无限重试恢复。
4. 离线策略只在节点处于 `Offline` 且健康状态已知时执行，并同时受允许列表、有效时间窗和触发次数限制；其他情况返回 `SafeDefault`。
5. 命令执行记录和本地 store checkpoint 用于进程重启后的幂等恢复，不要在不确认副作用状态时重复执行命令。

## 状态和观测

传输管理器使用以下状态：

| 状态 | 含义 | 运维动作 |
| --- | --- | --- |
| `Disconnected` | 尚未发起连接 | 按当前配置开始一次连接 |
| `Connecting` | 正在等待握手 | 等待握手结果，不重复调用连接流程 |
| `Connected` | 已完成版本和能力协商 | 根据能力回放事件并恢复心跳 |
| `Backoff` | 连接失败后等待下一次重试 | 等到 `next_retry_at`，不要提前重试 |

每次值班处理先生成 `LocalDiagnostics` 快照，重点查看：

- `connection_state`、`next_retry_at` 和 `sync_cursor`；
- `pending_events`、`dropped_events` 和 `sync_failures`；
- `negotiated_capabilities`，确认是否包含 `EventReplay`、`Heartbeat`、`Config` 或 `Command`；
- `lifecycle`、`health`、`policy_decision` 和 `execution_records`。

节点在控制面连续丢失心跳后标记为 `Offline`；收到时间戳不早于当前状态的心跳后恢复为 `Online`。时间戳倒退、已退役节点和未知节点都应作为数据问题处理，而不是通过重试掩盖。

## 弱网期间的操作

### 1. 保留本地状态

使用 `JournalConfig::new` 设置正的容量，并明确选择 `RejectNew` 或 `DropOldest`：

- `RejectNew` 保留已有事件，容量满时拒绝新事件，适合不能丢失审计记录的场景。
- `DropOldest` 允许继续写入，但必须监控 `dropped_events`，因为被丢弃的事件不能在恢复时补回。

收到 `QueueFull` 时先记录诊断并评估容量，不要直接删除整个 journal。进程重启前保存 `LocalStore::checkpoint`；启动时用 `LocalStore::restore` 校验并恢复它。

### 2. 允许有限的离线自治

只把无需远端确认、可安全重复判断的动作加入 `CommandAllowlist`。为每条 `AutonomyRule` 设置：

- 明确的有效起止时间；
- 非负的离线时长条件；
- 正的 `max_triggers` 上限；
- 已加入允许列表的命令动作。

策略引擎返回 `SafeDefault` 时不要强行执行动作。重启前保存 `AutonomyEngine::checkpoint`，恢复后通过 `AutonomyEngine::restore` 保留已消耗的触发预算。

### 3. 避免重连风暴

`BackoffPolicy` 使用有上限的指数退避。断链后由 `disconnect` 计算下一次时间；`begin_connect` 在窗口未到时会返回 `RetryNotReady`，达到尝试上限时返回 `RetryExhausted`。值班程序应记录这两个结果并等待或升级处理，不能通过紧密循环绕过退避。

## 恢复流程

按以下顺序恢复一台离线节点：

1. **确认快照。** 保存当前 `LocalDiagnostics` 和本地 checkpoint，记录节点 ID、最后心跳时间、待回放数量、丢弃数量和同步游标。
2. **等待退避窗口。** 在 `Backoff` 状态使用 `next_retry_at` 安排下一次尝试。若收到 `RetryExhausted`，先处理网络或版本问题，再重新建立传输管理器。
3. **开始连接和握手。** 在允许的时间调用 `begin_connect`，然后使用当前 `ProtocolVersion` 和本地能力调用 `handshake`。若返回 `UnsupportedProtocol` 或 `NoSharedCapability`，停止回放并升级兼容性问题。
4. **按批次回放。** 仅在连接为 `Connected` 且协商出 `EventReplay` 后调用 `replay_pending`。用 `SyncConfig` 限制单次 `batch_size` 与 `max_attempts`，保留 `ReplayReport` 供审计。
5. **处理回放结果。** `Acknowledged` 和 `Deduplicated` 会推进游标；`RetryScheduled` 保留当前事件并等待下一次传输机会；`Rejected` 或 `Exhausted` 会停止连续回放，应检查消息和远端原因，不跳过该序列。
6. **恢复心跳和控制通道。** 回放达到可接受状态后恢复 `Heartbeat`；节点收到有效心跳后由控制面从 `Offline` 转为 `Online`。只有协商出 `Config` 或 `Command` 时才启用相应通道。
7. **再次保存状态。** 回放和命令执行状态稳定后保存 store、执行记录和策略 checkpoint，并生成第二份诊断快照，确认游标、待处理数量和能力集合符合预期。

## 故障处理表

| 现象或错误 | 处理 |
| --- | --- |
| `RetryNotReady` | 等待 `next_retry_at`，检查链路和时间同步 |
| `RetryExhausted` | 停止自动重试，处理网络、凭证或版本问题后再恢复 |
| `UnsupportedProtocol` | 让两端使用同一 `ProtocolVersion`，不要降级发送未知消息 |
| `NoSharedCapability` | 检查节点与控制面能力配置；未协商的通道保持关闭 |
| `SyncNotReady` | 确认已连接且有 `EventReplay`，不要手动推进游标 |
| `ReplayReport.retryable_failures` 增长 | 保留队首事件，修复链路或远端暂时性故障后重试 |
| `ReplayReport.permanent_failures` 或 `exhausted` 增长 | 保留失败记录，人工确认消息和远端拒绝原因 |
| `dropped_events` 增长 | 评估 journal 容量和 `DropOldest` 是否合适，必要时切换为拒绝新事件 |
| 心跳返回 `StaleHeartbeat` | 检查设备时钟和事件时间戳，修正时间源后再发送 |

## 恢复验收

恢复完成前至少确认：

- 节点 ID 未变化，生命周期为 `Online`，健康状态不是未知；
- `connection_state` 为 `Connected`，能力集合包含业务所需通道；
- `sync_cursor` 连续推进，`pending_events` 为零或有已记录的明确原因；
- 没有新增未解释的 `dropped_events`、永久失败或耗尽条目；
- 命令 `execution_records` 与远端状态一致，未重复产生不可逆副作用；
- 最终 checkpoint 和诊断快照已经保存。

## 升级与回滚

1. **升级前保存状态。** 停止产生新命令，保存 store、执行记录、策略和诊断 checkpoint，记录当前协议版本、同步游标和待处理数量。
2. **先做兼容性检查。** 新版本必须能读取现有 checkpoint，并继续识别当前消息版本；如果协议版本不兼容，先安排两端联动升级，不要让单端进入回放流程。
3. **小范围启动。** 先在模拟器或一台节点上运行 `moon run cmd/main` 和相关检查，确认登记、心跳、握手、回放结果以及 `pending_events` 符合预期，再扩大范围。
4. **回滚条件。** 出现 checkpoint 无法恢复、协议拒绝、游标倒退、重复副作用或持续的永久失败时，停止新下发，保留诊断和失败事件，恢复上一版本程序与 checkpoint。
5. **回滚后复核。** 确认节点身份、命令执行记录和策略触发预算没有被重置；重新建立连接后从连续游标开始回放，不手工删除或跳过队首事件。

当前实现提供的是可复用的运行契约和内存模型；它不会创建目录、读取 TOML、管理 systemd/Kubernetes 进程或保存 TLS 凭证。实际部署适配器应在这些边界之外接入文件、服务管理和密钥存储，并继续遵守上述不变量。
