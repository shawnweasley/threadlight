# 贡献指南

感谢帮助改善 Threadlight。请先阅读 `AGENTS.md`、架构与隐私说明。

## 开发与验证

```bash
swift test
./scripts/build-app.sh
./scripts/smoke.sh
./scripts/build-dmg.sh --skip-build
```

测试需要 Swift 6 与 macOS；浮窗与菜单测试使用原生 AppKit。`smoke.sh` 会运行本地诊断并打开应用，需要已登录的图形桌面，不作为无桌面 CI 的必需项。

修改读取格式时添加合成夹具，覆盖半行、换文件、超长正文、缺少字段和身份隔离。不要把自己的 `.codex` / `.claude` 数据复制到仓库。测试明确验证 4 GB 稀疏日志的读取上限、热缓存零日志读取、重启缓存以及状态转换。

README 的菜单栏图片为使用者提供的实际截图，请保留原图。固定列表使用合成任务，可单独更新：

```bash
build/Threadlight.app/Contents/MacOS/Threadlight --export-screenshots /tmp/threadlight-previews
cp /tmp/threadlight-previews/task-list.png Assets/task-list.png
```

导出命令只短暂创建演示控件，不读取真实会话，不需要屏幕录制权限。不要将演示菜单栏图片覆盖到 `Assets/menu-bar.png`。

状态读取继续保持本地只读，不添加网络请求、令牌调用、hooks、遥测或向被监控应用写入的“修复”。UI 只展示对话标识、标题和状态，不扩展为日志浏览器。

## 提交反馈

说明 macOS、Swift、客户端版本、可复现操作和预期/实际结果。优先附上脱敏的 `--diagnose` 汇总结果。对比截图请使用合成任务，不公开真实私人标题。

## 分发

`build/`、`.build/` 与 `dist/` 是生成目录，不进 Git。公开二进制发布需要维护者确认版本、Developer ID 签名、公证和架构；仓库 CI 只验证编译与本地签名完整性。默认构建面向当前主机架构，并非 Universal Binary。

DMG 包含应用、指向系统 Applications 的「应用程序」入口与中文安装说明。打包脚本会实际校验和挂载镜像，并检查其中的应用，不只验证源目录。
