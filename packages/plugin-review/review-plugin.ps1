param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [string]$Name = '',
    [string[]]$Approve = @(),
    [switch]$AuditDeps,
    [switch]$NoAudit,
    [switch]$ScanDeps,
    [string]$DshHome = '',
    [string]$RulesPath = '',
    [string]$AllowlistPath = '',
    [string]$MaliciousListPath = '',
    [string]$VulnListPath = '',
    [string]$ReportOut = '',
    [string]$GateOut = '',
    [string]$NodeDir = ''
)

$ErrorActionPreference = 'Stop'

# powershell.exe -File passes "A,B,C" as ONE string, not an array; normalize
# both real arrays and comma-separated strings.
$Approve = @($Approve | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $RulesPath) { $RulesPath = Join-Path $ScriptDir 'rules\rules.json' }
if (-not $AllowlistPath) { $AllowlistPath = Join-Path $ScriptDir 'allowlist.json' }
if (-not $MaliciousListPath) { $MaliciousListPath = Join-Path $ScriptDir 'malicious-hashes.json' }
if (-not $VulnListPath) { $VulnListPath = Join-Path $ScriptDir 'vuln-allowlist.json' }
if (-not $DshHome) {
    if ($env:DSH_HOME) { $DshHome = $env:DSH_HOME }
    else { $DshHome = Join-Path $env:USERPROFILE '.dsh' }
}
$AuditScript = Join-Path $ScriptDir '..\audit\dsh-audit.ps1'

# Node/npm 解析：优先内置 runtime\node（Portable 不依赖系统安装 Node），
# 其次系统全局 Node，最后依赖 PATH 中的 npm.cmd。
if (-not $NodeDir) {
    $builtinNode = Join-Path (Resolve-Path (Join-Path $ScriptDir '..\..')).Path 'runtime\node'
    if (Test-Path -LiteralPath (Join-Path $builtinNode 'npm.cmd')) {
        $NodeDir = $builtinNode
    } elseif (Test-Path -LiteralPath 'C:\Program Files\nodejs\npm.cmd') {
        $NodeDir = 'C:\Program Files\nodejs'
    } else {
        $NodeDir = ''
    }
}

$TextExtensions = @('.js', '.ts', '.mjs', '.cjs', '.jsx', '.tsx', '.mts', '.cts', '.json')
$BinaryExtensions = @('.exe', '.dll', '.bin', '.so', '.dylib', '.wasm', '.node', '.o', '.a', '.pyc')

function Read-JsonFile([string]$FilePath, [string]$FallbackJson = '{}') {
    if (-not (Test-Path -LiteralPath $FilePath)) {
        return ($FallbackJson | ConvertFrom-Json)
    }
    try {
        return (Get-Content -LiteralPath $FilePath -Raw -Encoding UTF8 | ConvertFrom-Json)
    } catch {
        return ($FallbackJson | ConvertFrom-Json)
    }
}

function Get-Snippet([string]$Line) {
    $s = $Line.Trim()
    if ($s.Length -gt 120) { $s = $s.Substring(0, 117) + '...' }
    return $s
}

function Add-Finding {
    param(
        [string]$RuleId,
        [string]$Tier,
        [string]$File,
        [int]$Line,
        [string]$Snippet,
        [string]$Desc
    )
    $script:Findings += [pscustomobject]@{
        RuleId  = $RuleId
        Tier    = $Tier
        File    = $File
        Line    = $Line
        Snippet = $Snippet
        Desc    = $Desc
    }
}

function Invoke-NpmAudit([string]$PluginRoot, [hashtable]$VulnAllowlist) {
    $pkg = Join-Path $PluginRoot 'package.json'
    $lock = Join-Path $PluginRoot 'package-lock.json'
    $nm = Join-Path $PluginRoot 'node_modules'
    if (-not (Test-Path -LiteralPath $pkg)) { return }
    $hasDeps = $false
    try {
        $p = Get-Content -LiteralPath $pkg -Raw -Encoding UTF8 | ConvertFrom-Json
        $hasDeps = $p.dependencies -or $p.devDependencies
    } catch { return }
    if (-not $hasDeps) { return }
    if (-not (Test-Path -LiteralPath $lock) -and -not (Test-Path -LiteralPath $nm)) {
        Write-Host '[review] npm audit skipped: no package-lock.json / node_modules'
        return
    }

    $auditLog = Join-Path $env:TEMP ('dsh-npm-audit-' + [guid]::NewGuid().ToString('N') + '.json')
    $previousEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    Push-Location $PluginRoot
    try {
        $npm = Join-Path $NodeDir 'npm.cmd'
        if (-not (Test-Path -LiteralPath $npm)) { $npm = 'npm.cmd' }
        & $npm audit --json *> $auditLog
        $auditCode = $LASTEXITCODE
    } finally {
        Pop-Location
        $ErrorActionPreference = $previousEap
    }

    if ($auditCode -eq 2 -or -not (Test-Path -LiteralPath $auditLog)) {
        Write-Host '[review] npm audit could not complete (offline or registry issue); dependency scan skipped'
        return
    }
    try {
        $audit = Get-Content -LiteralPath $auditLog -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 10
    } catch {
        Write-Host '[review] npm audit output unparseable; dependency scan skipped'
        return
    }
    if (-not $audit.vulnerabilities) { return }
    foreach ($entry in $audit.vulnerabilities.PSObject.Properties) {
        $key = $entry.Name
        $v = $entry.Value
        $severity = $v.severity
        $tier = if ($severity -eq 'high' -or $severity -eq 'critical') { 'RISK' } else { 'INFO' }
        $allowReason = $VulnAllowlist.packages.$key
        if ($allowReason) {
            Write-Host "[review] dependency $key ($severity) skipped by vuln-allowlist: $allowReason"
            continue
        }
        $title = $v.via[0].title
        if (-not $title) { $title = 'advisory' }
        Add-Finding -RuleId 'DEP-VULN' -Tier $tier -File $key -Line 0 -Snippet $title -Desc "npm audit $severity"
    }
}

