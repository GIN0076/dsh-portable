param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet('status', 'dict-add', 'dict-list', 'dict-remove', 'force-on', 'force-off', 'cache-clear', 'translate', 'export-override')]
    [string]$Command,

    [string]$DshHome = '',
    [string]$Name = '',
    [string]$Path = '',
    [string]$PluginId = '',
    [string]$Source = '',
    [string]$Lang = 'zh',
    [switch]$DryRun,
    [string]$Out = ''
)

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $DshHome) {
    if ($env:DSH_HOME) { $DshHome = $env:DSH_HOME }
    else { $DshHome = Join-Path $env:USERPROFILE '.dsh' }
}
$AuditScript = Join-Path $ScriptDir '..\audit\dsh-audit.ps1'

$TranslateRoot = Join-Path $DshHome 'translate'
$StateFile = Join-Path $TranslateRoot 'state.json'
$DictsDir = Join-Path $TranslateRoot 'dicts'
$OverrideFile = Join-Path $TranslateRoot 'override.json'
$CacheDir = Join-Path $TranslateRoot 'cache'
$ConfigFile = Join-Path $TranslateRoot 'config.json'

function Ensure-Dirs {
    New-Item -ItemType Directory -Path $DictsDir, $CacheDir -Force | Out-Null
}

function Read-JsonFile([string]$FilePath, [string]$FallbackJson = '{}') {
    if (-not (Test-Path -LiteralPath $FilePath)) { return ($FallbackJson | ConvertFrom-Json) }
    try { return (Get-Content -LiteralPath $FilePath -Raw -Encoding UTF8 | ConvertFrom-Json) }
    catch { return ($FallbackJson | ConvertFrom-Json) }
}

