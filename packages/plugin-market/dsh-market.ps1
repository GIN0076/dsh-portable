param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet('search', 'info', 'install', 'installed')]
    [string]$Command,

    [string]$Query = '',
    [string]$Package = '',
    [string]$Version = '',
    [string[]]$Approve = @(),
    [switch]$DryRun,
    [string]$LocalPath = '',
    [string]$Profile = 'web',
    [string]$DshHome = '',
    [string]$Mirror = 'https://registry.npmmirror.com',
    [string]$ReportOut = '',
    [string]$GateOut = '',
    [string]$NodeDir = '',
    [string]$ProgramRoot = '',
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

# JSON 输出（-Json）给 GUI 消费：强制 UTF-8，避免中文描述在 OEM 代码页下乱码。
if ($Json) {
    try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }
}

$Approve = @($Approve | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $ProgramRoot) { $ProgramRoot = (Resolve-Path (Join-Path $ScriptDir '..\..')).Path }
if (-not $DshHome) {
    if ($env:DSH_HOME) { $DshHome = $env:DSH_HOME }
    else { $DshHome = Join-Path $env:USERPROFILE '.dsh' }
}
$NodeBin = Join-Path $ProgramRoot 'runtime\node\node.exe'
$CliBin = Join-Path $ProgramRoot 'src\apps\cli\lib\bin.js'
$ReviewScript = Join-Path $ScriptDir '..\plugin-review\review-plugin.ps1'
$AuditScript = Join-Path $ScriptDir '..\audit\dsh-audit.ps1'

# Node/npm 解析：Portable 应优先使用内置 runtime\node，不依赖系统安装的 Node；
# 其次回退到系统全局 Node，最后依赖 PATH 中的 npm.cmd。
if (-not $NodeDir) {
    $builtinNode = Join-Path $ProgramRoot 'runtime\node'
    if (Test-Path -LiteralPath (Join-Path $builtinNode 'npm.cmd')) {
        $NodeDir = $builtinNode
    } elseif (Test-Path -LiteralPath 'C:\Program Files\nodejs\npm.cmd') {
        $NodeDir = 'C:\Program Files\nodejs'
    } else {
        $NodeDir = ''
    }
}

