# 本地 TCP 闭环验收（M3）

`cmd/netdemo` 在两个独立 native 进程之间通过 `127.0.0.1` TCP 交换消息。每帧使用 **4 字节大端正文长度**加 UTF-8 JSON，正文上限 65,536 字节；连接与读写超时通过最后一个毫秒参数设置。控制端完成版本/能力握手、登记、心跳后，才接收事件；它调用磁盘收据适配器成功后才发 `Accepted`，同一消息 ID 再到达时发 `Duplicate`。收据和节点 checkpoint 分别单写、独立持久化。

在三个终端中从仓库根目录运行，数据目录须已存在。先在控制端终端执行：

```sh
moon run cmd/netdemo -- serve 39471 /tmp/edgeweaver-receipt.json 2 60000
```

然后分别启动两个节点进程：

```sh
moon run cmd/netdemo -- send 39471 /tmp/edgeweaver-checkpoint.json 3000
moon run cmd/netdemo -- replay 39471 /tmp/edgeweaver-checkpoint.json 3000
```

首次应看到 `remote accepted; local pending=1`。`send` 故意不保存本地确认，模拟远端已接收但节点在确认前退出。第二次应看到 `remote duplicate; local pending=0`，收据内该消息 ID 只出现一次。也可在两次命令之间停止控制端、用同一收据路径重新启动并将会话数设为 1；重启后仍应返回 `Duplicate`。若首次发送前控制端不存在，`send` 会以 `ConnectFailed` 退出但保留 checkpoint 的待处理事件；控制端启动后运行 `replay` 应返回 `Accepted` 并将待处理数降为 0。

本闭环仅绑定本机 loopback，不提供 TLS、凭证、远程主机接入、多写者仲裁或生产级远端服务。收据保存的是消息 ID；同一 ID 的不同负载冲突、磁盘掉电、服务并发与跨节点持久注册尚未验收。运行前请选择独占端口和专用数据文件，避免复用其他实例的收据。

多事件中断验收：先在没有控制端的情况下运行 `moon run cmd/netdemo -- queue /tmp/edgeweaver-queue.json 3`，应显示 `queued pending=3`。启动 `serve`，会话数设为 `1`，然后运行 `drain <port> /tmp/edgeweaver-queue.json 3000`；首条事件确认后控制端退出，第二次连接失败，checkpoint 仍有 2 条待处理。再次用相同收据路径启动 `serve`（会话数 `2`），重新运行 `drain`，应显示 `drained=2; pending=0`，收据 ID 按 `network-event-1,2,3` 排列。`queue` 每添加一条事件即保存 checkpoint。`drain` 每得到匹配的 `Accepted`/`Duplicate` 才确认并保存，连接失败时须由操作方重新启动；自动退避调度尚未接入此 CLI。
