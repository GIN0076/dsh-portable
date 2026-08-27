param(
    [ValidateSet('check', 'apply')]
    [string]$Mode = 'check',

    [switch]$Force,
    [switch]$KillRunning,
    [string]$DshHome = '',
    [string]$ProgramRoot = '',
    [string]$Mirror = 'https://ghfast.top',
    [string]$NodeDir = 'C:\Program Files\nodejs'
)

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $ProgramRoot) {
    $ProgramRoot = (Resolve-Path (Join-Path $ScriptDir '..\..')).Path
}
$ManifestPath = Join-Path $ProgramRoot 'version-manifest.json'
$LockPath = Join-Path $ProgramRoot 'upstream-lock.json'
$SrcDir = Join-Path $ProgramRoot 'src'
$NodeBin = Join-Path $ProgramRoot 'runtime\node\node.exe'
$CliBin = Join-Path $SrcDir 'apps\cli\lib\bin.js'
$AuditScript = Join-Path $ScriptDir '..\audit\dsh-audit.ps1'
$UpstreamRepo = 'deepseek-ai/deepseek-harness'
$Port = 3080

if (-not $DshHome) {
    if ($env:DSH_HOME) { $DshHome = $env:DSH_HOME }
    else { $DshHome = Join-Path $env:USERPROFILE '.dsh' }
}

function Write-Step([string]$Message) {
    Write-Host ("[update] " + $Message)
}