function Write-Audit {
    param(
        [string]$Type,
        [string]$Detail,
        [string]$PluginId = '',
        [string]$Result = 'ok',
        [string]$Evidence = ''
    )
    try {
        & $AuditScript log -Type $Type -PluginId $PluginId -Detail $Detail -Result $Result `
            -Evidence $Evidence -Session $env:CODEX_SESSION_ID -DshHome $DshHome | Out-Null
    } catch {
        Write-Host "[market] WARN: audit failed: $($_.Exception.Message)"
    }
}

# 防 SSRF：仅允许 http/https，且目标 host 不得是 localhost / 回环 / 私有 / 保留地址。
function Assert-SafeUrl([string]$Url) {
    $uri = $null
    if (-not [System.Uri]::TryCreate($Url, [System.UriKind]::Absolute, [ref]$uri)) {
        throw "unsafe URL (not absolute): $Url"
    }
    if ($uri.Scheme -ne 'http' -and $uri.Scheme -ne 'https') {
        throw "unsafe URL scheme ($($uri.Scheme)): $Url"
    }
    $hostName = $uri.DnsSafeHost
    if ($hostName -ieq 'localhost') { throw "unsafe URL host (localhost): $Url" }
    $ip = $null
    if ([System.Net.IPAddress]::TryParse($hostName, [ref]$ip)) {
        if ([System.Net.IPAddress]::IsLoopback($ip)) { throw "unsafe URL host (loopback): $Url" }
        $bytes = $ip.GetAddressBytes()
        if ($ip.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork) {
            if ($bytes[0] -eq 10) { throw "unsafe URL host (private 10/8): $Url" }
            if ($bytes[0] -eq 172 -and $bytes[1] -ge 16 -and $bytes[1] -le 31) { throw "unsafe URL host (private 172.16/12): $Url" }
            if ($bytes[0] -eq 192 -and $bytes[1] -eq 168) { throw "unsafe URL host (private 192.168/16): $Url" }
            if ($bytes[0] -eq 169 -and $bytes[1] -eq 254) { throw "unsafe URL host (link-local 169.254/16): $Url" }
            if ($bytes[0] -eq 0) { throw "unsafe URL host (0.0.0.0): $Url" }
            if ($bytes[0] -ge 224) { throw "unsafe URL host (multicast/reserved): $Url" }
        }
    }
    return $uri
}

function Get-PackageDownloads([string]$Package) {
    # npm downloads API（npmmirror 镜像同源）；失败时返回 0，不阻断主流程。
    try {
        $url = "$Mirror/downloads/point/last-month/$([uri]::EscapeDataString($Package))"
        $null = Assert-SafeUrl $url
        $r = Invoke-RegistryJson $url
        if ($r.downloads -is [int] -or $r.downloads -is [long]) { return [long]$r.downloads }
        return 0
    } catch {
        return 0
    }
}

function Invoke-RegistryJson([string]$Url) {
    $null = Assert-SafeUrl $Url
    # 优先 .NET（schannel）；失败自动降级内置 Node（OpenSSL/undici fetch）
    try {
        return Invoke-RestMethod -Uri $Url -TimeoutSec 30
    } catch {
        Write-Host "[market] .NET fetch failed ($($_.Exception.Message)); retrying via built-in Node (OpenSSL)..."
        $json = & $NodeBin -e 'fetch(process.argv[1]).then(r=>{if(!r.ok)process.exit(2);return r.text()}).then(t=>process.stdout.write(t)).catch(()=>process.exit(3))' $Url 2>$null
        if ($LASTEXITCODE -ne 0) { throw "registry fetch failed for $Url" }
        return (($json -join '') | ConvertFrom-Json)
    }
}

function Invoke-Search {
    if (-not $Query) { throw 'search requires -Query' }
    $url = "$Mirror/-/v1/search?text=$([uri]::EscapeDataString($Query))&size=15"
    $r = Invoke-RegistryJson $url
    if ($Json) {
        $items = @($r.objects | ForEach-Object {
            $p = $_.package
            $keywords = @()
            if ($p.keywords) { $keywords = @($p.keywords | ForEach-Object { [string]$_ }) }
            $downloads = Get-PackageDownloads $p.name
            # popularity：以月下载量为依据归一化到 0..1（10 万/月封顶）。
            $popularity = [Math]::Min(1.0, $downloads / 100000.0)
            [pscustomobject]@{
                name = $p.name
                version = $p.version
                description = $p.description
                publisher = $p.publisher.username
                date = $p.date
                keywords = $keywords
                downloads = $downloads
                popularity = [Math]::Round($popularity, 3)
            }
        })
        $items | ConvertTo-Json -Depth 5 -Compress
        return
    }
    Write-Host "[market] search '$Query': $($r.total) hit(s), showing up to 15"
    foreach ($obj in $r.objects) {
        $p = $obj.package
        $desc = if ($p.description) { $p.description.Substring(0, [Math]::Min(90, $p.description.Length)) } else { '' }
        Write-Host ("  {0}@{1}  {2}" -f $p.name, $p.version, $desc)
    }
}

function Invoke-Info {
    if (-not $Package) { throw 'info requires -Package' }
    $url = "$Mirror/$Package"
    $r = Invoke-RegistryJson $url
    if ($Json) {
        $latestVer = $r.versions.($r.'dist-tags'.latest)
        $deps = @{}
        if ($latestVer.dependencies) { $latestVer.dependencies.PSObject.Properties | ForEach-Object { $deps[$_.Name] = $_.Value } }
        $keywords = @()
        if ($r.keywords) { $keywords = @($r.keywords | ForEach-Object { [string]$_ }) }
        $downloads = Get-PackageDownloads $r.name
        $popularity = [Math]::Min(1.0, $downloads / 100000.0)
        [pscustomobject]@{
            name = $r.name
            latest = $r.'dist-tags'.latest
            license = $r.license
            description = $r.description
            repository = $r.repository.url
            keywords = $keywords
            downloads = $downloads
            popularity = [Math]::Round($popularity, 3)
            dependencies = $deps
        } | ConvertTo-Json -Depth 5 -Compress
        return
    }
    Write-Host "[market] $($r.name)"
    Write-Host "  latest   : $($r.'dist-tags'.latest)"
    Write-Host "  license  : $($r.license)"
    Write-Host "  desc     : $($r.description)"
    if ($r.repository.url) { Write-Host "  repo     : $($r.repository.url)" }
    $latestVer = $r.versions.($r.'dist-tags'.latest)
    if ($latestVer.dependencies) {
        Write-Host '  deps     :'
        $latestVer.dependencies.PSObject.Properties | ForEach-Object { Write-Host ("    {0} {1}" -f $_.Name, $_.Value) }
    }
}

function Invoke-Install {
    if (-not $Package -and -not $LocalPath) { throw 'install requires -Package or -LocalPath' }
    if ($Package -and $LocalPath) { throw 'use either -Package or -LocalPath, not both' }

    $reviewDir = ''
    $tmp = Join-Path $env:TEMP ('dsh-market-' + [guid]::NewGuid().ToString('N'))
    try {
        if ($LocalPath) {
            $reviewDir = (Resolve-Path -LiteralPath $LocalPath).Path
            $localPkg = Join-Path $reviewDir 'package.json'
            if (-not $Package -and (Test-Path -LiteralPath $localPkg)) {
                try {
                    $p = Get-Content -LiteralPath $localPkg -Raw -Encoding UTF8 | ConvertFrom-Json
                    if ($p.name) { $Package = $p.name; if ($p.version) { $Version = $p.version } }
                } catch { }
            }
            if (-not $Package) { $Package = Split-Path -Leaf $reviewDir }
            Write-Host '[market] NOTE: -LocalPath is review-gate mode; real installs still need a published npm package'
        } else {
            $spec = if ($Version) { "$Package@$Version" } else { $Package }
            $extract = Join-Path $tmp 'extract'
            New-Item -ItemType Directory -Path $extract -Force | Out-Null
            Write-Host "[market] packing $spec ..."
            $packLog = Join-Path $tmp 'pack.log'
            $previousEap = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            Push-Location $tmp
            try {
                $npm = Join-Path $NodeDir 'npm.cmd'
                if (-not (Test-Path -LiteralPath $npm)) { $npm = 'npm.cmd' }
                # npm 缓存默认写系统 %LOCALAPPDATA%\npm-cache，受限/便携场景可能不可写；
                # 统一重定向到数据目录下，保证任何环境都能安装。
                if (-not $env:npm_config_cache) {
                    $env:npm_config_cache = Join-Path $DshHome '.npm-cache'
                }
                & $npm pack $spec --pack-destination $tmp --registry $Mirror *>> $packLog
                $packCode = $LASTEXITCODE
            } finally {
                Pop-Location
                $ErrorActionPreference = $previousEap
            }
            if ($packCode -ne 0) { throw "npm pack failed (exit $packCode); see $packLog" }
            $tgz = @(Get-ChildItem -LiteralPath $tmp -Filter '*.tgz' | Select-Object -First 1)
            if ($tgz.Count -eq 0) { throw 'npm pack produced no tarball' }
            & tar -xzf $tgz[0].FullName -C $extract
            if ($LASTEXITCODE -ne 0) { throw 'tarball extraction failed' }
            $reviewDir = Join-Path $extract 'package'
            if (-not (Test-Path -LiteralPath $reviewDir)) {
                $reviewDir = $extract
            }
        }

        Write-Host "[market] M2 review: $reviewDir"
        $report = if ($ReportOut) { $ReportOut } else { Join-Path $tmp ('review-' + (Split-Path -Leaf $reviewDir) + '.txt') }
        $approveArg = if ($Approve.Count -gt 0) { @('-Approve', ($Approve -join ',')) } else { @() }
        $gateArgs = if ($GateOut) { @('-GateOut', $GateOut) } else { @() }
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ReviewScript -Path $reviewDir `
            -DshHome $DshHome -ReportOut $report @approveArg @gateArgs
        $reviewExit = $LASTEXITCODE

        if ($reviewExit -eq 3) {
            Write-Audit -Type plugin.install -PluginId $Package -Detail 'REJECTED by M2 review' -Result 'fail' -Evidence $report
            throw "REJECTED by M2 review (see $report)"
        }
        if ($reviewExit -eq 2) {
            Write-Audit -Type plugin.install -PluginId $Package -Detail 'needs confirmation: risks not approved' -Result 'warn' -Evidence $report
            throw "M2 review needs confirmation (see $report); re-run install with -Approve <rule-ids>"
        }

        $spec = if ($Version) { "$Package@$Version" } else { $Package }
        $cliArgs = @($CliBin, 'plugin', '--profile', $Profile, 'add', $spec)
        Write-Host "[market] installing via: node $($cliArgs -join ' ') (DSH_HOME=$DshHome)"
        if ($DryRun) {
            Write-Host '[market] DRY RUN: not executing install'
            Write-Audit -Type plugin.install -PluginId $Package -Detail "dry-run install (M2 passed)" -Evidence $report
            return
        }

        $installLog = Join-Path $tmp 'install.log'
        $env:DSH_HOME = $DshHome
        $previousEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            & $NodeBin @cliArgs *>> $installLog
            $installCode = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $previousEap
        }
        if ($installCode -ne 0) {
            Write-Audit -Type plugin.install -PluginId $Package -Detail "install failed (exit $installCode)" -Result 'fail' -Evidence $installLog
            throw "dsh plugin add failed (exit $installCode); see $installLog"
        }
        Write-Host "[market] installed: $spec into profile '$Profile'"
        Write-Audit -Type plugin.install -PluginId $Package -Detail "installed into profile $Profile" -Evidence $report
    } finally {
        if ($tmp -and (Test-Path -LiteralPath $tmp)) {
            & $NodeBin -e "require('fs').rmSync(process.argv[1],{recursive:true,force:true})" $tmp 2>$null
        }
    }
}

