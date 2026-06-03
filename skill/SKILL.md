---
name: flclash-toggle
description: 远程开关 FlClash（Windows 客户端）的代理通道。FlClash 装在 `C:\Program Files\FlClash\FlClash.exe` 且常驻托盘，本 skill 通过改 Windows 系统代理注册表（ProxyEnable）模拟"启动/停止"按钮效果。v3 起加了"前置验端口 + 切位后真连通测试 + 失败回滚"三重安全门，避免把电脑切到"代理黑洞"。
---

# flclash-toggle

## 这个 skill 解决什么

用户的 FlClash 平时常驻托盘（开机自启），需要上国际网时点"启动"按钮 = 切系统代理。**远程**无法操作托盘。

本 skill **不模拟点击托盘**（脆弱），而是直接改 Windows 注册表里的 `ProxyEnable` —— FlClash 提前把 `ProxyServer=127.0.0.1:7890` 配好，只切这一位代理就启用/停用。

## 怎么用

**重要：从飞书 DM 给我发自然语言**（不要带 `/` 前缀 —— Hermes 把 `/xxx` 当成平台管理命令截走）：

```
开代理
关代理
代理状态
```

或者更显式：

```
flclash 开
flclash 关
flclash 状态
```

或者直接说人话：

```
帮我开代理
帮我关代理
看看代理开没开
```

**直接命令行调用**（不用飞书也行）：

```cmd
:: 走 pwsh 7 (推荐, PS 5.1 解析器有 bug)
"%USERPROFILE%\.hermes\skills\flclash-toggle\scripts\flclash.bat" status
"%USERPROFILE%\.hermes\skills\flclash-toggle\scripts\flclash.bat" on
"%USERPROFILE%\.hermes\skills\flclash-toggle\scripts\flclash.bat" off

:: 走 pwsh 7 直接调
"C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\.hermes\skills\flclash-toggle\scripts\flclash-toggle.ps1" status
```

> ⚠️ **历史踩坑 1**：之前用的是 `/flclash on` 这种斜杠命令，**会和 Hermes 的管理命令系统冲突**（被识别为 `/flclash` 平台命令 → 报 "Unknown command /flclash"）。改成纯自然语言触发，不带斜杠，零歧义。
> 
> ⚠️ **历史踩坑 2**：脚本曾试图在 **Windows PowerShell 5.1** 下运行，但 PS 5.1 解析器对 `if ... { ... } exit ... } if ... { ... }` 嵌套组合 + 复杂字符串表达式会**误报"缺右大括号"**，即使语法完全正确。现在脚本里加了 `flclash.bat` 包装器强制用 **PowerShell 7 (`pwsh.exe`)** 跑，绕开这个 bug。pwsh 7 是用 `choco install powershell-core -y` 装的。

## 安全契约（v3，重要！必读）

`on` 命令有**三重安全门**，缺一就绝不切 ProxyEnable：

1. **前置端口检查**：执行 on 之前先 TCP 连 127.0.0.1:7890，**没人在 listen 直接 abort 退出 2**，绝不动注册表。这条防止"切到黑洞" —— 历史上发生过一次（2026-06-03），脚本乐观地把 ProxyEnable 改成 1，但 FlClash core 实际没启 mixed port，结果整个电脑断网。
2. **切位后真连通测试**：切完 ProxyEnable=1 后，用 .NET HttpClient 走 7890 拉一个白名单域名（cp.cloudflare.com / google.com/generate_204），**任何一条不通就立刻回滚到 0**，保证不会留下"切到位但代理不工作"的半状态。
3. **off 永远安全**：off 永远能成功 —— 它就是写 ProxyEnable=0，回直连。

> 🔑 **判断 VPN tunnel 真 UP 的唯一标准**：`ProxyEnable=1` **且** `Port 7890 LISTENING`。v3 的 status 脚本就是按这个标准算的。`VPN tunnel: UP` 但 `Port 7890 NOT LISTENING` 是不存在的状态（前置门已经挡掉了）。

## 前置条件（你必须先做一次）

