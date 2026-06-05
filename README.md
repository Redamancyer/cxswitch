# CXSwitch

CXSwitch 是一个原生 macOS 菜单栏应用，用来在多个 Codex Desktop 账户之间切换，同时保持本地会话与配置完全共享。

它始终使用唯一的 `~/.codex`，切换时只替换 `~/.codex/auth.json`。CXSwitch 自己的配置和账户凭据保存在 `~/.cxswitch` 中。

## 功能

- 导入当前 Codex 账户，并通过浏览器添加或重新认证其他账户
- 切换前自动退出 Codex Desktop，写入目标账户凭据后自动重新启动
- 测试账户本地认证状态
- 显示并手动刷新官方 5 小时与每周剩余用量
- 每次启动 CXSwitch 时自动刷新所有账户用量
- 删除非当前账户

## 共享数据

- 本地会话与归档会话
- 项目、Worktree 和本地状态
- `config.toml`
- 插件、Skills、MCP 和 Memories

## 要求

- macOS 14 或更高版本
- Codex Desktop 安装在 `/Applications/Codex.app`
- Swift 6 工具链

## 构建与使用

1. 确保 Codex 使用文件认证存储。在 `~/.codex/config.toml` 中设置：

   ```toml
   cli_auth_credentials_store = "file"
   ```

2. 构建应用：

   ```bash
   ./scripts/build-app.sh
   ```

3. 启动：

   ```bash
   open dist/CXSwitch.app
   ```

4. 点击“导入当前账户”，然后点击“添加账户”完成其他账户的浏览器登录。

## 本地存储

CXSwitch 会创建以下额外文件：

- `~/.cxswitch/accounts.json`：账户列表和当前账户记录
- `~/.cxswitch/auth/<账户UUID>.json`：每个账户对应的 Codex `auth.json`

目录权限设置为 `700`，文件权限设置为 `600`。

## 切换行为

切换账户时，CXSwitch 会：

1. 退出 Codex Desktop。
2. 将当前 `auth.json` 保存回当前账户的 `~/.cxswitch/auth` 槽位。
3. 原子写入目标账户的 `auth.json`。
4. 重新启动 Codex Desktop。

切换不会修改 `~/.codex` 中的任何其他文件。

## 注意事项

- `~/.cxswitch/auth` 中保存的是可用于登录的明文认证凭据。请保护本机账户，并且不要同步、上传或分享该目录。
- 不要在 Codex 正在执行任务时切换。
- 不调用 `codex logout`，避免撤销保存的 Token。
- Cloud Tasks 和远程工作区资源仍然属于各自账户。
- 使用新账户继续旧本地会话时，会话上下文会发送到新账户对应的工作区。

## 仓库结构

- `Sources/`：SwiftUI/AppKit 应用源码
- `scripts/build-app.sh`：构建并打包 `dist/CXSwitch.app`
- `Package.swift`：Swift Package 配置
