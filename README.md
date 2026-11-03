# Yingxia Remote（映匣遥控器）

用同一 Wi-Fi 下的手机浏览器控制 Mac 上的[映匣](https://github.com/jo32/tvbox-silicon)。这是独立开发的遥控器，非映匣官方项目。遥控器不传输画面，也不控制 Apple TV 硬件。

## 使用

1. 在 Mac 上安装并打开映匣，打开映匣主窗口。
2. 下载 GitHub Releases 中适合的 `YingxiaRemote-*-macOS-universal.zip`，解压并把 `YingxiaRemote.app` 放入“应用程序”。启动后会显示手机连接窗口；关闭窗口后，应用仍在菜单栏运行，可从菜单栏再次打开。
3. 首次启动时，在“系统设置 → 隐私与安全性 → 辅助功能”允许“映匣遥控器”，然后退出并重新打开应用。播放快捷键还可能触发 macOS 的“自动化”授权提示。
4. 点击菜单栏的电视图标，选择“复制手机地址”；让手机与 Mac 连接同一 Wi-Fi，在手机浏览器打开该地址，例如 `http://192.168.1.2:8765/`。地址无需 token，Mac 的 Wi-Fi 地址变化后要从菜单栏重新复制。

预览版使用临时签名，未经 Apple 公证，macOS 可能阻止首次打开。先尝试打开，再到“系统设置 → 隐私与安全性”点“仍要打开”；正式版需要 Developer ID 签名及公证。服务仅监听 Mac 的局域网地址和 8765 端口，**同一网络中能访问该端口的设备都可以操作映匣**。只在可信网络中运行，用完从菜单栏退出。若手机连不上，检查两台设备是否在同一网络、Mac 防火墙是否允许连接，以及路由器是否开启客户端隔离。

## 遥控操作

- “主界面”和“播放窗口”标签会切换并前置已有窗口，不会创建播放窗口。全屏播放遮挡主窗口时，切回主界面会先退出播放全屏。
- 主界面方向键在映匣的可见控件间移动，独立光框显示当前选中项；走到内容边缘时尝试滚动并选择新出现的控件。确认执行选中项，返回触发可见的返回按钮。长按确认或点“更多操作”发送右键；是否出现详情菜单取决于映匣当前卡片。
- 播放窗口的确认键和“播放 / 暂停”都发送空格键；左右跳转、上下调节播放器音量，另有全屏、静音、返回键。独立的“Mac 音量”按键调系统输出音量。
- 圆盘四个扇区都可点击，按住方向键会连续操作。页面不会滚动或因长按选中文本。支持 Vibration API 的浏览器会提供震动反馈；iPhone Safari 可能不支持。

主界面导航依赖映匣当前提供的 macOS 辅助功能控件。已在“发现”页验证上下滚动；其他页面、弹窗以及不同版本的映匣可能需要单独适配。独立光框不会改变映匣自身的焦点样式。

## 本地构建

需要 macOS 13+ 和 Xcode Command Line Tools。无需 Python 运行时、Node 或第三方库：

```sh
./build-app.sh
open dist/YingxiaRemote.app
```

脚本编译 Apple Silicon 和 Intel 通用版本，并对本地构建进行临时签名。生成的应用在 `dist/YingxiaRemote.app`。修改版本号可使用 `APP_VERSION=0.2.0 ./build-app.sh`。`server.py` 是开发用的旧版 Python 入口，可运行 `python3 server.py`，但 GitHub Release 使用原生单体 `.app`。

## GitHub Release

推送 `v0.1.0-preview.1` 这样的标签会构建临时签名的通用 `.app`，创建 prerelease，并附上 ZIP 与 SHA256 校验文件。预览版仍可能受 Gatekeeper 限制。推送 `v0.1.0` 这样的正式标签时，工作流要求以下 GitHub Actions secrets，完成 Developer ID 签名、Apple 公证和装订后才发布：

| Secret | 用途 |
| --- | --- |
| `CERTIFICATE_P12_BASE64` | Developer ID Application `.p12` 文件的 Base64 内容 |
| `CERTIFICATE_PASSWORD` | `.p12` 密码 |
| `CODESIGN_IDENTITY` | `Developer ID Application: … (TEAMID)` |
| `APPLE_ID` | 用于公证的 Apple ID |
| `APPLE_APP_PASSWORD` | 该 Apple ID 的 app 专用密码 |
| `APPLE_TEAM_ID` | Apple Developer Team ID |

当前没有 Developer ID 证书时，可以构建预览版，不能制作可正常公证的正式版。发布前应在 GitHub 仓库启用 Actions，并在真实 Mac 和手机上验证遥控操作。项目源码使用 [MIT License](LICENSE)；内置 Lucide 图标遵循其[许可证](icons/LUCIDE-LICENSE)。
