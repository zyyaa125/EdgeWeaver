# 命令与离线策略安全边界（M4）

`EdgeExecutor::execute_durable` 在调用动作适配器前，先通过 `persist` 保存 `InProgress`。终态也必须成功保存才对外返回成功或失败；若终态保存失败，保留 `InProgress`，重启后 `restore_checked` 拒绝不一致记录，且不重复执行同一命令。相同命令 ID 携带不同动作或时间边界时返回 `CommandConflict`。`Execute` 名称只能含 ASCII 字母、数字、`_`、`-`、`.` 且最多 64 字符；它是预定义动作 ID，不能当 Shell 命令解释。结果消息最多 4096 UTF-8 字节。

磁盘适配器使用版本化、单写者文件保存执行记录和策略预算；调用方必须给每种状态分别指定数据文件。`AutonomyEngine::evaluate_durable` 在返回离线动作决策前保存已消耗预算；同一时间戳重复评估不再次触发，时间倒退被拒绝。恢复时校验预算、规则版本和同一组规则的评估时间。策略决策成功只代表准许尝试动作，不代表实际执行成功。

两进程执行状态验收：

```sh
moon run cmd/safety -- write /tmp/edgeweaver-execution.json
moon run cmd/safety -- resume /tmp/edgeweaver-execution.json
```

首个进程模拟结果写入失败，应输出 `uncertain execution saved; runner_calls=1`；第二个进程恢复，应输出 `restored uncertain execution; runner_calls=0`。示例动作只返回模拟结果，不调用系统 Shell 或真实设备。核心库也不负责强制中断任意注入回调；实际运行器的超时、权限和输出流截断仍需在部署适配器实现并单独验收。损坏的安全 checkpoint 保留原文件并返回错误，不应创建新状态覆盖证据。