function Get-Sha256File([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
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

function Remove-DeepTree([string]$Path) {
    # Windows LongPathsEnabled=0 breaks Remove-Item -Recurse on deep
    # node_modules trees (>260 chars). Built-in Node handles long paths
    # natively and is the only reliable deleter here; fail loudly if it does not.
    if (-not (Test-Path -LiteralPath $Path)) { return }
    & $NodeBin -e "require('fs').rmSync(process.argv[1], { recursive: true, force: true })" $Path
    if ($LASTEXITCODE -ne 0) {
        throw "node rm failed for $Path (exit $LASTEXITCODE); remove manually with node fs.rmSync"
    }
}

function Resolve-PinnedPnpm([string]$ProjectDir) {
    # Read the repo's packageManager field (e.g. "pnpm@11.7.0") and return the
    # matching pnpm.cjs from the corepack cache, so nested `pnpm` calls inside
    # npm scripts use the same version and pass the devEngines check.
    try {
        $pkg = Get-Content -LiteralPath (Join-Path $ProjectDir 'package.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($pkg.packageManager -match '^pnpm@(\d+\.\d+\.\d+)') {
            $v = $matches[1]
            $candidates = @(
                (Join-Path $env:LOCALAPPDATA "Node\corepack\v1\pnpm\$v\bin\pnpm.cjs"),
                (Join-Path $env:USERPROFILE ".cache\node\corepack\v1\pnpm\$v\bin\pnpm.cjs")
            )
            foreach ($c in $candidates) {
                if (Test-Path -LiteralPath $c) { return $c }
            }
        }
    } catch { }
    return $null
}

function New-PnpmShim([string]$PnpmCjs) {
    $dir = Join-Path $env:TEMP ('dsh-pnpm-shim-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $cmdText = "@echo off`r`nnode `"$PnpmCjs`" %*`r`n"
    $psText = "& node `"$PnpmCjs`" @args`r`n"
    [System.IO.File]::WriteAllText((Join-Path $dir 'pnpm.cmd'), $cmdText, (New-Object System.Text.UTF8Encoding($false)))
    [System.IO.File]::WriteAllText((Join-Path $dir 'pnpm.ps1'), $psText, (New-Object System.Text.UTF8Encoding($false)))
    return $dir
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
        [string]$Evidence = '',
        [string]$PluginId = 'dsh-portable'
    )
    try {
        & $AuditScript log -Type $Type -PluginId $PluginId -Detail $Detail -Before $Before -After $After `
            -Result $Result -Evidence $Evidence -Session $env:CODEX_SESSION_ID -DshHome $DshHome | Out-Null
    } catch {
        Write-Host "[update] WARN: audit log failed: $($_.Exception.Message)"
    }
}

function Get-CurrentVersion {
    if (Test-Path -LiteralPath $ManifestPath) {
        try {
            $m = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
            return [pscustomobject]@{ Version = $m.version; Tag = $m.upstream.tag; Commit = $m.upstream.commit }
        } catch {
            Write-Host "[update] WARN: could not read $ManifestPath, falling back to package.json"
        }
    }
    $pkg = Join-Path $SrcDir 'package.json'
    if (Test-Path -LiteralPath $pkg) {
        $v = (Get-Content -LiteralPath $pkg -Raw -Encoding UTF8 | ConvertFrom-Json).version
        return [pscustomobject]@{ Version = $v; Tag = ''; Commit = '' }
    }
    return $null
}

function Get-UpstreamUrls([string]$RepoPath, [string]$Suffix) {
    # 构建候选 URL：配置镜像 → 常用镜像 → 直连 GitHub
    $candidates = @()
    if ($Mirror) { $candidates += ($Mirror.TrimEnd('/')) + '/https://github.com/' + $RepoPath + $Suffix }
    $candidates += 'https://ghfast.top/https://github.com/' + $RepoPath + $Suffix
    $candidates += 'https://ghproxy.com/https://github.com/' + $RepoPath + $Suffix
    $candidates += 'https://github.com/' + $RepoPath + $Suffix
    return @($candidates | Select-Object -Unique)
}

function Invoke-GitLsRemoteTags([string]$Url) {
    # Windows schannel TLS 凭据异常时自动降级 git 的 OpenSSL 后端
    $out = & git ls-remote --tags $Url 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $out) {
        Write-Step "git (schannel) failed for $Url; retrying with openssl backend ..."
        $out = & git -c http.sslBackend=openssl ls-remote --tags $Url 2>$null
        if ($LASTEXITCODE -ne 0) { return $null }
    }
    return $out
}

function Get-UpstreamTagsViaApi {
    # 无 git 时的降级：内置 Node（OpenSSL）抓 GitHub API；未认证 60 req/h，低频检查够用。
    # 输出转换为 git ls-remote 同款格式 <sha>\trefs/tags/<tag>，复用下游解析。
    # 脚本刻意全无引号（PowerShell 向原生 exe 传参时引号可能被吃掉）。
    $apiUrl = "https://api.github.com/repos/$UpstreamRepo/tags?per_page=100"
    Write-Step "fetching tags via GitHub API (built-in Node): $apiUrl"
    $script = 'fetch(process.argv[1],{headers:{[String.fromCharCode(85,115,101,114,45,65,103,101,110,116)]:String.fromCharCode(100,115,104,45,112,111,114,116,97,98,108,101)}}).then(r=>{if(!r.ok)throw new Error(String.fromCharCode(72,84,84,80)+r.status);return r.json()}).then(j=>process.stdout.write(j.map(x=>x.commit.sha+String.fromCharCode(9)+String.fromCharCode(114,101,102,115,47,116,97,103,115,47)+x.name).join(String.fromCharCode(10)))).catch(e=>{console.error(e.message);process.exit(1)})'
    $out = & $NodeBin -e $script $apiUrl 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $out) { return $null }
    return @($out)
}