function Write-JsonFile([string]$FilePath, $Object) {
    $dir = Split-Path -Parent $FilePath
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllText($FilePath, ($Object | ConvertTo-Json -Depth 10), (New-Object System.Text.UTF8Encoding($false)))
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

function Get-State {
    $s = Read-JsonFile $StateFile
    if (-not $s.forcePlugins) { $s | Add-Member -NotePropertyName forcePlugins -NotePropertyValue @() -Force }
    return $s
}

function Save-State($State) {
    Write-JsonFile $StateFile $State
}

function Write-Audit {
    param(
        [string]$Type,
        [string]$Detail,
        [string]$Result = 'ok',
        [string]$Evidence = ''
    )
    try {
        & $AuditScript log -Type $Type -PluginId 'dsh-translate' -Detail $Detail -Result $Result `
            -Evidence $Evidence -Session $env:CODEX_SESSION_ID -DshHome $DshHome | Out-Null
    } catch {
        Write-Host "[translate] WARN: audit failed: $($_.Exception.Message)"
    }
}

function Rebuild-Override {
    $merged = [ordered]@{}
    $packs = @(Get-ChildItem -LiteralPath $DictsDir -Filter '*.json' -ErrorAction SilentlyContinue | Sort-Object Name)
    foreach ($pack in $packs) {
        try {
            $data = Get-Content -LiteralPath $pack.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($ns in $data.PSObject.Properties) {
                if (-not $merged.Contains($ns.Name)) { $merged[$ns.Name] = [ordered]@{} }
                foreach ($key in $ns.Value.PSObject.Properties) {
                    $merged[$ns.Name][$key.Name] = $key.Value
                }
            }
        } catch {
            Write-Host "[translate] WARN: skipped bad dict pack $($pack.Name): $($_.Exception.Message)"
        }
    }
    Write-JsonFile $OverrideFile $merged
    return $packs.Count
}

function Invoke-Status {
    Ensure-Dirs
    Write-Line "DSH_HOME   : $DshHome"
    Write-Line "state file : $StateFile"
    Write-Line ''
    Write-Line '--- Locale ---'
    $settingsPath = Join-Path $DshHome 'settings.yaml'
    $pref = ''
    if (Test-Path -LiteralPath $settingsPath) {
        $line = Get-Content -LiteralPath $settingsPath -Encoding UTF8 | Where-Object { $_ -match '^\s*locale\.preference:\s*' } | Select-Object -First 1
        if ($line -match '^\s*locale\.preference:\s*(\S+)') { $pref = $matches[1] }
    }
    Write-Line "settings.yaml locale.preference : $(if ($pref) { $pref } else { '(unset)' })"
    Write-Line "env DSH_LANG                     : $(if ($env:DSH_LANG) { $env:DSH_LANG } else { '(unset)' })"
    Write-Line ''
    Write-Line '--- Force translation (strong mode) ---'
    $state = Get-State
    if (@($state.forcePlugins).Count -eq 0) {
        Write-Line '  (none)'
    } else {
        $state.forcePlugins | ForEach-Object { Write-Line "  $_" }
    }
    Write-Line ''
    Write-Line '--- Dictionary packs ---'
    $packs = @(Get-ChildItem -LiteralPath $DictsDir -Filter '*.json' -ErrorAction SilentlyContinue)
    if ($packs.Count -eq 0) {
        Write-Line '  (none)'
    } else {
        $packs | ForEach-Object { Write-Line ("  {0}  ({1} B)" -f $_.BaseName, $_.Length) }
    }
    Write-Line ''
    Write-Line '--- Translation cache ---'
    $cache = @(Get-ChildItem -LiteralPath $CacheDir -Filter '*.json' -ErrorAction SilentlyContinue)
    if ($cache.Count -eq 0) {
        Write-Line '  (empty)'
    } else {
        $size = ($cache | Measure-Object Length -Sum).Sum / 1KB
        Write-Line ("  {0} file(s), {1} KB" -f $cache.Count, [Math]::Round($size, 1))
    }
    Write-Line ''
    Write-Line '--- Model translation config ---'
    if (Test-Path -LiteralPath $ConfigFile) {
        $c = Read-JsonFile $ConfigFile
        Write-Line "  baseUrl  : $($c.baseUrl)"
        Write-Line "  model    : $($c.model)"
        Write-Line "  apiKeyEnv: $($c.apiKeyEnv)"
    } else {
        Write-Line '  (not configured; translate requires config.json)'
    }
}

function Invoke-DictAdd {
    if (-not $Name -or -not $Path) { throw 'dict-add requires -Name and -Path' }
    if (-not (Test-Path -LiteralPath $Path)) { throw "dict file not found: $Path" }
    Ensure-Dirs
    $data = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    $nsCount = @($data.PSObject.Properties).Count
    if ($nsCount -eq 0) { throw 'dict file must map namespaces to {key: value} objects' }
    $dest = Join-Path $DictsDir ($Name + '.json')
    Copy-Item -LiteralPath $Path -Destination $dest -Force
    $packs = Rebuild-Override
    Write-Host "[translate] dict pack '$Name' installed ($nsCount namespace(s)); override rebuilt from $packs pack(s): $OverrideFile"
    Write-Audit -Type translate.dict-add -Detail "dict pack $Name ($nsCount ns)" -Evidence $dest
}

function Invoke-DictList {
    $packs = @(Get-ChildItem -LiteralPath $DictsDir -Filter '*.json' -ErrorAction SilentlyContinue)
    if ($packs.Count -eq 0) { Write-Host '[translate] no dict packs'; return }
    $packs | ForEach-Object { Write-Host ("  {0}  ({1} B)" -f $_.BaseName, $_.Length) }
    Write-Host "[translate] override: $OverrideFile"
}

function Invoke-DictRemove {
    if (-not $Name) { throw 'dict-remove requires -Name' }
    $dest = Join-Path $DictsDir ($Name + '.json')
    if (-not (Test-Path -LiteralPath $dest)) { throw "dict pack not found: $Name" }
    Remove-Item -LiteralPath $dest -Force
    $packs = Rebuild-Override
    Write-Host "[translate] dict pack '$Name' removed; override rebuilt from $packs pack(s)"
    Write-Audit -Type translate.dict-remove -Detail "dict pack $Name removed"
}

function Set-Force {
    param([bool]$On)
    if (-not $PluginId) { throw 'force-on/force-off requires -PluginId' }
    $state = Get-State
    $list = @($state.forcePlugins | Where-Object { $_ -ne $PluginId })
    if ($On) { $list += $PluginId }
    $state.forcePlugins = $list
    Save-State $state
    Write-Host "[translate] force translation for '$PluginId' = $On"
    Write-Audit -Type translate.force -Detail "plugin $PluginId force=$On"
}

function Invoke-CacheClear {
    $cache = @(Get-ChildItem -LiteralPath $CacheDir -Filter '*.json' -ErrorAction SilentlyContinue)
    foreach ($f in $cache) { Remove-Item -LiteralPath $f.FullName -Force }
    Write-Host "[translate] cache cleared: $($cache.Count) file(s)"
    Write-Audit -Type translate.cache-clear -Detail "cleared $($cache.Count) cache file(s)"
}

function Invoke-ExportOverride {
    if (-not $Out) { throw 'export-override requires -Out' }
    Ensure-Dirs
    if (-not (Test-Path -LiteralPath $OverrideFile)) { Rebuild-Override | Out-Null }
    $dir = Split-Path -Parent $Out
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Copy-Item -LiteralPath $OverrideFile -Destination $Out -Force
    Write-Host "[translate] override exported: $Out"
}

function Invoke-Translate {
    if (-not $Source) { throw 'translate requires -Source (a JSON dict file)' }
    if (-not (Test-Path -LiteralPath $Source)) { throw "source not found: $Source" }
    Ensure-Dirs
    $srcData = Get-Content -LiteralPath $Source -Raw -Encoding UTF8 | ConvertFrom-Json
    $flat = [ordered]@{}
    foreach ($ns in $srcData.PSObject.Properties) {
        foreach ($key in $ns.Value.PSObject.Properties) {
            $flat["$($ns.Name).$($key.Name)"] = $key.Value
        }
    }
    if ($flat.Count -eq 0) { throw 'source has no translatable keys' }

    $override = Read-JsonFile $OverrideFile
    $covered = @()
    foreach ($fullKey in $flat.Keys) {
        $parts = $fullKey.Split('.', 2)
        if ($override.$($parts[0]).$($parts[1])) { $covered += $fullKey }
    }
    $srcHash = Get-Sha256Text ((Get-Content -LiteralPath $Source -Raw -Encoding UTF8))
    $cacheFile = Join-Path $CacheDir ($srcHash + '.json')
    $cache = Read-JsonFile $cacheFile
    $cachedKeys = @($cache.PSObject.Properties | ForEach-Object { $_.Name })

    $need = @($flat.Keys | Where-Object { $_ -notin $covered -and $_ -notin $cachedKeys })
    Write-Host "[translate] source keys=$($flat.Count) covered-by-dicts=$($covered.Count) cached=$($cachedKeys.Count) need-model=$($need.Count)"

    if ($need.Count -eq 0) {
        Write-Host '[translate] nothing to translate (all keys covered by dicts/cache)'
        return
    }
    if (-not (Test-Path -LiteralPath $ConfigFile)) {
        Write-Host '[translate] model translation not configured; create config.json:'
        Write-Host "  $ConfigFile"
        Write-Host '  {"baseUrl":"https://api.deepseek.com","model":"deepseek-chat","apiKeyEnv":"DEEPSEEK_API_KEY"}'
        if ($DryRun) {
            Write-Host "[translate] DRY RUN: would translate $($need.Count) key(s), e.g.:"
            $need | Select-Object -First 5 | ForEach-Object { Write-Host "    $_ = $($flat[$_])" }
        }
        return
    }

    $config = Read-JsonFile $ConfigFile
    $apiKey = [Environment]::GetEnvironmentVariable($config.apiKeyEnv)
    if (-not $apiKey) {
        throw "api key env '$($config.apiKeyEnv)' is not set"
    }
    if ($DryRun) {
        Write-Host "[translate] DRY RUN: configured model=$($config.model) base=$($config.baseUrl); would translate $($need.Count) key(s)"
        $need | Select-Object -First 5 | ForEach-Object { Write-Host "    $_ = $($flat[$_])" }
        return
    }

    $batchJson = ($need | ForEach-Object { '"' + $_ + '": ' + ($flat[$_] | ConvertTo-Json -Compress) }) -join ','
    $prompt = "Translate the JSON values into Simplified Chinese. Keep keys unchanged. Return ONLY a JSON object." +
        "`n{" + $batchJson + "}"
    $body = @{
        model       = $config.model
        temperature = 0.2
        messages    = @(
            @{ role = 'system'; content = 'You are a professional zh-CN translator for software UI strings.' },
            @{ role = 'user'; content = $prompt }
        )
    } | ConvertTo-Json -Depth 8
    $headers = @{ Authorization = "Bearer $apiKey" }
    $url = $config.baseUrl.TrimEnd('/') + '/chat/completions'
    Write-Host "[translate] calling $url (model=$($config.model), keys=$($need.Count)) ..."
    $resp = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -ContentType 'application/json' -Body $body -TimeoutSec 120
    $content = $resp.choices[0].message.content
    $jsonStart = $content.IndexOf('{')
    $jsonEnd = $content.LastIndexOf('}')
    if ($jsonStart -lt 0 -or $jsonEnd -le $jsonStart) { throw 'model response contains no JSON object' }
    $parsed = $content.Substring($jsonStart, $jsonEnd - $jsonStart + 1) | ConvertFrom-Json
    $merged = @{}
    foreach ($key in $need) {
        if ($parsed.$key) { $merged[$key] = $parsed.$key }
    }
    $cacheObj = @{}
    foreach ($p in $cache.PSObject.Properties) { $cacheObj[$p.Name] = $p.Value }
    foreach ($k in $merged.Keys) { $cacheObj[$k] = $merged[$k] }
    Write-JsonFile $cacheFile $cacheObj
    Write-Host "[translate] cached $($merged.Count)/$($need.Count) translations: $cacheFile"
    Write-Audit -Type translate.run -Detail "model translation $($merged.Count) keys" -Evidence $cacheFile
}

function Write-Line([string]$Message) {
    Write-Host ("[translate] " + $Message)
}

switch ($Command) {
    'status'         { Invoke-Status }
    'dict-add'       { Invoke-DictAdd }
    'dict-list'      { Invoke-DictList }
    'dict-remove'    { Invoke-DictRemove }
    'force-on'       { Set-Force -On $true }
    'force-off'      { Set-Force -On $false }
    'cache-clear'    { Invoke-CacheClear }
    'translate'      { Invoke-Translate }
    'export-override' { Invoke-ExportOverride }
}
