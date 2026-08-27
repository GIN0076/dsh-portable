#requires -Version 5.1

# 停止 DSH-Portable：清理 Electron 壳与其子进程（DSH web 服务），并释放端口。
# 入口：{app}\停止DSH-Portable.cmd  ->  scripts\stop-dsh.ps1

$ErrorActionPreference = 'Continue'

$appRoot = Split-Path -Parent $PSScriptRoot
$port = 3080

function Stop-Tree {
  param([int]$ProcId)
  if ($ProcId -le 0) { return }
  & taskkill /pid $ProcId /T /F 2>$null | Out-Null
}

# 1) 按端口兜底：找到 127.0.0.1:3080 的监听者并结束整棵进程树
$listeners = netstat -ano 2>$null |
  Select-String ("127.0.0.1:{0}" -f $port) |
  ForEach-Object { ($_.Line -split '\s+') | Select-Object -Last 1 } |
  Where-Object { $_ -match '^\d+$' } |
  Sort-Object -Unique
foreach ($procId in $listeners) {
  Stop-Tree ([int]$procId)
}

# 2) 按命令行定位本安装目录下的 electron 壳 / node 服务，确保全部结束
$procs = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
  Where-Object {
    ($_.Name -eq 'electron.exe' -or $_.Name -eq 'node.exe') -and
    $_.CommandLine -and
    ($_.CommandLine.IndexOf($appRoot, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
  }
foreach ($p in $procs) {
  Stop-Tree ([int]$p.ProcessId)
}

Write-Host 'DSH-Portable 已停止。' -ForegroundColor Green
