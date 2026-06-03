# flclash-toggle.ps1
# 远程开关 FlClash 代理通道(不动托盘、不动进程)
# 原理: FlClash 在"系统代理"模式下,"启动/停止"按钮等价于改
#       HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings\ProxyEnable
#       FlClash 提前把 ProxyServer 配成 127.0.0.1:7890,只要切这一位即可上/下国际网
#
# 安全契约(v4 重写):
#   - "on" 之前必须 7890 端口真在 listen,否则拒绝切位(避免把电脑切到黑洞)
#   - "on" 切位之后必须真连通外部(经代理 fetch 白名单域名),失败立刻回滚到 0
#   - "off" 切回 0 永远安全(恢复直连)
#   - PS 5.1 兼容: 完全不用 function 关键字(PS 5.1 嵌套函数体解析有 bug)
#   - PS 5.1 兼容: 不用 switch + exit 组合(PS 5.1 switch case 末尾的 exit 0 跟下一个 case 之间有歧义)
#   - PS 5.1 兼容: 不用 System.Net.Http.HttpClient(5.1 默认不加载),改用 HttpWebRequest
#
# 用法:
#   powershell -NoProfile -ExecutionPolicy Bypass -File flclash-toggle.ps1 status
#   powershell -NoProfile -ExecutionPolicy Bypass -File flclash-toggle.ps1 on
#   powershell -NoProfile -ExecutionPolicy Bypass -File flclash-toggle.ps1 off
#
# 退出码: 0=成功 1=失败 2=警告(环境异常)

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("on","off","status")]
    [string]$Action
)

$ProxyRegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
$ProxyEnableName = "ProxyEnable"
$ProxyServerName = "ProxyServer"
$FlClashProcess = "FlClash"
$ProxyPort = 7890

# ===== status 分支 =====
if ($Action -eq "status") {
    $flclashProc = Get-Process -Name $FlClashProcess -ErrorAction SilentlyContinue
    $flclashRunning = $null -ne $flclashProc
    $coreRunning = $null -ne (Get-Process -Name "FlClashCore" -ErrorAction SilentlyContinue)
    $proxyEnable = (Get-ItemProperty -Path $ProxyRegPath -Name $ProxyEnableName -ErrorAction SilentlyContinue).$ProxyEnableName
    $proxyServer = (Get-ItemProperty -Path $ProxyRegPath -Name $ProxyServerName -ErrorAction SilentlyContinue).$ProxyServerName

    $portListening = $false
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $iar = $tcp.BeginConnect("127.0.0.1", $ProxyPort, $null, $null)
        $portListening = $iar.AsyncWaitHandle.WaitOne(500, $false) -and $tcp.Connected
        $tcp.Close()
    } catch {
        $portListening = $false
    }

    Write-Host "=== FlClash Status ==="
    if ($flclashRunning) {
        Write-Host ("  FlClash.exe     : RUNNING (PID " + $flclashProc.Id + ")")
    } else {
        Write-Host "  FlClash.exe     : NOT RUNNING"
    }
    if ($coreRunning) {
        Write-Host "  FlClashCore.exe : RUNNING"
    } else {
        Write-Host "  FlClashCore.exe : NOT RUNNING"
    }
    if ($proxyServer) {
        Write-Host ("  ProxyServer     : " + $proxyServer)
    } else {
        Write-Host "  ProxyServer     : <not configured>"
    }
    Write-Host ("  ProxyEnable     : " + $proxyEnable)
    if ($portListening) {
        Write-Host ("  Port $ProxyPort       : LISTENING")
    } else {
        Write-Host ("  Port $ProxyPort       : NOT LISTENING")
    }
    $vpnUp = ($proxyEnable -eq 1) -and $portListening
    Write-Host ""
    if ($vpnUp) {
        Write-Host "  >>> VPN tunnel: UP"
    } else {
        Write-Host "  >>> VPN tunnel: DOWN"
    }
    if (($proxyEnable -eq 1) -and (-not $portListening)) {
        Write-Host "  !!! WARNING: ProxyEnable=1 but 7890 is NOT listening. Your traffic is going to a black hole. Run 'off' to recover."
    }
    exit 0
}

