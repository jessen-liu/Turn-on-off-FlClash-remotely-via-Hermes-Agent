# FlClash 远程开关

远程开关 Windows 上的 [FlClash](https://github.com/chen08209/FlClash) 代理。设计为通过聊天代理（飞书私信 / Telegram bot / Slack 等）触发，**不需要碰 GUI**。

> **一句话** —— 你在 FlClash GUI 上操作一次导入订阅，之后在任何聊天客户端发一句话就能开关代理。

[English version →](./README.md)

---

## 这是干嘛的

FlClash 是 Windows 上的 ClashMeta GUI 客户端。它托盘图标的"启动"按钮**无法**远程触发。本 skill **不模拟点击**（脆弱），而是**直接翻转 Windows 系统代理注册表位**（`HKCU\...\Internet Settings\ProxyEnable`）—— FlClash 启动 GUI 时已经把 `ProxyServer=127.0.0.1:7890` 写进注册表了，你只要切这一位就能开关代理。

难点是**"不能切到黑洞"**。v4 强制三道安全门：

1. **前置端口检查** —— 7890 不在 listen 就 **ABORT（退出 2）**，不碰注册表，流量保持直连
2. **真连通测试** —— 切完位后，通过 7890 拉一个已知可达的 URL。没拿到 HTTP 2xx/3xx 就**立刻回滚** ProxyEnable=0
3. **`off` 永远安全** —— 它就是写 0，恢复直连，没有前置条件

`status` 输出里的 `VPN tunnel: UP` 表示 **`ProxyEnable=1` 且 `7890 LISTENING` 两个同时满足**。任一单独成立都是误报（v2 脚本刚好演示过这种情况）。

---

## 系统要求

| 组件 | 要求 | 备注 |
|---|---|---|
| Windows | 10/11 | 注册表系统代理是 Windows 概念 |
| FlClash | 装好且在托盘常驻 | `C:\Program Files\FlClash\FlClash.exe` |
| FlClash 订阅 | 已配置 | Profiles 里至少有一个节点 |
| FlClash GUI "启动"按钮 | **点过至少一次** | 见下方"首次设置" |
| PowerShell 7 (`pwsh.exe`) | 强烈推荐 | PS 5.1 解析器 bug 会让这个脚本跑不起来 |

### 为什么要 PowerShell 7

脚本经过四次重写（v1 → v4）都是因为 **Windows PowerShell 5.1 解析器对嵌套 `if/else` + `exit` + 复杂字符串表达式有 bug**。它会在语法完全正确的情况下报"缺右大括号"。v4 通过以下方式绕开：

- 不写 `function Foo { param(...) }` 嵌套定义
- 不写 `switch ... case { exit } case` 多 case 块
- 不在字符串里用 `$(if-else)` 子表达式
- 配 `flclash.bat` 包装器强制走 `pwsh.exe`（PowerShell 7 的 .NET Core 解析器没这些 bug）

如果没装 pwsh 7，先装：

```cmd
choco install powershell-core -y
```

`flclash.bat` 包装器在 pwsh 7 找不到时会 fallback 到 `powershell.exe`（5.1），但脚本很可能解析失败。

---

## 首次设置（一次性）

1. **装 FlClash**：https://github.com/chen08209/FlClash/releases
2. **打开 FlClash GUI**（开始菜单）
3. 进 **Profiles** → 粘贴你的订阅链接 → 点刷新
4. 选一个节点
5. **点主界面大圆"启动"按钮**
6. 等 ~3 秒，托盘图标从灰变亮，系统代理状态切到"开"
7. **关掉 GUI 窗口**（或最小化到托盘），FlClash 服务在后台常驻

之后脚本就能开关代理，**再也不用打开 GUI**。

> **如果我不点"启动"会怎样？** —— 代理端口 7890 不会 listen。脚本的前置检查会 ABORT 并告诉你。注册表位保持 0，你电脑直连正常，但你**必须**做一次 GUI 点击。

---

## 安装

把 `skill/` 下的三个文件放到任意目录。然后：

### 方式 A：用 `.bat` 包装器（推荐）

```cmd
"C:\path\to\flclash.bat" on
"C:\path\to\flclash.bat" off
"C:\path\to\flclash.bat" status
```

包装器自动找 `C:\Program Files\PowerShell\7\pwsh.exe`，找不到时 fallback 到 `powershell.exe`。

### 方式 B：直接调 .ps1（你已经有 pwsh 7）

```powershell
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "C:\path\to\flclash-toggle.ps1" on
```

---

## 用法

### 通过聊天代理（飞书 DM）

对你的 agent 发**自然语言**。**不要用 `/flclash` 前缀** —— Hermes（以及大部分聊天 agent 平台）会把 `/...` 前缀当成平台命令。`/flclash` 没注册成平台命令，会被报"Unknown command /flclash"，用户消息根本到不了 skill。**用纯自然语言**：

```
开代理
关代理
代理状态
```

或更显式：

```
flclash 开
flclash 关
flclash 状态
```

或更自然：

```
帮我开代理
帮我关代理
看看代理开没开
```

你的聊天 agent 调 `flclash.bat`（或直接调 `flclash-toggle.ps1`），把 stdout 原样贴回聊天。

### 直接命令行

```cmd
:: on  —— 开代理（带三道安全门）
"C:\path\to\flclash.bat" on

:: off —— 关代理（永远安全）
"C:\path\to\flclash.bat" off

:: status —— 打印当前状态
"C:\path\to\flclash.bat" status
```

### 退出码

| 码 | 含义 |
|---|---|
| 0 | 成功 |
| 1 | 失败（切了位但不通 → 已回滚；或注册表写入失败） |
| 2 | ABORT（7890 不在 listen → **没碰注册表**） |

---

## 工作原理（技术细节）

### FlClash 架构

FlClash 是 Flutter 应用。两个进程：

- **`FlClash.exe`** —— GUI（Flutter，~70KB 桩 + `flutter_windows.dll`）
- **`FlClashCore.exe`** —— ClashMeta Go 内核，~46MB。启动时必带一个 Windows named pipe 参数，例如 `\\.\pipe\FlClashCore_8773`

它们通过那个 named pipe 通信。用户点 GUI 上的"启动"按钮，GUI 把配置 + 启动信号通过 pipe 发给 core，core 解析 Clash 配置、打开配置的端口（默认 7890）、开始代理。

FlClash GUI **不会**在进程启动时自动启动代理，即使 `vpnProps.enable=true` 在持久化状态里。**用户必须**在 GUI 上点过"启动"按钮。

这意味着你**不能** 100% 远程控制 FlClash。GUI 点击是引导步骤，做完之后脚本才能接管。

### Windows 系统代理位

FlClash 给 Clash 配置打了 patch，把自己注册成系统代理：

```
HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings
    ProxyEnable = 0 or 1 (DWORD)
    ProxyServer = "127.0.0.1:7890"
```

`ProxyEnable=1` 时，Chrome / Edge / curl / PowerShell 的 `Invoke-WebRequest` / Python 的 `urllib` 等所有 HTTP/HTTPS 请求都走 `127.0.0.1:7890`。`ProxyEnable=0` 时流量直连。

FlClash 在第一次 GUI 启动时把 `ProxyServer=127.0.0.1:7890` 写进注册表一次，之后不动。我们只切 `ProxyEnable`。

脚本还会调 `rundll32 wininet.dll,InternetSetOption 0 39 0` 和 `netsh winhttp reset proxy` 把变更广播给所有运行中的进程（让浏览器立刻刷新代理状态）。

### 为什么不能只信 `ProxyEnable=1`

经典 bug：你切了位，core 崩了，每个浏览器请求都挂在"connection refused"上。症状：整台电脑看起来断网了。

脚本的防御：**绝不切位，除非 7890 已经在接受连接**。如果你当前 bit=0 让我开，我**先**测 7890；失败就退出 2 给清晰消息，啥也不做。

如果当前 bit=0 是因为用户已经手动关了（7890 还活着），我也**先**测 7890。永远。

### `status` 输出含义

```
=== FlClash Status ===
  FlClash.exe     : RUNNING (PID xxxxx)            ← GUI 进程在
  FlClashCore.exe : RUNNING                        ← Core 进程在
  ProxyServer     : 127.0.0.1:7890                 ← 注册表里有 FlClash 的端口
  ProxyEnable     : 1                              ← 系统代理开了
  Port 7890       : LISTENING                      ← Core 真的在服务

  >>> VPN tunnel: UP                               ← 三者一致
```

如果 `ProxyEnable=1` 但 `Port 7890 NOT LISTENING`，你进入了黑洞状态。脚本的 `off` 命令立刻能恢复。**不要从这个状态再跑 `on`** —— 它会 ABORT 报同样的话。

### 为什么用 PowerShell 7 不用 5.1

开发过程中踩过的具体 bug：

| 写法 | PS 5.1 结果 | pwsh 7 结果 |
|---|---|---|
| `function Foo { param([int]$x) ... return ... }` | 解析器报"MissingEndCurlyBrace" | 正常 |
| `switch ($x) { "a" { ... exit 0 } "b" { ... } }` | 第一个 `exit` 后解析器报 | 正常 |
| `"text " + $(if ($x) {"A"} else {"B"})` 嵌套 if | 解析器报 | 正常 |

如果非要用 PS 5.1，准备花几小时追幽灵解析错误。装 pwsh 7。

---

## 限制和已知问题

1. **引导需要 GUI 点击。** FlClash Flutter 应用进程启动时**不**自动启动代理。第一次必须 GUI 点"启动"。之后脚本接管。要重新引导（进程重启后），只要在 GUI 上再点一次"启动"。

2. **FlClash 是单进程锁。** 同时只能跑一个 `FlClash.exe`。用户配置目录里的 `FlClash.lock` 文件强制这个限制。

3. **UIA 自动化对 FlClash 无效。** Flutter 桌面应用默认**不**向操作系统暴露 accessibility tree。你通过 UI Automation 或 `pywinauto` 找不到"启动"按钮。我们试过，找到 0 个控件。

4. **没有外部 IPC 命令可以调 FlClashCore。** `\\.\pipe\FlClashCore_<pid>` 协议是 FlClash 私有的，没有公开命令集。逆向不在本 skill 范围内。

5. **External controller 默认关闭。** FlClash 把 `external-controller: ""` 留空。如果你想用 HTTP API 控制（PUT /proxies 等），在 FlClash GUI → Settings → External Controller 开启。但那样你就不需要这个 skill 了。

6. **不支持 TUN 模式。** 这个脚本只控制系统代理模式。FlClash 的 TUN 模式（全设备 VPN）是另一个独立状态，本脚本不碰。

7. **订阅更新需要 GUI。** 你的订阅 URL 轮换节点时，必须打开 FlClash GUI 点刷新。本脚本不触发订阅刷新。

---

## 仓库结构

```
flclash-remote-toggle/
├── README.md                     ← 英文版（你正在看的链接）
├── README.zh-CN.md               ← 中文版（本文件）
├── LICENSE                       ← MIT
├── skill/                        ← 放到你的路径下
│   ├── SKILL.md                  ← 机器可读的 spec
│   ├── flclash-toggle.ps1        ← v4 脚本（要 pwsh 7）
│   └── flclash.bat               ← Windows 包装器，强制走 pwsh 7
└── examples/
    ├── hermes-config-snippet.md     ← Hermes 聊天 agent 的 YAML 片段
    └── feishu-natural-language.md   ← 触发 skill 的自然语言短语
```

---

## 协议

MIT