1. **FlClash 装在 `C:\Program Files\FlClash\FlClash.exe`**（按你的安装路径调整）
2. **FlClash 设为开机自启 + 最小化到托盘**（FlClash 设置里有"开机启动"选项）
3. **第一次必须打开 FlClash GUI 点一次"启动"** —— 让 FlClash 把 `ProxyServer=127.0.0.1:7890` 写进注册表 + 让 core 启 mixed port
   - **不做这步的后果**：`on` 命令会在"前置端口检查"那里 abort 退出 2，告诉你"7890 没在 listen"。这是 v3 的预期行为 —— 不再做这步就别想 `on` 成功。
   - **GUI 启动过之后**：以后 `on`/`off` 都不需要再碰 GUI，纯切注册表位即可。
4. 验证：跑 `scripts/flclash-toggle.ps1 status`，看 `ProxyServer` 是不是 `127.0.0.1:7890` + `Port 7890` 是不是 `LISTENING`

## 副作用

- **不启 FlClash 进程**（你负责保证常驻托盘）
- **不动 FlClash 配置**（不动订阅、不切节点、不动 TUN/系统代理模式）
- **改的是 HKCU 注册表**（不需要管理员权限）
- **通知系统刷新代理**（调 `rundll32 wininet.dll,InternetSetOption` + `netsh winhttp reset proxy`），其他程序立刻生效

## 退出码

| 码 | 含义 |
|----|------|
| 0 | 成功（off 永远 0；on 表示切位 + 真连通测试都通过） |
| 1 | 失败（on 切位后真连通测试失败已自动回滚；或注册表写入失败） |
| 2 | 警告（环境异常：FlClash.exe 没跑 / ProxyServer 没配 / 7890 没 listen —— 这种情况下 `on` 不会切位） |

## 验证

在干净 cmd 里跑：

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\.hermes\skills\flclash-toggle\scripts\flclash-toggle.ps1" status
```

应输出（正常 UP 状态）：

```
=== FlClash Status ===
  FlClash.exe     : RUNNING (PID xxxxx)
  FlClashCore.exe : RUNNING
  ProxyServer     : 127.0.0.1:7890
  ProxyEnable     : 1
  Port 7890       : LISTENING

  >>> VPN tunnel: UP
```

如果 Port 7890 显示 NOT LISTENING，status 会多一行 `!!! WARNING` 提醒你"代理位开了但端口没起"，这种情况就是 v3 修的"黑洞"状态 —— 跑 `off` 立刻恢复直连。

## 关键发现（背景）

- FlClash 仓库 `chen08209/FlClash` ⭐40.9k（**注意：不是 fork，是上游** —— 上游 GitHub 链接的 star 数对得上）
- `FlClash.exe` (71KB) 是 Flutter GUI
- `FlClashCore.exe` (45.5MB) 是 ClashMeta Go 核心（panic stack trace 显示 `D:/a/FlClash/FlClash/core/server.go`，确认是 ClashMeta）
- `FlClashHelperService.exe` 没在跑 → **TUN 模式未启用** → 本 skill 假设使用 **系统代理模式**（ProxyEnable 控制）
- **7890 端口是真 listen 监听**（不是 lazy）。v3 之前的脚本里"7890 端口可能 lazy listen，别用端口测当判据"是**错的** —— 实测 `WinError 10061` 就是没人 listen，跟 lazy 无关。v3 改成"以端口 listen 为硬判据"。
- **PowerShell 5.1 兼容性坑（重要！）**：PS 5.1 解析器对以下**任意一种**都会误报"缺右大括号"（实际语法正确）：
  - `function Foo { ... 复杂函数体 ... }` 嵌套（v2 写法）
  - `switch ($x) { "case" { ... exit ... } "next" { ... } }` 多个 case + exit 组合（v3 写法）
  - 字符串内 `$(if-else)` 子表达式 + 嵌套 if 块 + exit 组合（v4 写法）
  
  **永久解法**：用 PowerShell 7 (`pwsh.exe`)，解析器是 .NET Core 写的，没这些 bug。v4 用 `flclash.bat` 包装器强制走 pwsh 7。
