param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet('log', 'list', 'filter', 'timeline', 'export', 'verify', 'cleanup', 'review')]
    [string]$Command,

    [string]$DshHome = '',
    [string]$Type = '',
    [string]$PluginId = '',
    [string]$Detail = '',
    [string]$Operator = 'user',
    [string]$Before = '',
    [string]$After = '',
    [string]$Result = '',
    [string]$Evidence = '',
    [string]$Session = '',
    [int]$Limit = 50,
    [string]$Since = '',
    [int]$Days = 30,
    [string]$Out = ''
)

$ErrorActionPreference = 'Stop'

function Resolve-DshHome {
    if ($DshHome) { return $DshHome }
    if ($env:DSH_HOME) { return $env:DSH_HOME }
    return Join-Path $env:USERPROFILE '.dsh'
}

function Get-AuditFile {
    $dshHomePath = Resolve-DshHome
    return Join-Path $dshHomePath 'audit\audit.jsonl'
}

function Get-Sha256Text([string]$Text) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Read-Records {
    $file = Get-AuditFile
    if (-not (Test-Path -LiteralPath $file)) { return @() }
    $records = @()
    foreach ($line in (Get-Content -LiteralPath $file -Encoding UTF8)) {
        if (-not $line.Trim()) { continue }
        try { $records += ($line | ConvertFrom-Json) } catch { }
    }
    return $records
}

function Write-Utf8NoBom([string]$Path, [string]$Text) {
    [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false)))
}

function Append-Utf8NoBom([string]$Path, [string]$Line) {
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::AppendAllText($Path, $Line + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
}

function Invoke-Log {
    $file = Get-AuditFile
    $records = @(Read-Records)
    $seq = 1
    if ($records.Count -gt 0) { $seq = [int]$records[-1].seq + 1 }
    $prevHash = ''
    if ($records.Count -gt 0) {
        $lines = @(Get-Content -LiteralPath $file -Encoding UTF8 | Where-Object { $_.Trim() })
        $prevHash = Get-Sha256Text $lines[-1]
    }
    $ts = (Get-Date).ToUniversalTime().ToString('o')
    $rec = [ordered]@{
        seq      = $seq
        ts       = $ts
        operator = $Operator
        type     = $Type
        pluginId = $PluginId
        detail   = $Detail
        before   = $Before
        after    = $After
        result   = $Result
        evidence = $Evidence
        session  = $Session
        prevHash = $prevHash
        selfHash = ''
    }
    $json = $rec | ConvertTo-Json -Compress
    $selfHash = Get-Sha256Text ($json -replace '"selfHash":""', '"selfHash":""')
    $finalJson = $json -replace '"selfHash":""', ('"selfHash":"' + $selfHash + '"')
    Append-Utf8NoBom $file $finalJson
    Write-Host "[audit] logged seq=$seq type=$Type result=$Result plugin=$PluginId file=$file"
}

function Format-Record($Record) {
    $detail = if ($Record.detail) { $Record.detail } else { '' }
    $plugin = if ($Record.pluginId) { $Record.pluginId } else { '-' }
    return ('[{0}] {1} | {2} | {3} | {4} | {5}' -f $Record.seq, $Record.ts, $Record.type, $plugin, $Record.result, $detail)
}

function Invoke-List {
    $records = @(Read-Records)
    if ($records.Count -eq 0) { Write-Host '[audit] no records'; return }
    $records | Select-Object -Last $Limit | ForEach-Object { Write-Host (Format-Record $_) }
    Write-Host "[audit] total=$($records.Count) shown=$([Math]::Min($Limit, $records.Count))"
}

function Invoke-Filter {
    $records = @(Read-Records)
    $filtered = @($records | Where-Object {
        ($Type -eq '' -or $_.type -eq $Type) -and
        ($PluginId -eq '' -or $_.pluginId -eq $PluginId) -and
        ($Result -eq '' -or $_.result -eq $Result) -and
        ($Since -eq '' -or ([datetime]$_.ts) -ge ([datetime]$Since))
    })
    if ($filtered.Count -eq 0) { Write-Host '[audit] no matching records'; return }
    $filtered | Select-Object -Last $Limit | ForEach-Object { Write-Host (Format-Record $_) }
    Write-Host "[audit] matched=$($filtered.Count)"
}

function Invoke-Timeline {
    if (-not $PluginId) { throw 'timeline requires -PluginId' }
    $records = @(Read-Records | Where-Object { $_.pluginId -eq $PluginId })
    if ($records.Count -eq 0) { Write-Host "[audit] no records for plugin $PluginId"; return }
    $records | ForEach-Object { Write-Host (Format-Record $_) }
    Write-Host "[audit] timeline total=$($records.Count)"
}

function Invoke-Export {
    if (-not $Out) { throw 'export requires -Out' }
    $file = Get-AuditFile
    if (-not (Test-Path -LiteralPath $file)) { throw 'audit file does not exist' }
    $dir = Split-Path -Parent $Out
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Copy-Item -LiteralPath $file -Destination $Out -Force
    $count = @(Read-Records).Count
    Write-Host "[audit] exported $count records to $Out"
}

function Invoke-Verify {
    $file = Get-AuditFile
    if (-not (Test-Path -LiteralPath $file)) { Write-Host '[audit] no audit file (nothing to verify)'; return }
    $lines = @(Get-Content -LiteralPath $file -Encoding UTF8 | Where-Object { $_.Trim() })
    $bad = 0
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $obj = $line | ConvertFrom-Json
        if ($i -gt 0) {
            $expectedPrev = Get-Sha256Text $lines[$i - 1]
            if ($obj.prevHash -ne $expectedPrev) {
                Write-Host "[audit] CHAIN BREAK at line $($i + 1) (prevHash mismatch, seq=$($obj.seq))"
                $bad++
            }
        }
        $stripped = $line -replace '"selfHash":"[^"]*"', '"selfHash":""'
        if ((Get-Sha256Text $stripped) -ne $obj.selfHash) {
            Write-Host "[audit] SELF-HASH MISMATCH at line $($i + 1) (seq=$($obj.seq))"
            $bad++
        }
    }
    if ($bad -eq 0) {
        Write-Host "[audit] verify OK: $($lines.Count) records, chain intact"
    } else {
        Write-Host "[audit] verify FAILED: $bad problem(s)"
        exit 2
    }
}

