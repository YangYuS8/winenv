## What and why / 修改内容与原因

<!-- Describe the user problem and the resulting behavior. / 说明用户问题和修改后的行为。 -->

## Validation / 验证

<!-- List exact commands and relevant manual checks. / 列出实际执行的命令和人工检查。 -->

- [ ] Runtime changes: `pwsh -NoProfile -File ./scripts/test.ps1` / 运行时修改。
- [ ] Runtime changes: `powershell.exe -NoProfile -File ./scripts/test-windows-powershell.ps1` / 运行时修改。
- [ ] `pnpm test:docs`
- [ ] `pnpm docs:build`
- [ ] UI changes: `pnpm docs:test` / 界面修改。

## Checklist / 检查表

- [ ] The change is focused and linked to an issue when appropriate. / 修改范围聚焦，并在适用时关联 Issue。
- [ ] Behavior changes include tests and compatibility or migration notes. / 行为变化包含测试以及兼容或迁移说明。
- [ ] User-facing English and Simplified Chinese are updated together. / 用户可见的英文和简体中文已同步更新。
- [ ] No credentials, personal profiles, generated docs, `VERSION`, or manual changelog edits are included. / 不包含凭据、个人 Profile、生成文档、`VERSION` 或手工更新日志。
- [ ] New trust, privilege, or destructive behavior is explicit and documented. / 新增信任、权限或破坏性行为已明确说明。

By submitting, I agree to the MIT License and Code of Conduct. / 提交即表示同意 MIT License 与行为准则。
