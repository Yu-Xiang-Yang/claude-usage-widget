# Contributing / 贡献指南

Thank you for considering a contribution. This document is available in English first; a Chinese summary follows.

## Setup

```bash
git clone https://github.com/Yu-Xiang-Yang/claude-usage-widget.git
cd claude-usage-widget
./build.sh                  # builds build/ClaudeUsageWidget.app
open build/ClaudeUsageWidget.app
```

Only the Xcode Command Line Tools are required. The project is a single Swift package-less target; all sources are in `Sources/` and are compiled together by `build.sh`.

## Checking a change

There is no test suite yet. The command-line modes make most changes verifiable without a signed-in session:

| Change | Check |
| --- | --- |
| Layout or text | `ClaudeUsageWidget --snapshot out.png --size large --lang en --demo` for every size class and both languages, and compare the images; text must not be clipped |
| Usage endpoint parsing | `echo '<json>' \| ClaudeUsageWidget --parse-usage` |
| Log aggregation | `ClaudeUsageWidget --dump`, compared against an independent calculation |
| Window behaviour | Run the app, drag the widget, switch sizes, switch the language |

Use `--demo` for every image that is committed. Never commit screenshots that contain real usage figures, account names or e-mail addresses.

## Conventions

- Keep the surrounding style: naming, comment density and idiom. Comments are in English.
- Every user-facing string goes through `tr("中文", "English")` (`Sources/Localization.swift`); do not add literals to views.
- Keep each size class inside its card (164 × 164, 344 × 164, 344 × 344 and 704 × 344 pt); verify with the snapshot renders.
- Prices live in `Pricing` (`Sources/UsageStore.swift`). A price change needs the source of the figure in the pull request.

## Reporting a change in the usage endpoint

The plan limits come from a web endpoint of claude.ai that is not a public API. If the widget reports an unrecognized response, open an issue with the **structure** of the response (field names and types), not its values, and remove identifiers. `--parse-usage` shows what the parser extracts.

## Pull requests

1. Open an issue first for larger changes.
2. Keep a pull request to one topic.
3. Describe how the change was checked and attach demo-data renders for visual changes.

## 中文摘要

- 构建：`./build.sh`，仅需 Xcode 命令行工具。
- 验证：项目暂无测试集，请使用命令行模式核对——`--snapshot ... --demo` 渲染各尺寸与两种语言，`--parse-usage` 检查接口解析，`--dump` 核对聚合结果。
- 约定：界面文案一律使用 `tr("中文", "English")`；每个尺寸的内容不得超出卡片；提交的图片必须由 `--demo` 生成，不得包含真实用量、账号或邮箱。
- 额度接口变更：请在 issue 中提供响应的结构（字段名与类型），不要提供取值，并去除标识信息。
