# 文档与发布自动化

Winenv 的版本、更新日志、Release 资产与文档站都从提交记录产生。日常维护不需要手工改版本号、复制更新日志或上传网页。

## 发布链路

推送或合并到 `main` 后：

1. `Release` workflow 验证 Profile、PowerShell 语法、行为、国际化与文档；
2. semantic-release 分析 Conventional Commits；
3. 有功能或修复时，自动更新 `VERSION` 与根目录 `CHANGELOG.md`；
4. 自动创建版本提交、Git tag、GitHub Release、ZIP 与 SHA-256；
5. 新版本通过从 GitHub Release 下载并安装的冒烟测试；
6. `Release` 成功结束后，`Pages` workflow 从最新 `main` 构建并部署文档。

Pages 之所以等待 Release，是为了让刚生成的版本和更新日志出现在同一次站点部署中。`docs:` 等不产生版本的提交也会经过 Release 验证并更新文档站。

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

根目录 `CHANGELOG.md` 是唯一来源。`npm run docs:build` 会先运行 `scripts/sync-docs-changelog.mjs`，生成中英文页面外壳并调整标题层级，再交给 VitePress 构建。具体发布条目保留 semantic-release 生成的英文原文，避免维护两份可能分叉的发布历史。

生成的 `docs/changelog.md` 和 `docs/zh/changelog.md` 都被 Git 忽略，避免仓库里出现需要手工同步的副本。

## 本地预览

需要 Node.js 20 或更高版本：

```powershell
npm ci
npm run docs:dev
```

提交前执行生产构建：

```powershell
npm run docs:build
npm run docs:preview
```

内容位于 `docs/`，站点配置位于 `docs/.vitepress/`。

英文根目录是权威文档，简体中文镜像位于 `docs/zh/`。用户可见内容应在同一个 Pull Request 中同步；完整规则见[翻译指南](/zh/community/i18n)。

## 手动重发文档

正常情况下不需要任何操作。如果 GitHub Pages 服务发生临时故障，可以在 Actions 页面手动运行 `Pages` workflow；它仍会从最新 `main` 构建，不依赖本地生成文件。
