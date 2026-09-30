# EdgeWeaver 开发约定

- 每次只实现当前里程碑；不要提前加入后续阶段的功能。
- 修改前用精确文件名、`rg` 或 `moon ide` 定位，只读取直接相关内容。
- 保持 MoonBit module/package 边界清晰；每个 package 使用独立目录和 `moon.pkg`。
- MoonBit 源码按 `///|` 分块，文件只按职责组织，不构成命名空间。
- 格式与静态检查使用 `moon fmt` 和 `moon check --deny-warn`；只运行与当前改动相关的测试。
- 修改公开 API 时额外运行 `moon info`，并审阅生成的 `.mbti` 变化。
- 不读取或提交 `.git`、`_build`、`target`、`.repos` 和依赖缓存内容。
- 不在仓库、示例配置或提交记录中保存口令、令牌、私钥或生产设备凭证。
- 每个计划里程碑单独提交；提交说明写清行为变化与尚未覆盖的范围。
