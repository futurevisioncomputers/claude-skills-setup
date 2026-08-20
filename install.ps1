# Installs every skill listed in skills.json into ~/.claude/skills on Windows.
# Idempotent: re-run any time to pull updates and repair broken links.
#   powershell -ExecutionPolicy Bypass -File install.ps1

# Native exes (git/pip/winget) write progress to stderr; Continue keeps that from
# aborting the run. Real failures are caught by verifying each link afterwards.
$ErrorActionPreference = 'Continue'

$ManifestPath = Join-Path $PSScriptRoot 'skills.json'
$ProjectsDir  = Join-Path $HOME 'Projects'
$SkillsDir    = Join-Path $HOME '.claude\skills'

function Info($m) { Write-Host "  $m" }
function Ok($m)   { Write-Host "  OK   $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  WARN $m" -ForegroundColor Yellow }
function Fail($m) { Write-Host "  FAIL $m" -ForegroundColor Red }

# Junction, not symlink: symlinks need admin or Developer Mode, junctions never do.
# Verified by reading a file *through* the link -- Test-Path alone reports success
# on a junction whose target does not exist.
function Link-Dir($LinkPath, $TargetPath) {
    if (-not (Test-Path -LiteralPath $TargetPath)) { Fail "target missing: $TargetPath"; return $false }
    if (Test-Path -LiteralPath $LinkPath) {
        $item = Get-Item -LiteralPath $LinkPath -Force
        if ($item.LinkType -eq 'Junction') {
            if ($item.Target -eq $TargetPath) { return $true }
            cmd /c rmdir "$LinkPath" | Out-Null      # link-only removal, never follows into the target
        } else {
            Warn "$LinkPath exists and is a real directory, not a link -- leaving it alone"
            return $false
        }
    }
    cmd /c mklink /J "$LinkPath" "$TargetPath" | Out-Null
    return (Test-Path -LiteralPath $LinkPath)
}

function Verify-Skill($Name) {
    $f = Join-Path $SkillsDir "$Name\SKILL.md"
    if (Test-Path -LiteralPath $f) { Ok "$Name ($([math]::Round((Get-Item $f).Length / 1KB, 1)) KB)"; return $true }
    Fail "$Name -- SKILL.md not readable through the link"; return $false
}

Write-Host "`n=== Claude skills bootstrap ===" -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $ProjectsDir, $SkillsDir | Out-Null

# A shell started before an installer ran still carries the old PATH, which would make
# an already-installed tool look missing and get installed again. Re-read it first.
$env:PATH = (@([Environment]::GetEnvironmentVariable('Path', 'Machine'),
                [Environment]::GetEnvironmentVariable('Path', 'User')) -join ';')

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw "git is required and not on PATH" }
$manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json

$needFfmpeg = $false
$needEnv    = @()
$installed  = 0
$failed     = @()

foreach ($s in $manifest.skills) {
    Write-Host "`n[$($s.name)]" -ForegroundColor Cyan
    $clone = Join-Path $ProjectsDir $s.name

    if (Test-Path -LiteralPath $clone) {
        Info "pulling latest"
        git -C $clone pull --ff-only | Out-Null
    } else {
        Info "cloning $($s.repo)"
        git clone --depth 1 $s.repo $clone | Out-Null
    }

    if ($s.pip) {
        if (Get-Command uv -ErrorAction SilentlyContinue) { Info "uv sync"; Push-Location $clone; uv sync | Out-Null; Pop-Location }
        else { Info "pip install -e ."; python -m pip install -e $clone --quiet | Out-Null }
    }

    if ($s.layout -eq 'multi') {
        # Repo is a plugin: each directory under <subdir>/ is its own skill and needs
        # its own link, otherwise none of them are discoverable.
        $src = Join-Path $clone $s.subdir
        foreach ($d in Get-ChildItem -Path $src -Directory) {
            if (-not (Test-Path (Join-Path $d.FullName 'SKILL.md'))) { continue }
            Link-Dir (Join-Path $SkillsDir $d.Name) $d.FullName | Out-Null
            if (Verify-Skill $d.Name) { $installed++ } else { $failed += $d.Name }
        }
    } else {
        # Whole repo is one skill -- helpers/ must stay a sibling of SKILL.md.
        Link-Dir (Join-Path $SkillsDir $s.name) $clone | Out-Null
        if (Verify-Skill $s.name) { $installed++ } else { $failed += $s.name }
    }

}

# Repos that ship a Claude Code marketplace manifest are installed as plugins instead of
# linked by hand, so Claude owns their updates and uninstall. Both commands are no-ops
# when the marketplace/plugin is already present.
if ($manifest.marketplaces -and (Get-Command claude -ErrorAction SilentlyContinue)) {
    foreach ($m in $manifest.marketplaces) {
        Write-Host "`n[$($m.marketplace)]" -ForegroundColor Cyan
        Info "adding marketplace"
        claude plugin marketplace add $m.marketplace | Out-Null
        foreach ($p in $m.plugins) { Info "installing $p"; claude plugin install $p | Out-Null }
        Ok $m.marketplace
    }
} elseif ($manifest.marketplaces) {
    Warn "claude CLI not on PATH -- skipped marketplace plugins: $(($manifest.marketplaces | ForEach-Object { $_.marketplace }) -join ', ')"
}

if ($manifest.system) {
    if ($manifest.system.requires -contains 'ffmpeg') { $needFfmpeg = $true }
    foreach ($e in $manifest.system.env) {
        if (-not [Environment]::GetEnvironmentVariable($e.name, 'User')) { $needEnv += "$($e.name)  -- $($e.for)" }
    }
}

if ($needFfmpeg -and -not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    Write-Host "`n[ffmpeg]" -ForegroundColor Cyan
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Info "installing via winget (Gyan.FFmpeg)"
        winget install --id Gyan.FFmpeg -e --accept-source-agreements --accept-package-agreements --silent | Out-Null
        Warn "ffmpeg added to PATH -- restart your shell before using it"
    } else {
        Warn "ffmpeg missing and winget unavailable. Install manually: https://ffmpeg.org/download.html"
    }
}

$plugCount = @($manifest.marketplaces | ForEach-Object { $_.plugins }).Count
$mktCount  = @($manifest.marketplaces).Count
Write-Host "`n=== $plugCount plugin(s) from $mktCount marketplace(s), $installed linked skill(s) ===" -ForegroundColor Cyan
if ($failed.Count) { Fail "failed: $($failed -join ', ')" }
if ($needEnv.Count) {
    Write-Host "`nStill needed on this machine:" -ForegroundColor Yellow
    $needEnv | ForEach-Object { Write-Host "  - $_" }
    Write-Host '  Set with:  setx VARNAME "value"    (then restart your shell)'
}
Write-Host "`nRestart Claude Code to pick up the new plugins.`n"

