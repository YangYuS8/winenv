---
title: "文档与发布自动化"
description: "Winenv 文档：文档与发布自动化。"
sidebar:
  order: 4
---

<span id="文档与发布自动化"></span>

Winenv 的版本、更新日志、Release 资产与文档站都从提交记录产生。日常维护不需要手工改版本号、复制更新日志或上传网页。

## 发布链路

推送或合并到 `main` 后：

1. `Release` workflow 验证 Profile、PowerShell 语法、行为、国际化与文档；
2. semantic-release 分析 Conventional Commits；
3. 有功能或修复时，自动更新 `VERSION` 与根目录 `CHANGELOG.md`；
4. 自动创建版本提交、Git tag、GitHub Release、ZIP 与 SHA-256；
5. 新版本通过从 GitHub Release 下载并安装的冒烟测试；
6. `Release` 记录最终提交 SHA（包括生成的发布提交）；成功结束后，`Pages` 读取记录并准确构建该提交。

Pages 等待 Release，是为了让刚生成的版本与更新日志出现在同一次部署中，不会在处理较早任务时取到无关的新 `main` 提交。`docs:` 等不产生版本的提交仍经过文档验证并更新站点；只涉及已识别文档路径时跳过原生运行时测试，未知路径和工作流修改仍保留完整运行时检查。

## 提交类型

```text
fix: 修复安装器路径                 # patch
feat: 添加新能力                    # minor
feat!: 修改不兼容的配置结构         # major
docs: 补充说明                      # 不发布版本，但更新文档站
chore: 更新维护配置                 # 不发布版本
```

准确描述变化即可，不要手工编辑 `VERSION`。

## 更新日志如何同步

根目录 `CHANGELOG.md` 是唯一来源。`pnpm docs:build` 会先运行 `scripts/sync-docs-changelog.mjs`，生成中英文页面外壳并调整标题层级，再交给 Astro Starlight 构建。具体发布条目保留 semantic-release 生成的英文原文，避免维护两份可能分叉的发布历史。

生成的 `docs/src/content/docs/changelog.md` 和 `docs/src/content/docs/zh/changelog.md` 都被 Git 忽略，避免仓库里出现需要手工同步的副本。

## 本地预览

使用 `.node-version` 记录的 Node.js 版本（或兼容的新版本），以及 `packageManager` 固定的 pnpm。跨平台[开发环境说明](https://github.com/YangYuS8/winenv/blob/main/CONTRIBUTING.zh-CN.md#开发环境)包含首次准备步骤：

```powershell
pnpm install --frozen-lockfile
pnpm docs:dev
```

提交前执行生产构建：

```powershell
pnpm docs:build
pnpm docs:preview
```

正文位于 `docs/src/content/docs/`，站点配置是 `docs/astro.config.mjs`，浏览器语言偏好脚本是 `docs/public/locale.js`。Starlight 提供导航、标准界面翻译、Pagefind 搜索与默认布局。内容和浏览器检查见[文档维护](/winenv/zh/community/documentation/)。

英文根目录是权威文档，简体中文镜像位于 `docs/src/content/docs/zh/`。用户可见内容应在同一个 Pull Request 中同步；完整规则见[翻译指南](/winenv/zh/community/i18n/)。

## 手动重发文档

正常情况下无需操作。GitHub Pages 临时失败时，可以在 Release 的源码记录仍保留的七天内重跑任务，或者在 `main` 上手动触发 Pages。手动任务构建触发时选定的确切提交，不跟随继续变化的分支头，也不依赖本地生成文件。
