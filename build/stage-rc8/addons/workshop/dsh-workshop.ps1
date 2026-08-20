param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet('new', 'clarify', 'test', 'install', 'list')]
    [string]$Command,

    [string]$Name = '',
    [string]$Description = '',
    [string[]]$Features = @(),
    [string[]]$Events = @(),
    [string]$CommandName = '',
    [string]$Spec = '',
    [string]$Path = '',
    [string]$Profile = 'web',
    [switch]$Experimental,
    [switch]$DryRun,
    [string[]]$Approve = @(),
    [string]$DshHome = '',
    [string]$ProgramRoot = '',
    [string]$Out = '',
    [string]$NodeDir = 'C:\Program Files\nodejs'
)

$ErrorActionPreference = 'Stop'

$Approve = @($Approve | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
$Features = @($Features | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })

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
$WorkshopRoot = Join-Path $DshHome 'workshop'
$PluginsDir = Join-Path $WorkshopRoot 'plugins'
$BackupsDir = Join-Path $WorkshopRoot 'backups'

function Write-Utf8NoBom([string]$FilePath, [string]$Text) {
    $dir = Split-Path -Parent $FilePath
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllText($FilePath, $Text, (New-Object System.Text.UTF8Encoding($false)))
}

function Write-Audit {
    param(
        [string]$Type,
        [string]$Detail,
        [string]$PluginId = 'dsh-workshop',
        [string]$Result = 'ok',
        [string]$Evidence = ''
    )
    try {
        & $AuditScript log -Type $Type -PluginId $PluginId -Detail $Detail -Result $Result `
            -Evidence $Evidence -Session $env:CODEX_SESSION_ID -DshHome $DshHome | Out-Null
    } catch {
        Write-Host "[workshop] WARN: audit failed: $($_.Exception.Message)"
    }
}

function Test-PackageName([string]$PackageName) {
    return $PackageName -match '^(@[a-z0-9-~][a-z0-9-._~]*\/)?[a-z0-9-~][a-z0-9-._~]*$'
}

function Get-SanitizedCommandName([string]$RawName) {
    $c = ($RawName -replace '^/', '' -replace '[^a-z0-9-]', '-').ToLowerInvariant()
    if (-not $c) { $c = 'hello' }
    return $c
}

function Get-EventsCode([string[]]$EventList) {
    if ($EventList.Count -eq 0) { return '' }
    $lines = @()
    foreach ($ev in $EventList) {
        $lines += "  ctx.on('$ev', () => {})"
    }
    return $lines -join "`n"
}

function New-GeneratedPlugin {
    if (-not $Name) { throw 'new requires -Name (npm package name)' }
    if (-not (Test-PackageName $Name)) { throw "invalid npm package name: $Name (lowercase, no spaces)" }
    if (-not $Description) { throw 'new requires -Description' }
    if (-not $CommandName) { $CommandName = (Split-Path -Leaf $Name) -replace '[^a-z0-9-]', '-' }
    $cmd = Get-SanitizedCommandName $CommandName
    $events = $Events
    if ($events.Count -eq 0 -and $Features -contains 'event') { $events = @('session/created', 'session/event') }
    if ($Features.Count -eq 0) { $Features = @('command', 'event') }

    $targetDir = if ($Out) { Join-Path $Out $Name } else { Join-Path $PluginsDir $Name }

    $sections = @()
    if ($Features -contains 'command') {
        $sections += @(
            "  // Human command (no model turn): ctx.commands.register",
            "  ctx.commands.register({",
            "    name: '$cmd',",
            "    description: '$Description',",
            "    input: { hint: 'optional argument' },",
            "    handler: () => ({ kind: 'success', text: 'hello from $Name' })",
            "  })"
        )
    }
    if ($Features -contains 'event') {
        $evCode = Get-EventsCode $events
        if ($evCode) {
            $sections += @('  // Event listeners (session protocol events)')
            $sections += $evCode
        }
    }
    if ($Features -contains 'tool-stub') {
        $sections += @(
            "  // Model-facing tool (stub): register via ctx.tools.register({...})",
            "  // See docs/subsystems/tools.md before implementing; schema joins prompt assembly."
        )
    }
    if ($Features -contains 'service-stub') {
        $sections += @(
            "  // Service (stub): export const inject = ['<existing-service>'] and use ctx.<service>",
            "  // See docs/cordis-tutorial/03-services.md before implementing."
        )
    }
    if ($sections.Count -eq 0) {
        $sections += @('  // No features selected; empty plugin skeleton.')
    }
    $body = ($sections -join "`n")

    $stamp = (Get-Date).ToUniversalTime().ToString('o')
    $indexJs = @'
// Generated by DSH-Portable plugin workshop.
// Review with addons/plugin-review before installing. Do not add untrusted code.
export const name = '__NAME__'

export function apply(ctx) {
__BODY__
}
'@
    $indexJs = $indexJs -replace '__NAME__', $Name -replace '__BODY__', $body

    $pkgJson = @{
        name        = $Name
        version     = '0.0.1'
        description = $Description
        type        = 'module'
        main        = 'index.js'
        license     = 'MIT'
        dshWorkshop = @{
            generatedAt  = $stamp
            features     = @($Features)
            experimental = [bool]$Experimental
        }
    } | ConvertTo-Json -Depth 5

    $readme = @"
# $Name

$Description

Generated by the DSH-Portable plugin workshop on $stamp.
Features: $($Features -join ', ')
Experimental: $Experimental

Flow: generate -> review (plugin-review) -> install into profile -> self-test.
"@

    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    Write-Utf8NoBom (Join-Path $targetDir 'index.js') $indexJs
    Write-Utf8NoBom (Join-Path $targetDir 'package.json') $pkgJson
    Write-Utf8NoBom (Join-Path $targetDir 'README.md') $readme

    Write-Host "[workshop] generated plugin: $targetDir"
    Write-Host "  files: index.js, package.json, README.md"
    Write-Host "  features: $($Features -join ', '); command=/$cmd; experimental=$Experimental"
    Write-Host '  next: run "test" then "install" (both go through M2 review)'
    Write-Audit -Type workshop.generate -Detail "generated $Name (features: $($Features -join ','), experimental=$Experimental)" -Evidence $targetDir
}

function Invoke-Clarify {
    $specObj = $null
    if ($Spec) {
        if (-not (Test-Path -LiteralPath $Spec)) { throw "spec not found: $Spec" }
        $specObj = Get-Content -LiteralPath $Spec -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $Name) { $Name = $specObj.name }
        if (-not $Description) { $Description = $specObj.description }
        if ($Features.Count -eq 0 -and $specObj.features) { $Features = @($specObj.features) }
        if (-not $CommandName) { $CommandName = $specObj.command }
    }

    Write-Host '[workshop] clarifying plugin spec (required: name, description; recommended: features, command)'
    Write-Host ''
    $missing = @()
    if (-not $Name) { $missing += 'name (npm package name, e.g. my-hello-plugin)' }
    if (-not $Description) { $missing += 'description (one sentence: what the plugin does)' }
    if ($Name -and -not (Test-PackageName $Name)) { $missing += "name invalid: $Name (lowercase, no spaces)" }
    if ($Features.Count -eq 0) { $missing += 'features (command / event / tool-stub / service-stub, comma separated)' }
    if ($missing.Count -gt 0) {
        Write-Host 'Open questions:'
        $i = 1
        foreach ($m in $missing) {
            Write-Host ("  $i. $m")
            $i++
        }
        Write-Host ''
        Write-Host 'Example spec JSON (also accepted via -Spec):'
        Write-Host '  {"name":"my-hello-plugin","description":"say hello","features":["command","event"],"command":"hello"}'
        Write-Audit -Type workshop.clarify -Detail "open questions: $($missing.Count)" -Result 'warn'
    } else {
        Write-Host 'Spec is complete:'
        Write-Host "  name=$Name description=$Description features=$($Features -join ',') command=$CommandName"
        Write-Host 'Run: new -Name ... -Description ... -Features ...'
        Write-Audit -Type workshop.clarify -Detail "spec complete for $Name"
    }
}

