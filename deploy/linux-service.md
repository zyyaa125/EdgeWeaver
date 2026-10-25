# Linux 本机服务部署与恢复

目标环境是带 systemd 的 Linux 用户态主机、MoonBit native 工具链及 C 编译器。本档案把节点回放进程和控制端进程安装到**同一台主机**，TCP 仅监听 `127.0.0.1`。当前节点只回放已写入 checkpoint 的事件；`queue` 生成样例事件，不是设备采集器。没有 TLS、远端监听或生产命令运行器。

## 从仓库安装

以下命令在仓库根目录运行；首次安装需 root 权限，`edgeweaver` 账户须尚不存在。两个可执行文件来自同一份 MoonBit ELF，由启动参数和配置中的角色双重限定。

```sh
moon build
sudo useradd --system --home-dir /var/lib/edgeweaver --shell /usr/sbin/nologin edgeweaver
sudo install -d -m 0755 /etc/edgeweaver
sudo install -m 0755 _build/native/debug/build/cmd/netdemo/netdemo.exe /usr/local/bin/edgeweaver-node
sudo install -m 0755 _build/native/debug/build/cmd/netdemo/netdemo.exe /usr/local/bin/edgeweaver-control
sudo install -m 0644 deploy/node-service.json /etc/edgeweaver/node.json
sudo install -m 0644 deploy/control-service.json /etc/edgeweaver/control.json
sudo install -m 0644 deploy/edgeweaver-node.service /etc/systemd/system/edgeweaver-node.service
sudo install -m 0644 deploy/edgeweaver-control.service /etc/systemd/system/edgeweaver-control.service
sudo systemd-analyze verify /etc/systemd/system/edgeweaver-node.service /etc/systemd/system/edgeweaver-control.service
sudo systemctl daemon-reload
sudo systemctl enable --now edgeweaver-control.service edgeweaver-node.service
```

`StateDirectory` 为两个角色分别建立 `/var/lib/edgeweaver/{node,control}/events`，所有角色数据目录均由 `edgeweaver` 拥有，模式为 `0700`。服务以该非特权账户运行，`UMask=0077`；配置由 root 拥有，不能被组或其他用户写入。启动时拒绝配置符号链接、非普通文件、超过 4096 字节的配置、错误角色或格式、越界端口/时间、非绝对路径，以及不属于服务账户或权限过宽的数据目录。不要在配置中放入凭证。

配置格式为 JSON `format=1`，含 `role`（`node`/`control`）、`data_dir`、`port`（1–65535）、`timeout_ms`（100–300000）和 `poll_ms`（1000–10000）。两个角色使用相同本机端口；`poll_ms` 仅用于节点轮询。启动失败会输出不含配置内容的错误类别。

## 启停、日志及重启恢复

```sh
systemctl is-active edgeweaver-control.service edgeweaver-node.service
sudo journalctl -u edgeweaver-control.service -u edgeweaver-node.service -n 30 --no-pager
sudo runuser -u edgeweaver -- /usr/local/bin/edgeweaver-node queue /var/lib/edgeweaver/node/events/checkpoint.json 1
sudo systemctl stop edgeweaver-node.service edgeweaver-control.service
sudo systemctl start edgeweaver-control.service edgeweaver-node.service
```

节点日志的 `drained=1; pending=0` 表示样例事件获得持久收据后被本地确认。要验收“远端已接收、本地确认丢失”，先确认待处理数为零，再停止节点服务，执行下列命令，重启控制端后启动节点。最终仍应为 `pending=0`，控制端收据内该消息仅有一份。

```sh
sudo systemctl stop edgeweaver-node.service
sudo runuser -u edgeweaver -- /usr/local/bin/edgeweaver-node send 19077 /var/lib/edgeweaver/node/events/checkpoint.json 5000
sudo systemctl restart edgeweaver-control.service
sudo systemctl start edgeweaver-node.service
sudo journalctl -u edgeweaver-node.service -n 20 --no-pager
```

正常命令返回码为 0；服务启动配置或权限拒绝为 2；运行中网络或磁盘错误为 3，交由 systemd 有界重启。`systemctl stop` 通过 SIGTERM 停止服务。日志输出到 journald；错误只给类别，不输出事件正文、配置内容或命令参数。控制端的格式 2 收据与节点 checkpoint 是恢复依据，不得在升级或重启前删除。

## 升级与回滚

先停止节点和控制端，备份 `/etc/edgeweaver/` 与 `/var/lib/edgeweaver/`，保留原始目录权限和所有 `.receipt`/收据文件。再替换两个 ELF 与单元文件，运行 `systemd-analyze verify`、`systemctl daemon-reload`，按控制端、节点端顺序启动并查看 journal。回滚时停止服务、恢复先前版本的两个 ELF 和配置；若新版写入了旧版不认识的数据格式，先保留现场并做格式兼容核验，不能盲目覆盖 checkpoint 或收据。不得对不确定命令执行记录自动重试。

本地实测环境及结果见 [`../docs/acceptance-report.md`](../docs/acceptance-report.md)。Windows 构建产物不能用于这些 Linux 命令。
