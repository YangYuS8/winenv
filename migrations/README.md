# Migrations

将一次性的环境演进脚本放在这里，并用递增编号命名：

```text
001-example.ps1
002-next-change.ps1
```

`winprofile.ps1 install` 和 `winprofile.ps1 update` 会按文件名顺序执行尚未记录的脚本。脚本成功结束后，文件名会写入 `%LOCALAPPDATA%\WinProfile\state.json`；已经成功的 migration 不会重复执行。

Migration 应当：

- 可以安全地在预期状态上运行；
- 检查旧状态再修改；
- 失败时返回非零退出码或抛出异常；
- 不包含密码、令牌或私人数据；
- 只处理配置结构变化，不承担普通软件更新。