# ===== on 分支 =====
if ($Action -eq "on") {
    # 前置检查: 必须全过才切位
    $proxyServer = (Get-ItemProperty -Path $ProxyRegPath -Name $ProxyServerName -ErrorAction SilentlyContinue).$ProxyServerName
    if (-not $proxyServer) {
        Write-Warning "ABORT: ProxyServer not configured. Open FlClash GUI once, click 'Start' so it writes 127.0.0.1:7890 to the registry, then retry."
        exit 2
    }
    $flclashRunning = $null -ne (Get-Process -Name $FlClashProcess -ErrorAction SilentlyContinue)
    if (-not $flclashRunning) {
        Write-Warning "ABORT: FlClash.exe is not running. Start FlClash from the tray (or set it to auto-start) before turning the proxy on. This script only toggles the proxy bit, it does not start the process."
        exit 2
    }

    $portUp = $false
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $iar = $tcp.BeginConnect("127.0.0.1", $ProxyPort, $null, $null)
        $portUp = $iar.AsyncWaitHandle.WaitOne(500, $false) -and $tcp.Connected
        $tcp.Close()
    } catch {
        $portUp = $false
    }
    if (-not $portUp) {
        Write-Warning "ABORT: Port $ProxyPort is NOT listening. FlClash core is alive but the proxy port is not up."
        Write-Warning "  Cause: FlClash GUI 'Start' button has never been pressed, OR the core is still initializing."
        Write-Warning "  Fix:   Open FlClash GUI -> click 'Start' (启动) once. The 7890 port will come up."
        Write-Warning "  After that, retry: flclash on"
        Write-Warning "  (If we toggled ProxyEnable=1 now, your entire system traffic would go to a dead port and you'd lose all internet access. NOT doing that.)"
        exit 2
    }

    # 切位
    Set-ItemProperty -Path $ProxyRegPath -Name $ProxyEnableName -Value 1 -Type DWord
    $null = rundll32.exe wininet.dll,InternetSetOption 0 39 0 0
    $null = rundll32.exe wininet.dll,InternetSetOption 0 37 0 0
    $null = netsh.exe winhttp reset proxy 2>&1 | Out-Null
    Start-Sleep -Milliseconds 800

    # 切位之后真连通测试,失败立刻回滚
    # 用 .NET Framework 自带的 HttpWebRequest (PS 5.1 一直可用, 不需要 Add-Type)
    $testUrls = @(
        "http://www.msftconnecttest.com/connecttest.txt",
        "http://nmcheck.gnome.org/check_network_status.txt"
    )
    $checkOk = $false
    $checkUrl = ""
    $checkCode = 0
    foreach ($u in $testUrls) {
        try {
            $req = [System.Net.HttpWebRequest]::Create($u)
            $req.Proxy = New-Object System.Net.WebProxy("http://127.0.0.1:$ProxyPort")
            $req.Timeout = 5000
            $req.ReadWriteTimeout = 5000
            $req.Method = "GET"
            $req.UserAgent = "Mozilla/5.0 (FlClashToggle/4)"
            $resp = $req.GetResponse()
            $code = [int]$resp.StatusCode
            $resp.Close()
            if ($code -ge 200 -and $code -lt 400) {
                $checkOk = $true
                $checkUrl = $u
                $checkCode = $code
                break
            }
        } catch {
            # 试下一个
        }
    }

    if (-not $checkOk) {
        Write-Warning "ROLLED BACK: ProxyEnable=1 was set, but proxy is not actually reachable through 7890. Reverting to 0 to restore direct internet."
        Set-ItemProperty -Path $ProxyRegPath -Name $ProxyEnableName -Value 0 -Type DWord
        $null = rundll32.exe wininet.dll,InternetSetOption 0 39 0 0
        $null = rundll32.exe wininet.dll,InternetSetOption 0 37 0 0
        $null = netsh.exe winhttp reset proxy 2>&1 | Out-Null
        exit 1
    }

    Write-Host ("OK VPN tunnel is UP (verified via " + $checkUrl + " -> HTTP " + $checkCode + ")")
    exit 0
}

# ===== off 分支 =====
if ($Action -eq "off") {
    Set-ItemProperty -Path $ProxyRegPath -Name $ProxyEnableName -Value 0 -Type DWord
    $null = rundll32.exe wininet.dll,InternetSetOption 0 39 0 0
    $null = rundll32.exe wininet.dll,InternetSetOption 0 37 0 0
    $null = netsh.exe winhttp reset proxy 2>&1 | Out-Null
    Start-Sleep -Milliseconds 500
    Write-Host "OK VPN tunnel is DOWN (back to direct internet)"
    exit 0
}

# 不应该到这里, param 校验会挡住
Write-Error "Unknown action: $Action"
exit 1
