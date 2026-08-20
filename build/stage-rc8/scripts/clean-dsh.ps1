#requires -Version 5.1

# 清理 DSH-Portable：停止进程 -> 删除快捷方式 -> 可选删数据目录 -> 启动卸载器删除安装目录。
# 入口：{app}\清理DSH-Portable.cmd  ->  scripts\clean-dsh.ps1
# 参数：-DeleteData 直接删数据目录；-KeepData 直接保留；不带参数则交互询问。

param(
  [switch]$DeleteData,
  [switch]$KeepData
)

$ErrorActionPreference = 'Continue'

$appRoot = Split-Path -Parent $PSScriptRoot

function Get-RealDesktop {
  try {
    $p = [Environment]::GetFolderPath('Desktop')
    if ($p -and (Test-Path -LiteralPath $p)) { return $p }
  } catch {}
  try {
    $v = (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -Name 'Desktop' -ErrorAction Stop).Desktop
    if ($v) {
      $v = [Environment]::ExpandEnvironmentVariables($v)
      if (Test-Path -LiteralPath $v) { return $v }
    }
  } catch {}
  return $null
}

# 1) 先停止
& (Join-Path $PSScriptRoot 'stop-dsh.ps1')

# 2) 删除桌面与开始菜单快捷方式（桌面路径用 GetFolderPath + 注册表兜底，不硬编码）
$desktop = Get-RealDesktop
if ($desktop) {
  Remove-Item -LiteralPath (Join-Path $desktop 'DSH-Portable.lnk') -Force -ErrorAction SilentlyContinue
}
$startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\DSH-Portable'
Remove-Item -LiteralPath $startMenu -Recurse -Force -ErrorAction SilentlyContinue

# 3) 解析数据目录：优先 launcher-config.json，否则默认 ~/.dsh
$dataDir = $null
$cfg = Join-Path $appRoot 'shell\launcher-config.json'
if (Test-Path -LiteralPath $cfg) {
  try { $dataDir = (Get-Content -LiteralPath $cfg -Raw | ConvertFrom-Json).dataDir } catch {}
}
if (-not $dataDir) { $dataDir = Join-Path $env:USERPROFILE '.dsh' }

$doDelete = $DeleteData.IsPresent
if (-not $DeleteData.IsPresent -and -not $KeepData.IsPresent) {
  Write-Host "数据目录：$dataDir"
  Write-Host '是否同时删除数据目录（含 API Key / 凭据 / 审计日志）？'
  Write-Host '  输入 DELETE 并回车 = 删除；直接回车 = 保留。'
  $answer = Read-Host '选择'
  $doDelete = ($answer -eq 'DELETE')
}

if ($doDelete -and $dataDir -and (Test-Path -LiteralPath $dataDir)) {
  Remove-Item -LiteralPath $dataDir -Recurse -Force -ErrorAction SilentlyContinue
  Write-Host '已删除数据目录。'
} else {
  Write-Host '已保留数据目录。'
}

# 4) 启动卸载器（静默）删除安装目录与注册表项；卸载器负责自删。
$un = Get-ChildItem -LiteralPath $appRoot -Filter 'unins*.exe' -ErrorAction SilentlyContinue |
  Select-Object -First 1
if ($un) {
  Start-Process -FilePath $un.FullName -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART') -WindowStyle Hidden
  Write-Host '已启动卸载，安装目录将被移除。'
} else {
  Write-Host '未找到卸载器，请手动删除安装目录。'
}