function Get-UpstreamTags {
    $lines = $null
    if (Get-Command git -ErrorAction SilentlyContinue) {
        foreach ($url in (Get-UpstreamUrls $UpstreamRepo '.git')) {
            Write-Step "git ls-remote: $url"
            $lines = Invoke-GitLsRemoteTags $url
            if ($lines) { break }
        }
    } else {
        Write-Step 'git not found on PATH; falling back to GitHub API via built-in Node'
    }
    if (-not $lines) {
        $lines = Get-UpstreamTagsViaApi
    }
    if (-not $lines) {
        throw 'failed to enumerate upstream tags (git unavailable and API fallback failed)'
    }
    $commits = @{}
    $tags = @{}
    foreach ($ln in $lines) {
        if ($ln -match '^([0-9a-f]{40})\s+refs/tags/([^\s^{}]+)(\^\{\})?$') {
            $sha = $matches[1]
            $tag = $matches[2]
            $peeled = [bool]$matches[3]
            if ($tag -notlike 'dsh-v*') { continue }
            $version = $tag.Substring(5)
            $tags[$tag] = [pscustomobject]@{ Tag = $tag; Version = $version; Commit = $sha; Peeled = $peeled }
        }
    }
    $result = @()
    foreach ($tag in $tags.Keys) {
        $entry = $tags[$tag]
        $commit = $entry.Commit
        $peeledEntry = $tags.Values | Where-Object { $_.Tag -eq $tag -and $_.Peeled } | Select-Object -First 1
        if ($peeledEntry) { $commit = $peeledEntry.Commit }
        $result += [pscustomobject]@{ Tag = $tag; Version = $entry.Version; Commit = $commit }
    }
    return $result
}

function Invoke-DownloadFile([string]$Url, [string]$OutFile) {
    # 优先 .NET（schannel）；失败自动降级内置 Node（OpenSSL/undici，跟随重定向）。
    # 注意：降级脚本刻意不用引号字符（PowerShell 向原生 exe 传参时引号可能被吃掉）。
    try {
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -TimeoutSec 180
        return $true
    } catch {
        Write-Host "[update] .NET download failed ($($_.Exception.Message)); retrying via built-in Node (OpenSSL)..."
        $script = 'fetch(process.argv[1]).then(r=>{if(!r.ok)throw new Error(String.fromCharCode(72,84,84,80)+r.status);return r.arrayBuffer()}).then(b=>require(String.fromCharCode(102,115)).writeFileSync(process.argv[2],Buffer.from(b))).catch(e=>{console.error(e.message);process.exit(1)})'
        & $NodeBin -e $script $Url $OutFile 2>$null
        return ($LASTEXITCODE -eq 0)
    }
}

function Parse-Version([string]$Version) {
    $m = [regex]::Match($Version, '^(\d+)\.(\d+)\.(\d+)(?:-(.+))?$')
    if (-not $m.Success) { throw "cannot parse version: $Version" }
    return [pscustomobject]@{
        Core = @([int]$m.Groups[1].Value, [int]$m.Groups[2].Value, [int]$m.Groups[3].Value)
        Pre  = $m.Groups[4].Value
    }
}

