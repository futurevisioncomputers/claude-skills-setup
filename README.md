# fv-skills

A Claude Code plugin marketplace holding every skill this account uses, plus a bootstrap
script for the things a marketplace cannot install.

## Why this exists

`~/.claude/skills/` is a **local folder**. It is not tied to your Claude account and it does
not sync. Signing into Claude on a second device authenticates you — it copies no skill
files. Publishing the skills as a marketplace makes them one command away on any machine,
and makes them visible in `/plugin` where Claude manages their updates and removal.

## Use it on a new machine

```bash
claude plugin marketplace add futurevisioncomputers/claude-skills-setup
claude plugin install video-use@fv-skills
claude plugin install design-dna@fv-skills
claude plugin install gsap-skills@fv-skills
claude plugin install superseo@fv-skills
```

The repo is private, so the machine needs GitHub access — `gh auth login` once, or any
working git credential helper.

Then, for the system-level pieces no marketplace can deliver (ffmpeg, API keys):

```powershell
git clone https://github.com/futurevisioncomputers/claude-skills-setup "$HOME\Projects\claude-skills-setup"
powershell -ExecutionPolicy Bypass -File "$HOME\Projects\claude-skills-setup\install.ps1"
```

```bash
git clone https://github.com/futurevisioncomputers/claude-skills-setup ~/Developer/claude-skills-setup
bash ~/Developer/claude-skills-setup/install.sh
```

The installer performs the marketplace adds too, so on a fresh machine you can skip straight
to it. Restart Claude Code afterwards.

## What's in the marketplace

| Plugin | Skills | Delivery | Needs |
|--------|--------|----------|-------|
| `video-use` | `video-use`, `manim-video` | vendored wrapper | ffmpeg, `ELEVENLABS_API_KEY` |
| `design-dna` | `design-dna` | vendored wrapper | — |
| `gsap-skills` | 8 GSAP skills | referenced upstream | — |
| `superseo` | 11 SEO skills | referenced upstream | — |

## Vendored vs referenced

Claude Code's plugin loader **only discovers skills under a plugin's `skills/` directory**.

- `gsap-skills` and `superseo` already use the canonical `skills/<name>/SKILL.md` layout, so
  the marketplace points straight at their GitHub URLs. Nothing is copied and upstream stays
  authoritative. A `plugin.json` in the source repo turns out to be optional; the layout is
  what matters.
- `video-use` and `design-dna` keep `SKILL.md` at their repo root. Referencing them directly
  finds nothing — verified: doing that with `video-use` surfaced only its nested
  `manim-video` skill and missed the real one. `plugins/*/` restages their files into the
  expected layout. Both are MIT; each wrapper carries the upstream `LICENSE` plus a
  `NOTICE.md` recording the source commit.

Refresh the vendored copies when upstream moves:

```powershell
powershell -ExecutionPolicy Bypass -File sync-vendored.ps1
git status      # review, then commit
```

## Adding a skill

1. Check the source repo's layout. `skills/<name>/SKILL.md` present → reference it by URL.
   `SKILL.md` at the root → it needs a wrapper under `plugins/`, added to the `$Vendored`
   list in `sync-vendored.ps1`.
2. Add an entry to `.claude-plugin/marketplace.json`.
3. Add the plugin id to `skills.json` so the installer picks it up on other machines.
4. Commit and push. Other machines get it with `claude plugin marketplace update fv-skills`
   followed by `claude plugin install <name>@fv-skills`.

## skills.json

Read by the installers.

| Key | Meaning |
|-----|---------|
| `marketplaces[].marketplace` | Passed to `claude plugin marketplace add`. |
| `marketplaces[].plugins` | Plugin ids to install. |
| `skills[]` | Legacy clone-and-link path, kept for anything that can't be a plugin. Currently empty. |
| `system.requires` | System tools to install. `ffmpeg` is the only one handled. |
| `system.env` | API keys; the installer reports missing ones rather than prompting. |

## Secrets

Never committed. Set them per machine:

```powershell
setx ELEVENLABS_API_KEY "your-key"     # Windows, then restart the shell
```

```bash
echo 'export ELEVENLABS_API_KEY="your-key"' >> ~/.zshrc   # macOS/Linux
```

## Tested on

- **Windows** — the full path was exercised end to end: marketplace added from the private
  GitHub repo, all four plugins installed, skill inventories confirmed with
  `claude plugin details`, and the vendored `helpers/` scripts run from the installed plugin
  copy.
- **macOS / Linux** — `install.sh` is syntax-checked and written for bash 3.2 (the version
  macOS ships), but has not been executed on a real machine. Expect to shake out something
  the first time you run it.
