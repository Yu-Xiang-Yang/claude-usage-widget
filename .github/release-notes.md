## Install / 安装

1. Download `ClaudeUsageWidget-<version>-macos.zip`, unzip it and move `ClaudeUsageWidget.app` to `/Applications`. The build is universal (Apple silicon and Intel) and needs macOS 14 or later.
   下载 zip，解压后将 `ClaudeUsageWidget.app` 移入 `/Applications`。该构建为通用二进制（Apple 芯片与 Intel），需要 macOS 14 及以上。
2. The app is ad-hoc signed and not notarized, so macOS blocks the first launch. Remove the quarantine flag once:
   应用采用临时签名且未经公证，首次启动会被系统拦截。执行一次下列命令移除隔离标记：

   ```bash
   xattr -dr com.apple.quarantine /Applications/ClaudeUsageWidget.app
   ```

   Alternatively open System Settings → Privacy & Security and choose *Open Anyway*.
   也可在「系统设置 → 隐私与安全性」中选择「仍要打开」。
3. Open the app, right-click the widget and choose *Sign In to claude.ai…* to show the plan limits.
   打开应用，右键小组件并选择「登录 claude.ai…」以显示订阅额度。

Verify the download with `SHA256SUMS.txt`. The sources are in this repository; the app can also be built from source with `./build.sh`.
可用 `SHA256SUMS.txt` 校验下载文件。源码即本仓库，也可执行 `./build.sh` 自行编译。

> Independent project, not affiliated with Anthropic. The plan limits use a web endpoint of claude.ai that is not a documented API.
> 独立项目，与 Anthropic 无关；订阅额度使用 claude.ai 的非公开网页接口。

---