function Invoke-Test {
    if (-not $Path) { throw 'test requires -Path' }
    if (-not (Test-Path -LiteralPath $Path)) { throw "path not found: $Path" }
    $pluginRoot = (Resolve-Path -LiteralPath $Path).Path
    Write-Host "[workshop] self-test: $pluginRoot"
    $failed = $false

    $jsFiles = @(Get-ChildItem -LiteralPath $pluginRoot -Recurse -File -Filter '*.js' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\node_modules\\' })
    foreach ($file in $jsFiles) {
        $previousEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            & $NodeBin --check $file.FullName *> $null
            $code = $LASTEXITCODE
            if ($code -ne 0) {
                Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | & $NodeBin --input-type=module --check *> $null
                $code = $LASTEXITCODE
            }
        } finally {
            $ErrorActionPreference = $previousEap
        }
        if ($code -ne 0) {
            Write-Host "[workshop] SYNTAX FAIL: $($file.FullName)"
            $failed = $true
        } else {
            Write-Host "[workshop] syntax ok: $($file.Name)"
        }
    }

    $entry = Join-Path $pluginRoot 'index.js'
    if (Test-Path -LiteralPath $entry) {
        $checkScript = "import { pathToFileURL } from 'node:url'; const m = await import(pathToFileURL(process.argv[1]).href); if (typeof m.apply !== 'function') { console.error('missing apply export'); process.exit(1) }; console.log('export ok, name=' + (m.name || ''))"
        $previousEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            & $NodeBin --input-type=module -e $checkScript $entry
            if ($LASTEXITCODE -ne 0) {
                Write-Host '[workshop] EXPORT FAIL: apply() export missing or module cannot load'
                $failed = $true
            }
        } finally {
            $ErrorActionPreference = $previousEap
        }
    } else {
        Write-Host '[workshop] WARN: no index.js entry; export check skipped'
    }

    Write-Host '[workshop] running M2 review ...'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ReviewScript -Path $pluginRoot -DshHome $DshHome
    $reviewExit = $LASTEXITCODE
    if ($reviewExit -eq 3) {
        Write-Host '[workshop] SELF-TEST FAIL: M2 review REJECTED'
        $failed = $true
    }

    if ($failed) {
        Write-Audit -Type workshop.test -Detail "self-test FAILED for $pluginRoot" -Result 'fail' -Evidence $pluginRoot
        throw 'workshop self-test failed'
    }
    Write-Host '[workshop] self-test PASSED (syntax, exports, M2 review)'
    Write-Audit -Type workshop.test -Detail "self-test passed for $pluginRoot" -Evidence $pluginRoot
}

