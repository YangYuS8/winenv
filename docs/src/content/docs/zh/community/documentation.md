---
title: 文档维护
description: 编写、翻译、检查并自动发布 Winenv 文档，不维护相互重复的权威来源。
sidebar:
  order: 4
---

站点使用 Astro Starlight 和 pnpm，部署为静态 GitHub Pages。贡献者编辑文字不需要 CMS、服务器或安装 Winenv。

## 先确定内容职责

- **教程：**安全、完整的学习练习，例如[第一次使用](/winenv/zh/guide/first-steps/)。
- **指南：**解决具体任务或问题，包括[故障排查](/winenv/zh/guide/troubleshooting/)。
- **参考：**准确的命令、参数、存储路径和约束。
- **解释：**说明模型为什么如此设计，例如[声明与归属](/winenv/zh/concepts/profiles-and-ownership/)。

这些职责借鉴 [Diátaxis](https://diataxis.fr/)。先确定读者需求，再写内容；不要仅为了填满模板而创建空栏目。

## 权威来源

正文位于 `docs/src/content/docs/`，中文对应页放在 `zh/`，保持相同文件名与扩展名。优先使用 Markdown，只有 Starlight 组件确实有帮助时才使用 MDX，例如首页。通过 frontmatter 设置清晰的 `title`、`description` 和 `sidebar.order`。

根目录规范保留权威正文，站点规范页面做摘要并链接过去。`CHANGELOG.md` 由 semantic-release 生成，`pnpm docs:sync` 生成两个语言的站点外壳。不要手改外壳、`VERSION` 或发布历史。站点跟随成功的 Release 工作流记录的源码提交，包括自动生成的发布提交。用户支持渠道只覆盖最新稳定版 Winenv；文档站不是旧版手册档案库。

站内链接使用 `/winenv/.../`，中文使用 `/winenv/zh/.../`。保留已发布的页面与标题锚点，或者明确添加兼容别名。`scripts/docs-legacy-routes.json` 记录迁移前的公开路径和锚点，不要为了通过检查直接删掉记录。

## 本地检查

按照[开发环境说明](https://github.com/YangYuS8/winenv/blob/main/CONTRIBUTING.zh-CN.md#开发环境)准备工具后：

```sh
pnpm docs:dev
pnpm test:docs
pnpm docs:build
```

构建检查页面元数据、JSON 示例、翻译配对、HTML 站内链接、资源和锚点。它不会执行安装示例，也不保证外部网站可用。英文修改需要在同一组变更中更新中文对应页；应复核并完成对应修改，而不是更新无意义的时间戳。语义准确性仍需要人工评审。

修改界面时，先运行 `pnpm exec playwright install chromium`，再执行 `pnpm docs:test`。测试使用生产预览，因为 Pagefind 搜索索引在生产构建时生成，不是开发服务器功能。测试覆盖语言检测与记忆、深层链接、搜索、移动导航和自动无障碍冒烟检查。自动检查不是完整的无障碍认证。

## 依赖与发布政策

`.node-version` 和 `packageManager` 固定工具链，`pnpm-lock.yaml` 是唯一的依赖锁文件。CI 使用 `--frozen-lockfile` 安装。依赖构建脚本需明确授权，新版本至少等待 24 小时，信任降级会被阻止；经过复核的例外必须在 `pnpm-workspace.yaml` 中限定到准确版本。

`pnpm audit signatures` 检查注册表签名，这不表示每个依赖的构建来源都已独立验证。信任降级策略只是额外信号，不是软件安全的证明。需要评审锁文件变化，并限制安全例外范围。

发布继续交给现有 GitHub Actions，不额外启用 pnpm 的发布系统、Changesets，也不手工上传站点产物。文档提交不需要提升 Winenv 版本。
