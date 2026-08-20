# Refreshes the vendored plugin wrappers under plugins/ from their upstream clones.
#
# Why vendoring is necessary: Claude Code's plugin loader only discovers skills under a
# plugin's skills/ directory. video-use and design-dna both put SKILL.md at their repo
# root, so pointing a marketplace entry straight at them finds nothing (verified: doing
# that on video-use surfaced only its nested manim-video skill). These wrappers restage
# the same files into the layout the loader expects. Both upstreams are MIT; LICENSE and
# NOTICE.md travel with each copy.
#
#   powershell -ExecutionPolicy Bypass -File sync-vendored.ps1
#
# Run it, then commit whatever changed.

$ErrorActionPreference = 'Continue'

$Root        = $PSScriptRoot
$ProjectsDir = Join-Path $HOME 'Projects'

# name -> @{ repo; skill folders to stage as skills/<key> }
$Vendored = @(
    @{
        name  = 'video-use'
        repo  = 'https://github.com/browser-use/video-use'
        # SKILL.md and helpers/ must stay siblings -- the skill calls helpers by bare name.
        skills = @(
            @{ as = 'video-use';   from = '.';                   include = @('SKILL.md', 'helpers') }
            @{ as = 'manim-video'; from = 'skills/manim-video';  include = @('*') }
        )
    },
    @{
        name  = 'design-dna'
        repo  = 'https://github.com/zanwei/design-dna'
        skills = @(
            @{ as = 'design-dna'; from = '.'; include = @('SKILL.md', 'references') }
        )
    }
)

foreach ($v in $Vendored) {
    $clone = Join-Path $ProjectsDir $v.name
    Write-Host "`n[$($v.name)]" -ForegroundColor Cyan

    if (Test-Path $clone) { git -C $clone pull --ff-only | Out-Null }
    else { git clone --depth 1 $v.repo $clone | Out-Null }

    $sha = (git -C $clone rev-parse --short HEAD).Trim()
    $pluginDir = Join-Path $Root "plugins\$($v.name)"
    $skillsDir = Join-Path $pluginDir 'skills'

    # Rebuild skills/ from scratch so files deleted upstream do not linger here.
    if (Test-Path $skillsDir) { Remove-Item $skillsDir -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $skillsDir | Out-Null

    foreach ($s in $v.skills) {
        $dest = Join-Path $skillsDir $s.as
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        $src = Join-Path $clone $s.from
        foreach ($pattern in $s.include) {
            $p = Join-Path $src $pattern
            # A directory must be copied as itself, not as its contents: SKILL.md resolves
            # helpers/ and references/ by relative path, so flattening them breaks the skill.
            if ((Test-Path -LiteralPath $p) -and (Get-Item -LiteralPath $p).PSIsContainer) {
                Copy-Item -LiteralPath $p -Destination $dest -Recurse -Force
            } else {
                Get-ChildItem -Path $p -Force -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -ne '.git' } |
                    ForEach-Object { Copy-Item $_.FullName -Destination $dest -Recurse -Force }
            }
        }
        $count = (Get-ChildItem $dest -Recurse -File).Count
        Write-Host "  staged skills/$($s.as)  ($count files)"
    }

    Copy-Item (Join-Path $clone 'LICENSE') -Destination (Join-Path $pluginDir 'LICENSE') -Force

    @"
# Third-party notice

The contents of ``skills/`` in this directory are vendored from:

  $($v.repo)
  commit $sha
  synced $(Get-Date -Format 'yyyy-MM-dd')

Licensed MIT by the upstream authors; ``LICENSE`` beside this file is their copy,
unmodified. The files are restaged into ``skills/<name>/`` because Claude Code's plugin
loader only discovers skills there, and upstream keeps ``SKILL.md`` at the repo root.
No content was edited.

Refresh with ``sync-vendored.ps1`` in the repo root.
"@ | Set-Content (Join-Path $pluginDir 'NOTICE.md') -Encoding utf8

    Write-Host "  upstream @ $sha" -ForegroundColor DarkGray
}

Write-Host "`nDone. Review with 'git status', then commit.`n"