if (-not (Test-Path -LiteralPath $Path)) {
    throw "plugin path not found: $Path"
}
if (-not (Test-Path -LiteralPath (Join-Path $Path 'package.json'))) {
    Write-Host '[review] WARN: no package.json in plugin root (assuming plain source folder)'
}

$pluginRoot = (Resolve-Path -LiteralPath $Path).Path
$pluginName = $Name
$pluginVersion = ''
$pkgJson = Join-Path $pluginRoot 'package.json'
if (Test-Path -LiteralPath $pkgJson) {
    try {
        $pkg = Get-Content -LiteralPath $pkgJson -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $pluginName -and $pkg.name) { $pluginName = $pkg.name }
        if ($pkg.version) { $pluginVersion = $pkg.version }
    } catch { }
}
if (-not $pluginName) { $pluginName = Split-Path -Leaf $pluginRoot }

$rules = @((Read-JsonFile $RulesPath).rules)
$allowlist = Read-JsonFile $AllowlistPath
$malicious = Read-JsonFile $MaliciousListPath
$vulnAllow = Read-JsonFile $VulnListPath
$allowedIds = @()
$allowReason = ''
if ($allowlist.plugins -and $allowlist.plugins.$pluginName) {
    $allowedIds = @($allowlist.plugins.$pluginName.allow)
    $allowReason = $allowlist.plugins.$pluginName.reason
    if ($allowedIds.Count -gt 0) {
        Write-Host "[review] allowlist hit for ${pluginName}: $($allowedIds -join ',') ($allowReason)"
    }
}

$script:Findings = @()
$allFiles = @(Get-ChildItem -LiteralPath $pluginRoot -Recurse -File -Force -ErrorAction SilentlyContinue |
    Where-Object { if ($ScanDeps) { $_.FullName -notmatch '\\.git\\' } else { $_.FullName -notmatch '\\.git\\|\\node_modules\\' } })

# Binary payloads (RED).
foreach ($file in $allFiles) {
    if ($BinaryExtensions -contains $file.Extension.ToLowerInvariant()) {
        Add-Finding -RuleId 'BINARY-PAYLOAD' -Tier 'RED' -File $file.FullName -Line 1 -Snippet $file.Name -Desc 'binary payload in package'
    }
}

# Malicious SHA-256 library (RED).
if ($malicious.files) {
    foreach ($file in $allFiles) {
        try {
            $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($malicious.files.$hash) {
                Add-Finding -RuleId 'MALICIOUS-HASH' -Tier 'RED' -File $file.FullName -Line 1 `
                    -Snippet $file.Name -Desc ("known malicious hash: " + $malicious.files.$hash)
            }
        } catch { }
    }
}

# Install scripts (RISK).
if (Test-Path -LiteralPath $pkgJson) {
    try {
        $pkg = Get-Content -LiteralPath $pkgJson -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($pkg.scripts) {
            foreach ($scriptName in @('install', 'preinstall', 'postinstall')) {
                if ($pkg.scripts.$scriptName) {
                    $lineNo = 1
                    $lines = @(Get-Content -LiteralPath $pkgJson -Encoding UTF8)
                    for ($i = 0; $i -lt $lines.Count; $i++) {
                        if ($lines[$i] -match "\`"$scriptName\`"") { $lineNo = $i + 1; break }
                    }
                    Add-Finding -RuleId 'INSTALL-SCRIPT' -Tier 'RISK' -File $pkgJson -Line $lineNo `
                        -Snippet $pkg.scripts.$scriptName -Desc "package.json $scriptName script"
                }
            }
        }
    } catch { }
}