function Invoke-Cleanup {
    $file = Get-AuditFile
    if (-not (Test-Path -LiteralPath $file)) { Write-Host '[audit] no audit file'; return }
    $records = @(Read-Records)
    if ($records.Count -eq 0) { Write-Host '[audit] no records'; return }
    $cutoff = (Get-Date).AddDays(-$Days)
    $keep = @($records | Where-Object { ([datetime]$_.ts) -ge $cutoff })
    $removed = $records.Count - $keep.Count
    if ($removed -eq 0) {
        Write-Host "[audit] cleanup: nothing older than $Days days"
        return
    }
    $lines = @()
    $prevHash = ''
    $seq = 0
    foreach ($r in $keep) {
        $seq++
        $rec = [ordered]@{
            seq      = $seq
            ts       = $r.ts
            operator = $r.operator
            type     = $r.type
            pluginId = $r.pluginId
            detail   = $r.detail
            before   = $r.before
            after    = $r.after
            result   = $r.result
            evidence = $r.evidence
            session  = $r.session
            prevHash = $prevHash
            selfHash = ''
        }
        $json = $rec | ConvertTo-Json -Compress
        $selfHash = Get-Sha256Text ($json -replace '"selfHash":""', '"selfHash":""')
        $finalJson = $json -replace '"selfHash":""', ('"selfHash":"' + $selfHash + '"')
        $lines += $finalJson
        $prevHash = Get-Sha256Text $finalJson
    }
    Write-Utf8NoBom $file ($lines -join [Environment]::NewLine)
    Write-Host "[audit] cleanup: removed $removed, kept $($keep.Count), chain re-chained"
    Invoke-Verify
}

function Invoke-Review {
    $records = @(Read-Records | Where-Object { $_.result -and $_.result -ne 'ok' })
    if ($records.Count -eq 0) { Write-Host '[audit] review: no problem records (all ok)'; return }
    Write-Host "[audit] review: $($records.Count) problem record(s)"
    $records | ForEach-Object { Write-Host (Format-Record $_) }
    Write-Host ''
    Write-Host 'Summary by type:'
    $records | Group-Object type | ForEach-Object {
        $fail = @($_.Group | Where-Object { $_.result -eq 'fail' }).Count
        Write-Host ("  {0}: {1} record(s), {2} failed" -f $_.Name, $_.Count, $fail)
    }
}

switch ($Command) {
    'log'     { Invoke-Log }
    'list'    { Invoke-List }
    'filter'  { Invoke-Filter }
    'timeline' { Invoke-Timeline }
    'export'  { Invoke-Export }
    'verify'  { Invoke-Verify }
    'cleanup' { Invoke-Cleanup }
    'review'  { Invoke-Review }
}
