# 设备观测契约与 Linux 信息适配器

`DeviceObservation` 是不依赖文件、网络或进程 API 的统一结果：节点 ID、设备 ID、`NodeHealth`、指标名/整数值/单位、采集时间。`DeviceObservation::to_envelope(message_id=...)` 将它编码为版本 1 的结构化 Telemetry 消息，交给现有本地 journal 与同步流程；调用方负责稳定消息 ID 和持久化。构造器拒绝空设备 ID、指标、单位及负时间戳，采集失败由 `AdapterError::ReadUnavailable(source)` 明确返回。

`DeviceSimulator::collect_sensor` 沿用原有确定性传感器，成功采集标为 `Healthy`，适合稳定的回归测试。它不代表物理硬件。`linux_device/LinuxUptimeAdapter` 用只读 Linux 用户态接口 `/proc/uptime` 采集**主机运行秒数**；固定设备 ID `linux-host`、指标 `uptime_seconds`、单位 `s`。单一指标不能判断整机健康，因此其健康状态为 `Unknown`。文件缺失、无法读取或数值超出 `Int32` 范围时返回 `ReadUnavailable("proc_uptime")`，不伪造读数；非 Linux native 构建也返回不可用。

在 Linux native 环境运行可复现示例：

```sh
moon run cmd/device
```

程序打印一行真实观测 JSON 和一行版本化消息 JSON；运行秒数及时间戳随主机变化。新 native package 的 `moon.pkg` 至少需要以下导入，调用方式见 [`cmd/device/main.mbt`](../cmd/device/main.mbt)：

```moonbit
import {
  "zyyaa125/edgeweaver",
  "zyyaa125/edgeweaver/linux_device",
}
```

模拟器的固定读数、观测序列化和错误拒绝由 `device_observation_test.mbt` 测试；Linux package 的测试在 Ubuntu 实际读取 procfs，在 Windows 验证明确拒绝。

包边界：仓库根 package 是纯领域逻辑，可单独运行 `moon check . --target all --deny-warn` 与 `moon test . --target all --deny-warn`。`disk/`、`network/`、`linux_device/` 及相关 CLI 包含 native 文件/Socket/进程接口；整模块 `--target all` 当前首先在 `disk/checkpoint_wbtest.mbt` 的非 native 路径失败，不能将 native I/O 宣称为 wasm 或 JS 可用。首选后端仍是 native。没有新增第三方库；C 代码只读取 Linux 内核提供的 procfs。Mooncakes 的实际发布版本与可用状态以 registry 页面为准。
