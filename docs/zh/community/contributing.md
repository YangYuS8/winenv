# 参与贡献

Winenv 欢迎代码、测试、文档、翻译、Issue 分类以及经过认真设计的 Profile 示例。完整仓库规范见 [`CONTRIBUTING.zh-CN.md`](https://github.com/YangYuS8/winenv/blob/main/CONTRIBUTING.zh-CN.md)。

## 开始贡献前

1. 搜索已有 Issue 和文档。
2. 根据问题选择缺陷、功能、文档或使用问题表单。
3. 安全漏洞必须通过 [GitHub 私有公告表单](https://github.com/YangYuS8/winenv/security/advisories/new)报告。
4. 重要设计修改应先确认用户问题和边界，再投入实现。

## 本地验证

使用 Windows 11、PowerShell 7 和 Node.js 20 或更高版本：

```powershell
npm ci
pwsh -NoProfile -File ./scripts/test.ps1
powershell.exe -NoProfile -File ./scripts/test-windows-powershell.ps1
npm run docs:build
```

测试覆盖 Profile 组合、管理器路由、现有系统纳入、安装器信任规则、国际化和 Windows PowerShell 兼容性。生产文档构建会验证两种语言。

架构和 Provider 修改必须遵守 [RFC 0001](/zh/reference/architecture)。保持 `win.ps1` 为轻量兼容入口，并把实现函数放入对应的内部模块。

## Pull Request 要求

- 每个 Pull Request 只解决一个完整问题
- 行为修改包含测试
- 用户可见的英文与简体中文同步修改
- 明确说明安全、兼容和迁移影响
- 标题使用 Conventional Commits
- 不包含个人 Profile、凭据、下载的安装器、生成站点、手工 `VERSION` 或手工 `CHANGELOG.md` 修改

评审会考虑正确性、用户体验、信任边界、向后兼容、维护成本、测试和翻译完整度，而不只是代码能否运行。

## 项目规范

- [行为准则](https://github.com/YangYuS8/winenv/blob/main/CODE_OF_CONDUCT.zh-CN.md)
- [安全政策](https://github.com/YangYuS8/winenv/blob/main/SECURITY.zh-CN.md)
- [支持政策](https://github.com/YangYuS8/winenv/blob/main/SUPPORT.zh-CN.md)
- [项目治理](./governance)
- [翻译指南](./i18n)