function Invoke-Installed {
    $profileDir = Join-Path $DshHome "profiles\$Profile"
    $pkgPath = Join-Path $profileDir 'package.json'
    if (-not (Test-Path -LiteralPath $pkgPath)) {
        if ($Json) { '[]' | Write-Output; return }
        Write-Host "[market] profile '$Profile' has no package.json yet ($profileDir); no plugins installed"
        return
    }
    $pkg = Get-Content -LiteralPath $pkgPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $deps = @{}
    if ($pkg.dependencies) {
        $pkg.dependencies.PSObject.Properties | ForEach-Object { $deps[$_.Name] = $_.Value }
    }
    if ($pkg.devDependencies) {
        $pkg.devDependencies.PSObject.Properties | ForEach-Object { $deps[$_.Name] = $_.Value }
    }
    if ($Json) {
        @($deps.GetEnumerator() | Sort-Object Name | ForEach-Object {
            [pscustomobject]@{ name = $_.Key; version = $_.Value }
        }) | ConvertTo-Json -Depth 4 -Compress
        return
    }
    Write-Host "[market] plugins in profile '$Profile' ($profileDir): $($deps.Count)"
    $deps.GetEnumerator() | Sort-Object Name | ForEach-Object { Write-Host ("  {0} {1}" -f $_.Key, $_.Value) }
}

switch ($Command) {
    'search'    { Invoke-Search }
    'info'      { Invoke-Info }
    'install'   { Invoke-Install }
    'installed' { Invoke-Installed }
}