function Invoke-Install {
    if (-not $Path) { throw 'install requires -Path' }
    if (-not (Test-Path -LiteralPath $Path)) { throw "path not found: $Path" }
    if (-not (Test-Path -LiteralPath $NodeBin)) {
        throw "built-in node not found: $NodeBin (wrong -ProgramRoot?)"
    }
    $pluginRoot = (Resolve-Path -LiteralPath $Path).Path
    $pkg = Join-Path $pluginRoot 'package.json'
    if (-not (Test-Path -LiteralPath $pkg)) { throw 'install requires a package.json in -Path' }
    $pkgObj = Get-Content -LiteralPath $pkg -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $pkgObj.name) { throw 'package.json has no name' }
    $pluginName = $pkgObj.name

    Write-Host "[workshop] M2 review: $pluginRoot"
    $tmp = Join-Path $env:TEMP ('dsh-workshop-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    try {
        $report = Join-Path $tmp 'review.txt'
        $approveArg = if ($Approve.Count -gt 0) { @('-Approve', ($Approve -join ',')) } else { @() }
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ReviewScript -Path $pluginRoot `
            -DshHome $DshHome -ReportOut $report @approveArg
        $reviewExit = $LASTEXITCODE
        if ($reviewExit -eq 3) {
            Write-Audit -Type workshop.install -PluginId $pluginName -Detail 'REJECTED by M2 review' -Result 'fail' -Evidence $report
            throw "REJECTED by M2 review (see $report)"
        }
        if ($reviewExit -eq 2) {
            Write-Audit -Type workshop.install -PluginId $pluginName -Detail 'needs confirmation' -Result 'warn' -Evidence $report
            throw "M2 review needs confirmation (see $report); re-run install with -Approve <rule-ids>"
        }

        if ($DryRun) {
            $spec = "file:$pluginRoot"
            Write-Host "[workshop] DRY RUN: dsh plugin --profile $Profile add `"$spec`""
            Write-Audit -Type workshop.install -PluginId $pluginName -Detail "dry-run install (M2 passed)" -Evidence $report
            return
        }

        $profileDir = Join-Path $DshHome "profiles\$Profile"
        $profilePkg = Join-Path $profileDir 'package.json'
        New-Item -ItemType Directory -Path $BackupsDir -Force | Out-Null
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $backup = Join-Path $BackupsDir ("profile-$Profile-$stamp.json")
        $hadProfile = Test-Path -LiteralPath $profilePkg
        if ($hadProfile) {
            Copy-Item -LiteralPath $profilePkg -Destination $backup -Force
            Write-Host "[workshop] profile backed up: $backup"
        } else {
            Write-Host '[workshop] no existing profile package.json; nothing to back up'
        }

        $installLog = Join-Path $tmp 'install.log'
        $env:DSH_HOME = $DshHome
        $spec = "file:$pluginRoot"
        $cliArgs = @($CliBin, 'plugin', '--profile', $Profile, 'add', $spec)
        $previousEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            & $NodeBin @cliArgs *>> $installLog
            $installCode = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $previousEap
        }
        if ($installCode -ne 0) {
            Write-Host "[workshop] install failed (exit $installCode); rolling back profile ..."
            if ($hadProfile -and (Test-Path -LiteralPath $backup)) {
                Copy-Item -LiteralPath $backup -Destination $profilePkg -Force
                Write-Host '[workshop] profile package.json restored from backup'
            }
            Write-Audit -Type workshop.install -PluginId $pluginName -Detail "install failed, profile rolled back" -Result 'fail' -Evidence $installLog
            throw "install failed (exit $installCode); profile restored; see $installLog"
        }
        Write-Host "[workshop] installed $pluginName into profile '$Profile'"
        Write-Host '[workshop] NOTE: hot activation requires the running harness to reload the profile (or restart DSH-Portable)'
        Write-Audit -Type workshop.install -PluginId $pluginName -Detail "installed into profile $Profile" -Evidence $report
    } finally {
        if (Test-Path -LiteralPath $tmp) {
            & $NodeBin -e "require('fs').rmSync(process.argv[1],{recursive:true,force:true})" $tmp 2>$null
        }
    }
}

function Invoke-List {
    $profileDir = Join-Path $DshHome "profiles\$Profile"
    $pkgPath = Join-Path $profileDir 'package.json'
    if (-not (Test-Path -LiteralPath $pkgPath)) {
        Write-Host "[workshop] no plugins in profile '$Profile'"
        return
    }
    $pkg = Get-Content -LiteralPath $pkgPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Write-Host "[workshop] plugins in profile '$Profile':"
    if ($pkg.dependencies) {
        $pkg.dependencies.PSObject.Properties | Sort-Object Name | ForEach-Object {
            Write-Host ("  {0} {1}" -f $_.Name, $_.Value)
        }
    }
}

switch ($Command) {
    'new'     { New-GeneratedPlugin }
    'clarify' { Invoke-Clarify }
    'test'    { Invoke-Test }
    'install' { Invoke-Install }
    'list'    { Invoke-List }
}
