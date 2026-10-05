# EdgeWeaver 运行档案

本目录保存可审阅的部署样例。样例只描述进程角色、目录和有界资源预算，不包含设备密钥、访问令牌或远程地址。

## 节点端

[`node-profile.toml`](node-profile.toml) 对应 `RunProfileKind::Node`：

- 角色：`node`
- 数据目录：`/var/lib/edgeweaver/node`
- 配置文件：`/etc/edgeweaver/node.toml`
- 网络策略：可重连，离线时由本地存储和策略模块继续工作

## 控制面

[`control-plane-profile.toml`](control-plane-profile.toml) 对应 `RunProfileKind::ControlPlane`：

- 角色：`control-plane`
- 数据目录：`/var/lib/edgeweaver/control-plane`
- 配置文件：`/etc/edgeweaver/control-plane.toml`
- 网络策略：可重连，用于登记节点、同步配置和接收命令

## 启动参数约定

调用方将参数传给 `LaunchOptions::parse`：

```text
--profile node|control-plane
--data-dir <path>
--config <path>
```

省略覆盖参数时使用对应角色的默认值；覆盖数据目录后，事件日志和诊断目录会自动放在该目录下的 `events/` 与 `diagnostics/` 子目录。所有路径和资源预算在 `RunProfile::validate` 中检查。

仓库根目录提供无需真实硬件的最小闭环示例。在项目根目录运行 `moon run cmd/main`，可验证节点登记、心跳、事件入队、能力握手和回放；输出中的 `pending events: 0` 表示本次演示队列已清空。

本阶段不启动 systemd/Kubernetes 服务，也不创建目录或读取 TOML 文件；它只提供可复用的运行档案和启动参数契约。

弱网期间的队列、重连、事件回放和恢复流程见 [`../docs/weak-network-operations.md`](../docs/weak-network-operations.md)。