# Regex rules on text files.
$textFiles = @($allFiles | Where-Object { $TextExtensions -contains $_.Extension.ToLowerInvariant() })
foreach ($rule in $rules) {
    $patterns = @($rule.patterns)
    if ($patterns.Count -eq 0) { continue }
    foreach ($file in $textFiles) {
        $lines = @(Get-Content -LiteralPath $file.FullName -Encoding UTF8 -ErrorAction SilentlyContinue)
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            if ($rule.id -eq 'MINIFIED' -and $line.Length -gt 3000) {
                Add-Finding -RuleId 'MINIFIED' -Tier 'INFO' -File $file.FullName -Line ($i + 1) `
                    -Snippet (Get-Snippet $line) -Desc 'line longer than 3000 chars'
                break
            }
            foreach ($pat in $patterns) {
                if ($line -match $pat) {
                    $tier = $rule.tier
                    if ($rule.id -eq 'NET-EGRESS' -and $line -match 'localhost|127\.0\.0\.1|0\.0\.0\.0|\[::1\]') {
                        $tier = 'INFO'
                    }
                    Add-Finding -RuleId $rule.id -Tier $tier -File $file.FullName -Line ($i + 1) `
                        -Snippet (Get-Snippet $line) -Desc $rule.desc
                    break
                }
            }
        }
    }
}

# Optional dependency vulnerability scan.
if ($AuditDeps) {
    Invoke-NpmAudit $pluginRoot $vulnAllow
}

# Apply allowlist.
$findings = @($script:Findings | Where-Object { $allowedIds -notcontains $_.RuleId })
$skipped = $script:Findings.Count - $findings.Count
if ($skipped -gt 0) {
    Write-Host "[review] $skipped finding(s) removed by allowlist"
}

$red = @($findings | Where-Object { $_.Tier -eq 'RED' })
$risks = @($findings | Where-Object { $_.Tier -eq 'RISK' -and $Approve -notcontains $_.RuleId })
$info = @($findings | Where-Object { $_.Tier -eq 'INFO' })

$reportLines = @()
$reportLines += "[review] plugin=$pluginName version=$pluginVersion path=$pluginRoot"
$reportLines += "[review] files=$($allFiles.Count) findings=$($findings.Count) (red=$($red.Count) risk=$($risks.Count) info=$($info.Count))"
foreach ($f in $findings) {
    $short = $f.File
    if ($short.StartsWith($pluginRoot)) { $short = $short.Substring($pluginRoot.Length).TrimStart('\') }
    $reportLines += ("  [{0}] {1,-18} {2}:{3}  {4}" -f $f.Tier, $f.RuleId, $short, $f.Line, (Get-Snippet $f.Snippet))
}

if ($red.Count -gt 0) {
    $decision = 'REJECT'
    $reportLines += "Decision: REJECT ($($red.Count) red flag(s))"
} elseif ($risks.Count -gt 0) {
    $decision = 'CONFIRM'
    $reportLines += "Decision: CONFIRM ($($risks.Count) unapproved risk(s)); approve with -Approve $((@($risks | ForEach-Object { $_.RuleId } | Sort-Object -Unique) -join ','))"
} else {
    $decision = 'ALLOW'
    $reportLines += 'Decision: ALLOW (no red flags, all risks approved)'
}

# Runtime gate suggestion (official ctx.approval consumer contract).
$runtimeIds = @($findings | Where-Object { $_.RuleId -in @('CHILD-PROC', 'NET-EGRESS', 'DYN-EXEC', 'OOB-WRITE') } |
    ForEach-Object { $_.RuleId } | Sort-Object -Unique)
if ($runtimeIds.Count -gt 0) {
    $reportLines += "Runtime gate: $($runtimeIds -join ',') (enforce via ctx.approval.request at runtime; see docs/m2-review.md)"
    if ($GateOut) {
        $gate = [ordered]@{ schemaVersion = 1; plugin = $pluginName; version = $pluginVersion; runtimeApis = @($runtimeIds) }
        [System.IO.File]::WriteAllText($GateOut, ($gate | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding($false)))
        $reportLines += "Runtime gate file written: $GateOut"
    }
}

$reportText = $reportLines -join [Environment]::NewLine
Write-Host $reportText
if ($ReportOut) {
    $dir = Split-Path -Parent $ReportOut
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllText($ReportOut, $reportText, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "[review] report saved: $ReportOut"
}

if (-not $NoAudit) {
    $summary = "findings=$($findings.Count) red=$($red.Count) risk=$($risks.Count)"
    $evidence = if ($ReportOut) { $ReportOut } else { '' }
    & $AuditScript log -Type plugin.review -PluginId $pluginName -Detail $summary -Before '' -After $pluginVersion `
        -Result $decision.ToLowerInvariant() -Evidence $evidence -DshHome $DshHome | Out-Null
}

if ($red.Count -gt 0) { exit 3 }
if ($risks.Count -gt 0) { exit 2 }
exit 0
