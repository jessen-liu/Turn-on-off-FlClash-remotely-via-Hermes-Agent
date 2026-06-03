# FlClash Remote Toggle

Remote on/off control for [FlClash](https://github.com/chen08209/FlClash) proxy on Windows. Designed to be invoked from a chat agent (e.g. Feishu DM, Telegram bot, Slack) without touching the GUI.

> **TL;DR** — You operate FlClash GUI once to import your subscription, then drive the proxy on/off from any chat client by sending the right phrase.

[中文版 →](./README.zh-CN.md)

---

## What this does

FlClash is a ClashMeta GUI client for Windows. Its tray-icon "Start" button cannot be triggered from a remote session. This skill **doesn't simulate a click** (fragile), it **flips the Windows system proxy registry bit** (`HKCU\...\Internet Settings\ProxyEnable`) that FlClash has already configured with `ProxyServer=127.0.0.1:7890`. One bit flip = proxy on, flip back = proxy off.

The hard part is **not flipping into a black hole**. v4 enforces a three-stage safety contract:

1. **Pre-flight port check** — if 7890 isn't listening, ABORT (exit 2). No registry flip. Your traffic stays on direct connection.
2. **Real connectivity test** — after flipping the bit, fetch a known-good URL through 7890. If it doesn't return HTTP 2xx/3xx, **immediately roll back** the bit to 0.
3. **`off` is always safe** — it just writes 0, restoring direct connection. No preconditions.

The "VPN tunnel: UP" status output means **both** `ProxyEnable=1` **and** `7890 LISTENING`. Either alone is a false positive (and v2 of this script demonstrated exactly that).

---

## Requirements

| Component | Required | Notes |
|---|---|---|
| Windows | 10/11 | Registry-based proxy is a Windows concept |
| FlClash | installed and running in tray | `C:\Program Files\FlClash\FlClash.exe` |
| FlClash subscription | configured | `Profiles` must have at least one node |
| FlClash GUI "Start" button | clicked at least once | See "Initial setup" below |
| PowerShell 7 (`pwsh.exe`) | recommended | PS 5.1 has parser bugs that break this script |

### Why PowerShell 7

The script went through four rewrites (v1 → v4) because **Windows PowerShell 5.1's parser is buggy on nested `if/else` + `exit` + complex string expressions**. It reports "missing closing brace" on perfectly valid syntax. v4 works around this by:

- No `function Foo { param(...) }` nested definitions
- No `switch ... case { exit } case` multi-case blocks
- No `$(if-else)` sub-expressions inside strings
- Wrapped in `flclash.bat` that forces `pwsh.exe` (PowerShell 7's .NET Core parser has none of these issues)

If you don't have pwsh 7, install it:

```cmd
choco install powershell-core -y
```

The `flclash.bat` wrapper falls back to `powershell.exe` (5.1) if pwsh 7 is missing, but the script will likely fail to parse.

---

## Initial setup (one-time)

1. **Install FlClash** from https://github.com/chen08209/FlClash/releases
2. **Open FlClash GUI** from the Start menu
3. Go to **Profiles** → paste your subscription URL → click refresh
4. Select a node
5. **Click the big round "Start" button** in the main UI
6. Wait ~3 seconds. You should see the tray icon change from gray to active and the system proxy status flip to "on"
7. **Close the GUI window** (or minimize to tray). The FlClash service stays in the background

After this, the script can flip the proxy on/off without ever opening the GUI again.

> **What if I never click "Start"?** — The proxy port 7890 will not be listening. The script's pre-flight check will ABORT and tell you so. The registry bit stays at 0. Your internet keeps working on direct connection. You have to do the GUI click at least once.

---

## Installation

Drop the three files from `skill/` into any directory. Then either:

### Option A: Use the `.bat` wrapper (recommended)

```cmd
"C:\path\to\flclash.bat" on
"C:\path\to\flclash.bat" off
"C:\path\to\flclash.bat" status
```

The wrapper auto-detects `pwsh.exe` at `C:\Program Files\PowerShell\7\pwsh.exe` and falls back to `powershell.exe` if not found.

### Option B: Call the .ps1 directly (if you have pwsh 7)

```powershell
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "C:\path\to\flclash-toggle.ps1" on
```

---

## Usage

### From a chat agent (e.g. Feishu DM)

Use **natural language** to your agent. **Do not use `/flclash` prefix** — Hermes (and most chat agent platforms) intercept any `/...` prefix as a platform command. Plain phrases work:

```
开代理
关代理
代理状态
```

Or explicit:

```
flclash 开
flclash 关
flclash 状态
```

Or natural:

```
帮我开代理
帮我关代理
看看代理开没开
```

Your chat agent should call `flclash.bat` (or `flclash-toggle.ps1` directly) and paste the stdout back to the chat.

### Direct command line

```cmd
:: on  — flip proxy on (with three-stage safety)
"C:\path\to\flclash.bat" on

:: off — flip proxy off (always safe)
"C:\path\to\flclash.bat" off

:: status — print current state
"C:\path\to\flclash.bat" status
```

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Failed (proxy enabled but unreachable → rolled back; or registry write failed) |
| 2 | Aborted (7890 not listening → did NOT touch registry) |

---

## How it works (technical details)

### The FlClash architecture

FlClash is a Flutter app. Two processes:

- **`FlClash.exe`** — the GUI (Flutter, ~70KB stub + `flutter_windows.dll`)
- **`FlClashCore.exe`** — the ClashMeta Go core, ~46MB. Always starts with a Windows named pipe argument, e.g. `\\.\pipe\FlClashCore_8773`

They communicate over that named pipe. When the user clicks "Start" in the GUI, the GUI sends a config + go signal over the pipe. The core parses the Clash config, opens the configured ports (7890 by default), and starts proxying.

The FlClash GUI **does NOT auto-start the proxy on process launch**, even if `vpnProps.enable=true` in its persisted state. The user must click "Start" in the GUI at least once after the process starts.

This means you **cannot** 100% remotely control FlClash. The GUI click is the bootstrap. After that, the script handles on/off.

### The Windows system proxy bit

FlClash patches the Clash config to register itself as the system proxy:

```
HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings
    ProxyEnable = 0 or 1 (DWORD)
    ProxyServer = "127.0.0.1:7890"
```

When `ProxyEnable=1`, every HTTP/HTTPS request from Chrome, Edge, curl, PowerShell's `Invoke-WebRequest`, Python's `urllib`, etc. gets routed to `127.0.0.1:7890`. When `ProxyEnable=0`, traffic goes direct.

FlClash writes `ProxyServer=127.0.0.1:7890` once (on first GUI start) and leaves it there. We just toggle `ProxyEnable`.

The script also calls `rundll32 wininet.dll,InternetSetOption 0 39 0` and `netsh winhttp reset proxy` to broadcast the change to all running processes (so browsers refresh their proxy state immediately).

### Why we don't trust `ProxyEnable=1` alone

The classic bug: you flip the bit, the core has crashed, every browser request hangs on a "connection refused" to a dead port. Symptom: your whole computer appears to be offline.

The script's defense: **never flip the bit unless 7890 is already accepting connections**. If the bit is currently 0 and you ask to turn on, we test 7890 first. If it fails, we exit 2 with a clear message and do nothing.

If the bit is currently 0 because the user already toggled it off (with 7890 still up), we still test 7890 first. Always.

### What the `status` output means

```
=== FlClash Status ===
  FlClash.exe     : RUNNING (PID xxxxx)            ← GUI process alive
  FlClashCore.exe : RUNNING                        ← Core process alive
  ProxyServer     : 127.0.0.1:7890                 ← Registry has FlClash's port
  ProxyEnable     : 1                              ← System proxy is enabled
  Port 7890       : LISTENING                      ← Core is actually serving

  >>> VPN tunnel: UP                               ← All three line up
```

If `ProxyEnable=1` but `Port 7890 NOT LISTENING`, you have a black-hole state. The script's `off` command fixes it immediately. **Do not run `on` from this state** — it will ABORT with the same message.

### Why PowerShell 7 and not 5.1

Concrete bugs that bit us during development:

| Pattern | PS 5.1 result | pwsh 7 result |
|---|---|---|
| `function Foo { param([int]$x) ... return ... }` | Parser error "MissingEndCurlyBrace" | Works |
| `switch ($x) { "a" { ... exit 0 } "b" { ... } }` | Parser error after first `exit` | Works |
| `"text " + $(if ($x) {"A"} else {"B"})` with nested if | Parser error | Works |

If you must use PS 5.1, expect to spend hours chasing ghost parse errors. Install pwsh 7.

---

## Limitations and known issues

1. **Bootstrap requires GUI click.** FlClash's Flutter app does not auto-start the proxy on process launch. The very first time, you must click "Start" in the GUI. After that, the script handles on/off. To re-bootstrap after a process restart, just click "Start" once in the GUI.

2. **FlClash is single-process-locked.** Only one `FlClash.exe` can run at a time. The `FlClash.lock` file in the user config directory enforces this.

3. **UIA automation does not work on FlClash.** Flutter apps do not expose their accessibility tree to the OS. You cannot find "the Start button" via UI Automation or `pywinauto`. We tried. It finds 0 controls.

4. **No IPC command to FlClashCore from outside.** The `\\.\pipe\FlClashCore_<pid>` protocol is private to FlClash. There's no public command set. Reverse-engineering it is out of scope.

5. **External controller is off by default.** FlClash leaves `external-controller: ""` empty. If you want HTTP API control (PUT /proxies etc.), enable it in FlClash GUI → Settings → External Controller. But then you don't need this skill at all.

6. **TUN mode is not supported.** This script only controls system proxy mode. FlClash's TUN mode (full-device VPN) is a separate state and this script does not touch it.

7. **Subscription updates require GUI.** When your subscription URL rotates nodes, you have to open FlClash GUI and click refresh. This script doesn't trigger subscription refresh.

---

## Repository layout

```
flclash-remote-toggle/
├── README.md                     ← English (you are here)
├── README.zh-CN.md               ← 中文版
├── LICENSE                       ← MIT
├── skill/                        ← drop these into your path
│   ├── SKILL.md                  ← machine-readable spec
│   ├── flclash-toggle.ps1        ← v4 script (pwsh 7 required)
│   └── flclash.bat               ← Windows wrapper, forces pwsh 7
└── examples/
    ├── hermes-config-snippet.yaml     ← YAML for Hermes chat agent
    └── feishu-natural-language.md     ← Phrases that map to commands
```

---

## License

MIT
