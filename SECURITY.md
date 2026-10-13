# Security Policy / 安全策略

## Scope

The widget reads the session logs of Claude Code on the local machine and, for the plan limits, loads a web endpoint of claude.ai inside an embedded WebKit view that holds the user's own sign-in.

- The sign-in is stored by WebKit in `~/Library/WebKit/local.claude-usage-widget/`. The widget does not read, copy or transmit passwords, cookies or tokens; it only reads the response of the usage endpoint.
- The widget stores the per-day totals (`history.json`) and the last plan-limit reading (`quota.json`) in `~/Library/Application Support/ClaudeUsageWidget/`.
- The only network destination is `claude.ai`.
- **Clear Sign-In** in the context menu deletes the WebKit data, the stored organization identifier and `quota.json`.

Relevant reports include: leaking or persisting credentials, reading files outside the paths above, unexpected network destinations, and flaws in the sign-in window.

## Reporting a vulnerability

Please do not open a public issue. Use GitHub's private vulnerability reporting: **Security → Report a vulnerability** on this repository. Include the affected version, the steps to reproduce and the impact. A first response is aimed for within seven days.

## Supported versions

Only the latest release receives fixes.

## 中文

组件读取本机 Claude Code 日志，并在内嵌的 WebKit 视图中以用户自己的登录态访问 claude.ai 的用量接口。登录态由 WebKit 保存，组件不读取、复制或传输密码、Cookie 与令牌；唯一的网络目标为 `claude.ai`。右键菜单的「清除登录状态」会删除登录数据、组织标识与额度缓存。

请勿公开提交漏洞 issue，请使用本仓库的 **Security → Report a vulnerability** 私下报告，并注明受影响的版本、复现步骤与影响。仅最新版本接收修复。