function Compare-Version([string]$A, [string]$B) {
    $pa = Parse-Version $A
    $pb = Parse-Version $B
    for ($i = 0; $i -lt 3; $i++) {
        if ($pa.Core[$i] -gt $pb.Core[$i]) { return 1 }
        if ($pa.Core[$i] -lt $pb.Core[$i]) { return -1 }
    }
    if ($pa.Pre -eq '' -and $pb.Pre -eq '') { return 0 }
    if ($pa.Pre -eq '') { return 1 }
    if ($pb.Pre -eq '') { return -1 }
    $ma = [regex]::Match($pa.Pre, '^rc\.(\d+)$')
    $mb = [regex]::Match($pb.Pre, '^rc\.(\d+)$')
    if ($ma.Success -and $mb.Success) {
        $na = [int]$ma.Groups[1].Value
        $nb = [int]$mb.Groups[1].Value
        if ($na -gt $nb) { return 1 }
        if ($na -lt $nb) { return -1 }
        return 0
    }
    return [string]::Compare($pa.Pre, $pb.Pre, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-PortBusy {
    return (Test-NetConnection -ComputerName 127.0.0.1 -Port $Port -WarningAction SilentlyContinue).TcpTestSucceeded
}

function Stop-ProgramProcesses {
    $targets = Get-CimInstance Win32_Process -Filter "Name='electron.exe' OR Name='node.exe'" |
        Where-Object { $_.CommandLine -and $_.CommandLine -like "*$ProgramRoot*" }
    foreach ($t in $targets) {
        Write-Step "killing $($t.Name) pid=$($t.ProcessId)"
        & taskkill /pid $t.ProcessId /T /F | Out-Null
    }
    Start-Sleep -Seconds 2
}

function Test-SelfCheck([string]$SrcPath) {
    $selfCheckHome = Join-Path $env:TEMP ('dsh-update-selfcheck-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $selfCheckHome | Out-Null
    $cli = Join-Path $SrcPath 'apps\cli\lib\bin.js'
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        $proc = Start-Process -FilePath $NodeBin -ArgumentList @('"' + $cli + '"', 'web', '--host', '127.0.0.1', '--port', [string]$Port) `
            -PassThru -WindowStyle Hidden -Environment @{ DSH_HOME = $selfCheckHome }
    } else {
        $env:DSH_HOME = $selfCheckHome
        $proc = Start-Process -FilePath $NodeBin -ArgumentList @('"' + $cli + '"', 'web', '--host', '127.0.0.1', '--port', [string]$Port) -PassThru -WindowStyle Hidden
    }
    $ok = $false
    for ($i = 0; $i -lt 80; $i++) {
        if ($ok) { break }
        try {
            $r = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$Port" -TimeoutSec 1
            if ($r.StatusCode -eq 200) { $ok = $true }
        } catch { }
        if (-not (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)) { break }
        Start-Sleep -Milliseconds 500
    }
    if (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue) {
        & taskkill /pid $proc.Id /T /F | Out-Null
    }
    Start-Sleep -Seconds 2
    $still = Get-PortBusy
    return [pscustomobject]@{ Ok = $ok; PortReleased = (-not $still) }
}

function Invoke-PinnedPnpm([string]$ProjectDir, [string[]]$PnpmArgs, [string]$BuildLog) {
    $env:PATH = $NodeDir + ';' + $env:PATH
    # PowerShell 5.1 turns native stderr into ErrorRecords when
    # $ErrorActionPreference='Stop'; tsdown/tsc print a lot to stderr even on
    # success, so the run would falsely throw. Native commands must be run with
    # EAP=Continue and judged by $LASTEXITCODE instead.
    $previousEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $pnpmShim = $null
    try {
        $pinnedPnpm = Resolve-PinnedPnpm $ProjectDir
        if ($pinnedPnpm) {
            $pnpmShim = New-PnpmShim $pinnedPnpm
            $env:PATH = $pnpmShim + ';' + $env:PATH
            $pnpmCommand = Join-Path $pnpmShim 'pnpm.cmd'
            Write-Step "pnpm: pinned shim ($pinnedPnpm)"
        } else {
            $pnpmCommand = 'corepack'
            $env:npm_config_pm_on_fail = 'ignore'
            Write-Step 'pnpm: pinned version not cached; using corepack with pm_on_fail=ignore'
        }
        & $pnpmCommand @PnpmArgs *>> $BuildLog
        return $LASTEXITCODE
    } finally {
        if ($pnpmShim) { Remove-DeepTree $pnpmShim }
        $ErrorActionPreference = $previousEap
    }
}

function Invoke-Build([string]$StageDir, [string]$BuildLog) {
    Push-Location $StageDir
    try {
        Write-Step 'pnpm install --frozen-lockfile ...'
        $code = Invoke-PinnedPnpm $StageDir @('install', '--frozen-lockfile') $BuildLog
        if ($code -ne 0) { throw "pnpm install failed (exit $code); see $BuildLog" }

        Write-Step 'pnpm run typecheck ...'
        $code = Invoke-PinnedPnpm $StageDir @('run', 'typecheck') $BuildLog
        if ($code -ne 0) { throw "typecheck failed (exit $code); see $BuildLog" }

        Write-Step 'pnpm run build ...'
        $code = Invoke-PinnedPnpm $StageDir @('run', 'build') $BuildLog
        if ($code -ne 0) { throw "build failed (exit $code); see $BuildLog" }
    } finally {
        Pop-Location
    }
}

function Update-Manifests([string]$Tag, [string]$Version, [string]$Commit) {
    $stamp = (Get-Date).ToString('o')
    if (Test-Path -LiteralPath $ManifestPath) {
        $m = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } else {
        $m = [pscustomobject]@{
            schemaVersion = 1
            name = 'DSH-Portable'
            version = $Version
            upstream = [pscustomobject]@{ name = 'deepseek-harness'; repository = "https://github.com/$UpstreamRepo.git"; mirror = "$Mirror/https://github.com/$UpstreamRepo.git"; tag = $Tag; version = $Version; commit = $Commit }
            builtAt = $stamp
            toolchain = [pscustomobject]@{ node = 'v24.19.0'; pnpm = '11.7.0' }
            artifacts = [pscustomobject]@{
                cli = [pscustomobject]@{ path = 'src/apps/cli/lib/bin.js'; sha256 = (Get-Sha256File (Join-Path $SrcDir 'apps\cli\lib\bin.js')) }
                webDistIndex = [pscustomobject]@{ path = 'src/apps/web/dist/index.html'; sha256 = (Get-Sha256File (Join-Path $SrcDir 'apps\web\dist\index.html')) }
            }
        }
    }
    $m.version = $Version
    $m.upstream.tag = $Tag
    $m.upstream.version = $Version
    $m.upstream.commit = $Commit
    $m.builtAt = $stamp
    $m.artifacts.cli.sha256 = Get-Sha256File (Join-Path $SrcDir 'apps\cli\lib\bin.js')
    $m.artifacts.webDistIndex.sha256 = Get-Sha256File (Join-Path $SrcDir 'apps\web\dist\index.html')
    Write-Utf8NoBom $ManifestPath ($m | ConvertTo-Json -Depth 10)
    Write-Step "manifest updated: $Version ($Commit)"

    if (Test-Path -LiteralPath $LockPath) {
        $l = Get-Content -LiteralPath $LockPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } else {
        $l = [pscustomobject]@{ schemaVersion = 1; upstream = [pscustomobject]@{ name = 'deepseek-harness'; repository = "https://github.com/$UpstreamRepo.git"; mirror = "$Mirror/https://github.com/$UpstreamRepo.git"; tag = $Tag; version = $Version; commit = $Commit }; fetchedAt = $stamp; lockfile = [pscustomobject]@{ path = 'src/pnpm-lock.yaml'; sha256 = '' } }
    }
    $l.upstream.tag = $Tag
    $l.upstream.version = $Version
    $l.upstream.commit = $Commit
    $l.fetchedAt = $stamp
    $lock = Join-Path $SrcDir 'pnpm-lock.yaml'
    if (Test-Path -LiteralPath $lock) { $l.lockfile.sha256 = Get-Sha256File $lock }
    Write-Utf8NoBom $LockPath ($l | ConvertTo-Json -Depth 10)
    Write-Step "upstream-lock updated"
}

function Invoke-Check {
    $current = Get-CurrentVersion
    $tags = Get-UpstreamTags
    $latest = $null
    foreach ($t in $tags) {
        if (-not $latest -or (Compare-Version $t.Version $latest.Version) -gt 0) { $latest = $t }
    }
    if (-not $latest) { throw 'no upstream tags found' }
    $curVer = if ($current) { $current.Version } else { 'unknown' }
    Write-Step "current=$curVer"
    Write-Step "latest=$($latest.Version) tag=$($latest.Tag) commit=$($latest.Commit)"
    if (-not $current) {
        Write-Step 'current version unknown (no manifest); use -Mode apply -Force to install fresh'
        Write-Audit -Type update.check -Detail "current unknown, latest $($latest.Version)" -After $latest.Version
        return $false
    }
    if ((Compare-Version $latest.Version $current.Version) -gt 0) {
        Write-Step 'UPDATE AVAILABLE'
        Write-Audit -Type update.check -Detail 'update available' -Before $current.Version -After $latest.Version
        return $true
    }
    Write-Step 'up to date'
    Write-Audit -Type update.check -Detail 'up to date' -Before $current.Version -After $current.Version
    return $false
}

function Invoke-Apply {
    $current = Get-CurrentVersion
    $tags = Get-UpstreamTags
    $latest = $null
    foreach ($t in $tags) {
        if (-not $latest -or (Compare-Version $t.Version $latest.Version) -gt 0) { $latest = $t }
    }
    if (-not $latest) { throw 'no upstream tags found' }
    $curVer = if ($current) { $current.Version } else { 'unknown' }
    $newer = $true
    if ($current -and (Compare-Version $latest.Version $current.Version) -le 0) {
        $newer = $false
        if (-not $Force) {
            Write-Step "already at latest ($curVer); nothing to do (use -Force to rebuild same version)"
            Write-Audit -Type update.apply -Detail 'skipped: up to date' -Before $curVer -After $curVer -Result 'warn'
            return
        }
    }

    Write-Step "target: $($latest.Version) tag=$($latest.Tag) commit=$($latest.Commit) (current=$curVer)"
    Write-Audit -Type update.start -Detail "begin update" -Before $curVer -After $latest.Version

    try {
        $longPaths = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name LongPathsEnabled -ErrorAction SilentlyContinue).LongPathsEnabled
        Write-Step "LongPathsEnabled=$longPaths (stage uses a short dir name, so build paths stay within current src path lengths)"
    } catch {
        Write-Step 'WARN: could not read LongPathsEnabled registry value'
    }

    if (Get-PortBusy) {
        if (-not $KillRunning) {
            Write-Audit -Type update.apply -Detail 'aborted: port busy' -Before $curVer -After $latest.Version -Result 'fail'
            throw "port $Port is in use; exit DSH-Portable first, or rerun with -KillRunning"
        }
        Stop-ProgramProcesses
    }

    # 1. Backup user data ($DshHome) before anything else.
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupDir = Join-Path $ProgramRoot ("backups\dsh-data-$stamp")
    if (Test-Path -LiteralPath $DshHome) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $backupDir) -Force | Out-Null
        & robocopy $DshHome $backupDir /E /XJ /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
        if ($LASTEXITCODE -lt 8) {
            Write-Step "data backed up to $backupDir"
            Write-Audit -Type update.backup -Detail 'DSH_HOME backup ok' -After $backupDir -Evidence $backupDir
        } else {
            Write-Host "[update] WARN: robocopy exit=$LASTEXITCODE, backup may be incomplete"
            Write-Audit -Type update.backup -Detail "robocopy exit=$LASTEXITCODE" -Result 'warn'
        }
    } else {
        Write-Step "no $DshHome yet, skipping data backup"
    }

    # 2. Download source zip via mirror (multi-mirror candidates).
    $zipUrls = Get-UpstreamUrls $UpstreamRepo ("/archive/refs/tags/$($latest.Tag).zip")
    $tmpRoot = Join-Path $ProgramRoot ('.update-tmp-' + [guid]::NewGuid().ToString('N'))
    $zipPath = Join-Path $tmpRoot 'source.zip'
    New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null
    # Short stage name on purpose: Windows LongPathsEnabled=0 caps paths at ~260
# chars, and a long name like "update-stage-dsh-v0.1.0-rc.8" pushed deep
    # node_modules paths past the limit. "stg" keeps stage paths equal to src.
    $stageDir = Join-Path $ProgramRoot 'stg'
    Remove-DeepTree $stageDir
    $buildLog = Join-Path $ProgramRoot 'logs\update-build.log'
    $logsDir = Split-Path -Parent $buildLog
    if (-not (Test-Path -LiteralPath $logsDir)) { New-Item -ItemType Directory -Path $logsDir -Force | Out-Null }
    if (Test-Path -LiteralPath $buildLog) { Remove-Item -LiteralPath $buildLog -Force }
    $updateOk = $false
    try {
        $downloaded = $false
        for ($try = 1; $try -le 3; $try++) {
            foreach ($url in $zipUrls) {
                Write-Step "downloading $url"
                if (Invoke-DownloadFile $url $zipPath) { $downloaded = $true; break }
            }
            if ($downloaded) { break }
            Write-Host "[update] download attempt $try failed on all mirrors; retrying in 3s"
            Start-Sleep -Seconds 3
        }
        if (-not $downloaded) { throw 'source zip download failed after 3 attempts' }
        $size = (Get-Item -LiteralPath $zipPath).Length
        if ($size -lt 1MB) { throw "zip too small ($size bytes), likely a proxy error page" }
        Write-Step "zip downloaded ($size bytes)"
        Write-Audit -Type update.download -Detail 'source zip ok' -Evidence $zipPath -After $latest.Version

        # 3. Extract and verify.
        Write-Step 'extracting ...'
        # Windows Expand-Archive cannot handle the upstream zip's symlink /
        # long-path entries and silently yields an empty tree. Prefer Python
        # zipfile (proven on this archive), keeping Expand-Archive as fallback.
        $pyCandidates = @(
            (Join-Path $env:USERPROFILE '.workbuddy\binaries\python\versions\3.13.12\python.exe'),
            (Join-Path $env:USERPROFILE '.workbuddy\binaries\python\versions\3.14.6\python.exe')
        ) | Where-Object { Test-Path -LiteralPath $_ }
        if ($pyCandidates.Count -eq 0 -and (Get-Command python.exe -ErrorAction SilentlyContinue)) {
            $pyCandidates += 'python.exe'
        }
        $python = $pyCandidates | Select-Object -First 1
        if ($python) {
            $pyScript = 'import sys,zipfile; z=zipfile.ZipFile(sys.argv[1]); z.testzip(); z.extractall(sys.argv[2])'
            & $python -c $pyScript $zipPath $tmpRoot
            if ($LASTEXITCODE -ne 0) { throw "zip extraction failed (python exit $LASTEXITCODE)" }
        } else {
            Expand-Archive -LiteralPath $zipPath -DestinationPath $tmpRoot -Force
        }
        $topDirs = @(Get-ChildItem -LiteralPath $tmpRoot -Directory | Where-Object { $_.Name -ne 'source.zip' -and $_.Name -ne 'extract' })
        $extract = Join-Path $tmpRoot 'extract'
        New-Item -ItemType Directory -Path $extract -Force | Out-Null
        if ($topDirs.Count -ne 1) { throw 'unexpected zip layout' }
        Get-ChildItem -LiteralPath $topDirs[0].FullName | Move-Item -Destination $extract -Force
        Remove-Item -LiteralPath $topDirs[0].FullName -Force
        $pkgPath = Join-Path $extract 'package.json'
        if (-not (Test-Path -LiteralPath $pkgPath)) { throw 'package.json missing in extracted source' }
        $pkgVersion = (Get-Content -LiteralPath $pkgPath -Raw -Encoding UTF8 | ConvertFrom-Json).version
        if ($pkgVersion -ne $latest.Version) {
            throw "version mismatch: zip=$pkgVersion expected=$($latest.Version)"
        }
        Write-Step "integrity ok: zip version $pkgVersion matches tag"
        Write-Audit -Type update.verify -Detail 'zip version match' -Before $curVer -After $pkgVersion -Evidence $pkgPath

        # 4. Build in staging directory.
        Move-Item -LiteralPath $extract -Destination $stageDir
        try {
            Invoke-Build $stageDir $buildLog
        } catch {
            if (Test-Path -LiteralPath $buildLog) {
                Write-Host '--- build log tail ---'
                Get-Content -LiteralPath $buildLog -Tail 40
                Write-Host '--- end of build log tail ---'
            }
            throw
        }
        Write-Step 'staging build passed (install/typecheck/build)'
        Write-Audit -Type update.build -Detail 'staging build passed' -Evidence $stageDir -After $latest.Version

        # 5. Atomic swap: keep one previous src for rollback.
        $srcBackup = Join-Path $ProgramRoot 'src.bak'
        $oldBackups = @(Get-ChildItem -LiteralPath $ProgramRoot -Directory -Filter 'src.bak*' -ErrorAction SilentlyContinue)
        foreach ($old in $oldBackups) {
            Write-Step "removing old rollback dir $($old.Name)"
            Remove-DeepTree $old.FullName
        }
        Move-Item -LiteralPath $SrcDir -Destination $srcBackup
        Move-Item -LiteralPath $stageDir -Destination $SrcDir
        if (-not (Test-Path -LiteralPath $CliBin)) {
            Move-Item -LiteralPath $SrcDir -Destination $stageDir
            Move-Item -LiteralPath $srcBackup -Destination $SrcDir
            throw 'swap verification failed (cli bin missing), rolled back'
        }
        Write-Step "swapped: new src at $SrcDir (old kept at $srcBackup)"
        Write-Audit -Type update.swap -Detail 'atomic swap ok' -Evidence $srcBackup -After $latest.Version

        # 6. Re-link node_modules at the final path. pnpm creates junctions with
        # ABSOLUTE targets (they point at ...\stg\...), so moving the built
        # stage breaks every link. Delete and reinstall so junctions point at
        # the final src path; otherwise the swapped build cannot boot.
        Write-Step 're-linking node_modules at final path ...'
        Remove-DeepTree (Join-Path $SrcDir 'node_modules')
        Push-Location $SrcDir
        try {
            $code = Invoke-PinnedPnpm $SrcDir @('install', '--frozen-lockfile') $BuildLog
            if ($code -ne 0) { throw "relink install failed (exit $code); see $BuildLog" }
        } finally {
            Pop-Location
        }
        Write-Step 'node_modules re-linked at final path'
        Write-Audit -Type update.relink -Detail 'node_modules junctions re-created at final path' -Result 'ok'

        # 7. Self-check the new build: HTTP 200 + port released.
        $check = Test-SelfCheck $SrcDir
        if (-not $check.Ok) {
            Write-Step 'self-check FAILED (no HTTP 200), rolling back ...'
            Move-Item -LiteralPath $SrcDir -Destination $stageDir
            Move-Item -LiteralPath $srcBackup -Destination $SrcDir
            Write-Audit -Type update.selfcheck -Detail 'self-check failed, rolled back' -Result 'fail'
            throw 'self-check failed; previous version restored'
        }
        if (-not $check.PortReleased) {
            Write-Step 'WARN: port still busy after self-check kill'
            Write-Audit -Type update.selfcheck -Detail 'port not released after self-check' -Result 'warn'
        } else {
            Write-Step 'self-check ok: HTTP 200 and port released'
            Write-Audit -Type update.selfcheck -Detail 'HTTP 200, port released' -Result 'ok'
        }

        # 8. Manifests.
        Update-Manifests $latest.Tag $latest.Version $latest.Commit
        Write-Audit -Type update.apply -Detail 'update completed' -Before $curVer -After $latest.Version
        Write-Step "DONE: now at $($latest.Version) ($($latest.Commit))"
        $updateOk = $true
    } catch {
        Write-Host "[update] ERROR: $($_.Exception.Message)"
        if (Test-Path -LiteralPath $stageDir) {
            Write-Host "[update] staging source kept at $stageDir for debugging"
        }
        Write-Audit -Type update.apply -Detail ("failed: " + $_.Exception.Message) -Before $curVer -After $latest.Version -Result 'fail'
        throw
    } finally {
        Remove-DeepTree $tmpRoot
        if ($updateOk) { Remove-DeepTree $stageDir }
        # Update-UI 触发的更新：清理 .updating 标记（Electron 壳靠它区分
        # "更新导致的退出"与"意外退出"，见 apps/desktop-shell/main.js）。
        $updatingMark = Join-Path $ProgramRoot '.updating'
        if (Test-Path -LiteralPath $updatingMark) {
            Remove-Item -LiteralPath $updatingMark -Force -ErrorAction SilentlyContinue
        }
    }
}

switch ($Mode) {
    'check' { Invoke-Check | Out-Null }
    'apply' { Invoke-Apply }
}
