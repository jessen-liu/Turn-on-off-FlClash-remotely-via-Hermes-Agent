@echo off
REM ============================================================
REM flclash.bat - Wrapper that runs flclash-toggle.ps1 via PowerShell 7 (pwsh)
REM
REM We must use pwsh 7 instead of Windows PowerShell 5.1 because
REM PS 5.1 parser has a bug: it misreports "missing closing brace"
REM on nested if/else blocks even when syntax is correct. v4 of the
REM script triggers this bug. pwsh 7 uses .NET Core and has a
REM new parser without this issue.
REM
REM pwsh 7 install path: C:\Program Files\PowerShell\7\pwsh.exe
REM Install: choco install powershell-core -y
REM ============================================================

setlocal
set "SCRIPT=C:\Users\Administrator\.hermes\skills\flclash-toggle\scripts\flclash-toggle.ps1"
set "PWSH=C:\Program Files\PowerShell\7\pwsh.exe"

if not exist "%PWSH%" (
  echo [ERROR] PowerShell 7 not found at "%PWSH%"
  echo         Install with: choco install powershell-core -y
  echo.
  set "PWSH=powershell.exe"
)

"%PWSH%" -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
exit /b %ERRORLEVEL%
