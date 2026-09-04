# 为 Winenv 贡献

[English](./CONTRIBUTING.md)

感谢你帮助 Winenv 把 Windows 软件管理做得更可预测。这份规范用于让小规模社区也能稳定评审、发布和维护贡献。

## 提交 Issue 前

- 先搜索已有 Issue 和[中文文档](https://yangyus8.top/winenv/zh/)。
- 选择与问题匹配的结构化 Issue 表单。
- 安全漏洞必须按照[安全政策](./SECURITY.zh-CN.md)私下报告。
- 报告缺陷时提供 Winenv 版本（`win ver`）、Windows build、PowerShell 版本、完整命令、预期结果、实际结果以及去除敏感信息后的输出。

可以提使用问题，但最小可复现示例通常比单张截图更容易排查。

## 项目范围

Winenv 在 Windows 11 上协调 WinGet、Scoop 和 mise。修改应维持以下边界：

- 软件发现来自管理器的实时目录，不维护人工整理的万能索引；
- 安装、更新、卸载、pin 和 hold 仍由实际管理器负责；
- 内置运行 Profile 只包含 Winenv 自身必需能力；
- 用户和社区 Profile 独立、可组合且不做破坏性操作；
- 第三方仓库、无法验证的安装器等信任决定必须明确可见；
- 复用或纳入已有安装时，不谎称软件最初由 Winenv 安装。

超出这些边界的想法，请先通过功能请求说明具体用户问题。

## 架构

修改命令路由、Profile 语义或软件管理器前，请先阅读 [RFC 0001](https://yangyus8.top/winenv/zh/reference/architecture)。`win.ps1` 是轻量兼容入口；实现函数应放在 `src/` 下对应职责的文件中。内部模块不是公共 API，也不得仅因为被加载就执行用户操作。

Provider 修改必须维持经过校验的注册表契约。新增 Provider 前需要创建 Issue，说明机器级职责、归属模型、不可用时的行为、提权、信任、回滚、测试与维护成本。不要仅为了重复项目依赖管理器或加载第三方代码而增加 Provider。

## 开发环境

纯文档贡献支持 Windows、macOS 和 Linux。使用 `.node-version` 记录的 Node.js 版本（或兼容的新版本），以及 `package.json` 固定的 pnpm 版本。这些是贡献者工具，不是 Winenv 用户的运行前置。Fork 仓库并创建聚焦的分支：

```powershell
git clone https://github.com/<你的账号>/winenv.git
cd winenv
npm install --global pnpm@11.25.0
pnpm install --frozen-lockfile
pnpm docs:dev
```

提交文档 Pull Request 前运行：

```sh
pnpm test:docs
pnpm docs:build
```

修改导航、样式或语言切换时，再执行浏览器检查：

```sh
pnpm exec playwright install chromium
pnpm docs:test
```

修改 PowerShell 行为时，还需要 Windows 11 和 PowerShell 7：

```powershell
pwsh -NoProfile -File ./scripts/test.ps1
powershell.exe -NoProfile -File ./scripts/test-windows-powershell.ps1
pnpm docs:build
```

CI 在 Linux 上执行文档和浏览器检查，在相关文件变化时执行 Windows 运行时检查。文档构建验证元数据、JSON 示例、语言配对、站内链接、资源以及已发布网址和锚点的兼容性。翻译变更检查提醒贡献者复核中文对应页，但不能判断译文准确性。单独修正译文不要求重写英文。

根目录规范文件保留权威正文，文档站社区页面只做导读并链接过去，不单独维护完整副本。[文档维护指南](https://yangyus8.top/winenv/zh/community/documentation/)说明内容结构和质量检查。

## 保持修改聚焦

- 一个 Pull Request 只解决一组相互关联的问题。
- 保留与本次工作无关的用户和仓库修改。
- 行为变化与回归修复要补测试。
- 内部函数只放在一个职责模块中；模块边界变化时同步更新架构测试。
- 日常命令保持简短；合理情况下继续兼容完整动作名。
- 不静默提权、不削弱 Windows 安全设置、不扩大信任决定。
- 不提交个人 Profile、凭据、下载安装器、生成后的文档、`VERSION` 或手工修改的 `CHANGELOG.md`。

## 英文与简体中文

英文是源码消息、仓库规范和文档根目录的权威语言。简体中文是正式支持的产品语言，不是随缘维护的附件。

修改用户可见内容时：

1. 先完成英文源码消息或页面；
2. CLI 输出同步更新 `locales/zh-CN.json`；
3. 同步更新 `docs/src/content/docs/zh/` 下对应页面；
4. 命令、参数、包 ID、路径和代码示例通常保持原样；
5. 运行国际化和文档检查。

仓库规范的中文译本使用 `.zh-CN.md` 后缀。术语与评审规则见[翻译指南](https://yangyus8.top/winenv/zh/community/i18n)。

## 提交与发布

使用 Conventional Commits：

```text
feat: add automatic locale selection
fix: preserve profile language during migration
docs: explain third-party bucket trust
test: cover localized table output
chore: refresh development metadata
```

只有有意引入不兼容修改时才使用 `feat!:` 或 `BREAKING CHANGE:`。如果能让历史更清楚，请在合并前压缩探索性提交。

`main` 分支自动发布。semantic-release 会决定版本、生成更新日志和 tag、发布带校验的资产、执行安装冒烟测试，最后部署 GitHub Pages。贡献者不应自行创建发布提交或 tag。

## Pull Request 检查表

- 说明用户问题与最终行为。
- 链接相关 Issue。
- 必要时说明安全、兼容、迁移和回滚影响。
- 包含测试和中英文用户可见内容。
- 确认本地检查通过。
- 根据评审意见继续修改。

提交贡献表示你同意按仓库的 [MIT License](./LICENSE) 授权，并遵守[行为准则](./CODE_OF_CONDUCT.zh-CN.md)。
