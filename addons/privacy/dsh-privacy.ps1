param(
    [ValidateSet('status', 'reset-id', 'backup', 'restore', 'cleanup-audit')]
    [string]$Command = 'status',

    [string]$DshHome = '',
    [string]$ProgramRoot = '',
    [string]$Out = '',
    [int]$Days = 90,
    [switch]$Force = $false
)

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $ProgramRoot) {
    $ProgramRoot = (Resolve-Path (Join-Path $ScriptDir '..\..')).Path
}
if (-not $DshHome) {
    if ($env:DSH_HOME) { $DshHome = $env:DSH_HOME }
    else { $DshHome = Join-Path $env:USERPROFILE '.dsh' }
}

$AuditScript = Join-Path $ScriptDir '..\audit\dsh-audit.ps1'
$IdFile = Join-Path $DshHome '.anonymous-user-id'
$AuditFile = Join-Path $DshHome 'audit\audit.jsonl'

function Write-Line([string]$Message) {
    Write-Host ("[privacy] " + $Message)
}

function Get-UtcStamp {
    return (Get-Date).ToUniversalTime().ToString('o')
}

function Write-Utf8NoBom([string]$Path, [string]$Text) {
    [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false)))
}

function Write-Audit {
    param(
        [string]$Type,
        [string]$Detail,
        [string]$Before = '',
        [string]$After = '',
        [string]$Result = 'ok',
        [string]$PluginId = 'dsh-privacy'
    )
    try {
        & $AuditScript log -Type $Type -PluginId $PluginId -Detail $Detail -Before $Before -After $After `
            -Result $Result -Session $env:CODEX_SESSION_ID -DshHome $DshHome | Out-Null
    } catch {
        Write-Host "[privacy] WARN: audit log failed: $($_.Exception.Message)"
    }
}

function Get-MaskedId([string]$Id) {
    if (-not $Id) { return '(none)' }
    if ($Id.Length -le 8) { return '****' }
    return $Id.Substring(0, 4) + '****' + $Id.Substring($Id.Length - 4)
}

function Get-TelemetryMode {
    if ($env:DSH_TELEMETRY_MODE) { return $env:DSH_TELEMETRY_MODE }
    return 'DISABLED (default)'
}

function Get-AuditStats {
    if (-not (Test-Path -LiteralPath $AuditFile)) {
        return [pscustomobject]@{ Count = 0; SizeKB = 0 }
    }
    $count = 0
    foreach ($line in (Get-Content -LiteralPath $AuditFile -Encoding UTF8)) {
        if ($line.Trim()) { $count++ }
    }
    $size = (Get-Item -LiteralPath $AuditFile).Length / 1KB
    return [pscustomobject]@{ Count = $count; SizeKB = [Math]::Round($size, 1) }
}

function Invoke-Status {
    Write-Line "DSH_HOME       : $DshHome"
    Write-Line ''

    Write-Line '--- Telemetry ---'
    Write-Line "mode           : $(Get-TelemetryMode)"
    Write-Line 'control        : env var DSH_TELEMETRY_MODE (LIVE/ON_DEMAND/DISABLED); DISABLED is the official default'
    Write-Line ''

    Write-Line '--- Anonymous user id ---'
    if (Test-Path -LiteralPath $IdFile) {
        $id = (Get-Content -LiteralPath $IdFile -Raw -Encoding UTF8).Trim()
        Write-Line "file           : $IdFile"
        Write-Line "value          : $(Get-MaskedId $id)"
        Write-Line 'usage          : shared by telemetry export, /feedback ack, and DeepSeek request header x-deepseek-harness-user-id'
    } else {
        Write-Line 'value          : (not created yet)'
        Write-Line "note           : created on first telemetry/feedback/DeepSeek request at $IdFile"
    }
    Write-Line ''

    Write-Line '--- Feedback / sharing ---'
    Write-Line 'feedback       : recorded locally in session logs; acknowledged with anonymous user id'
    Write-Line 'export         : only happens when telemetry mode is LIVE (current mode off by default)'
    Write-Line ''

    $audit = Get-AuditStats
    Write-Line '--- Audit ledger ---'
    Write-Line "records        : $($audit.Count)"
    Write-Line "size           : $($audit.SizeKB) KB"
    Write-Line "file           : $AuditFile"
    Write-Line ''

    Write-Line '--- Backups ---'
    $backupRoot = Join-Path $ProgramRoot 'backups'
    if (Test-Path -LiteralPath $backupRoot) {
        Get-ChildItem -LiteralPath $backupRoot -Directory | Sort-Object LastWriteTime -Descending |
            ForEach-Object { Write-Line ("  {0}  ({1})" -f $_.Name, $_.LastWriteTime.ToString('yyyy-MM-dd HH:mm')) }
    } else {
        Write-Line '  (no backups yet)'
    }
    Write-Line ''
    Write-Line 'commands: reset-id | backup -Out <path> | restore -Out <path> [-Force] | cleanup-audit -Days N'
}

function Invoke-ResetId {
    $old = ''
    if (Test-Path -LiteralPath $IdFile) {
        $old = (Get-Content -LiteralPath $IdFile -Raw -Encoding UTF8).Trim()
        Remove-Item -LiteralPath $IdFile -Force
        Write-Line "removed old id: $(Get-MaskedId $old)"
    }
    $new = [guid]::NewGuid().ToString()
    $dir = Split-Path -Parent $IdFile
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Write-Utf8NoBom $IdFile $new
    Write-Line "new id written: $(Get-MaskedId $new)"
    Write-Line "file: $IdFile"
    Write-Audit -Type privacy.reset-id -Detail 'anonymous user id reset' -Before (Get-MaskedId $old) -After (Get-MaskedId $new) -Evidence $IdFile
}

function Invoke-Backup {
    if (-not (Test-Path -LiteralPath $DshHome)) {
        throw "nothing to back up: $DshHome does not exist"
    }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $target = $Out
    $isZip = $false
    if (-not $target) {
        $target = Join-Path $ProgramRoot ("backups\dsh-data-backup-$stamp")
    } elseif ($target.ToLowerInvariant().EndsWith('.zip')) {
        $isZip = $true
    }

    if ($isZip) {
        $staging = Join-Path $env:TEMP ('dsh-backup-staging-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $staging -Force | Out-Null
        try {
            & robocopy $DshHome $staging /E /XJ /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
            if ($LASTEXITCODE -ge 8) { throw "robocopy failed (exit $LASTEXITCODE)" }
            $zipDir = Split-Path -Parent $target
            if (-not (Test-Path -LiteralPath $zipDir)) { New-Item -ItemType Directory -Path $zipDir -Force | Out-Null }
            Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $target -Force
        } finally {
            Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
        }
    } else {
        $parent = Split-Path -Parent $target
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        & robocopy $DshHome $target /E /XJ /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
        if ($LASTEXITCODE -ge 8) { throw "robocopy failed (exit $LASTEXITCODE)" }
    }
    $size = if (Test-Path -LiteralPath $target) { (Get-Item -LiteralPath $target).Length / 1MB } else { 0 }
    Write-Line "backup written: $target ($([Math]::Round($size, 1)) MB)"
    Write-Audit -Type privacy.backup -Detail 'data backup exported' -After $target -Evidence $target
}

function Invoke-CleanupAudit {
    & $AuditScript cleanup -Days $Days -DshHome $DshHome
    if (-not $?) { throw 'audit cleanup failed' }
    Write-Audit -Type privacy.cleanup-audit -Detail ("audit retention cleanup, days=$Days")
}

function Invoke-Restore {
    $source = $Out
    if (-not $source) {
        $backupRoot = Join-Path $ProgramRoot 'backups'
        $source = Get-ChildItem -LiteralPath $backupRoot -Directory -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1 -ExpandProperty FullName
        if (-not $source) { throw "no backup found under $backupRoot" }
    }
    if (-not (Test-Path -LiteralPath $source)) { throw "backup not found: $source" }

    if (Test-Path -LiteralPath $DshHome) {
        $hasItems = ($null -ne (Get-ChildItem -LiteralPath $DshHome -Force -ErrorAction SilentlyContinue | Select-Object -First 1))
        if ($hasItems -and -not $Force) {
            throw "data directory not empty: $DshHome (use -Force to overwrite)"
        }
        if ($Force) {
            Remove-Item -LiteralPath $DshHome -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    New-Item -ItemType Directory -Path $DshHome -Force | Out-Null

    if ($source.ToLowerInvariant().EndsWith('.zip')) {
        $staging = Join-Path $env:TEMP ('dsh-restore-staging-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $staging -Force | Out-Null
        try {
            Expand-Archive -Path $source -DestinationPath $staging -Force
            & robocopy $staging $DshHome /E /XJ /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
            if ($LASTEXITCODE -ge 8) { throw "robocopy failed (exit $LASTEXITCODE)" }
        } finally {
            Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
        }
    } else {
        & robocopy $source $DshHome /E /XJ /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
        if ($LASTEXITCODE -ge 8) { throw "robocopy failed (exit $LASTEXITCODE)" }
    }

    Write-Line "restored from: $source -> $DshHome"
    Write-Audit -Type privacy.restore -Detail 'data backup restored' -After $DshHome
}

switch ($Command) {
    'status'        { Invoke-Status }
    'reset-id'      { Invoke-ResetId }
    'backup'        { Invoke-Backup }
    'restore'       { Invoke-Restore }
    'cleanup-audit' { Invoke-CleanupAudit }
}
