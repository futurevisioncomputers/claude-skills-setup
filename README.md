# claude-skills-setup

One command to get the same Claude Code skills onto any machine.

## Why this exists

`~/.claude/skills/` is a **local folder**. It is not tied to your Claude account and it does
not sync. Signing into Claude on a second device authenticates you — it copies no skill files.
Every machine has to install them, so this repo makes that a single command.

## Use it on a new machine

**Windows**

```powershell
git clone https://github.com/<you>/claude-skills-setup "$HOME\Projects\claude-skills-setup"
powershell -ExecutionPolicy Bypass -File "$HOME\Projects\claude-skills-setup\install.ps1"
```

**macOS / Linux**

```bash
git clone https://github.com/<you>/claude-skills-setup ~/Developer/claude-skills-setup
bash ~/Developer/claude-skills-setup/install.sh
```

Restart Claude Code afterwards so it rescans the skills directory.

## What the installer does

For every entry in `skills.json`:

1. Clones the skill repo (or `git pull --ff-only` if already present) into `~/Projects` on
   Windows, `~/Developer` on macOS/Linux.
2. Installs Python deps when the entry sets `pip: true`.
3. Links it into `~/.claude/skills/` — a **junction** on Windows (symlinks there need admin
   or Developer Mode; junctions don't), a symlink elsewhere.
4. Verifies by reading `SKILL.md` *through* the link. Checking that the link exists is not
   enough — a junction pointing at a missing target still passes an existence check.
5. Adds each `marketplaces` entry and installs its plugins through the `claude` CLI.
6. Installs `ffmpeg` if some skill needs it and it isn't present.
7. Prints any API keys still missing on this machine.

Re-running is safe and is also how you update: it pulls every repo and repairs broken links.

## Adding a skill

Append to `skills.json` and re-run the installer on each machine. Two kinds of entry exist.

### `marketplaces` — repos with a Claude Code plugin manifest

If the repo has `.claude-plugin/marketplace.json`, prefer this. Claude owns the install,
updates, and uninstall; nothing is linked by hand.

| Field | Meaning |
|-------|---------|
| `marketplace` | `owner/repo` passed to `claude plugin marketplace add`. |
| `plugins` | Plugin ids to install, e.g. `gsap-skills@gsap-skills`. |

### `skills` — everything else

| Field | Meaning |
|-------|---------|
| `name` | Clone directory name. For `layout: single`, also the skill name. |
| `repo` | Git URL. |
| `layout` | `single` = the whole repo is one skill. `multi` = every directory under `subdir` is its own skill and gets its own link. |
| `subdir` | For `multi` only — usually `skills`. |
| `pip` | `true` runs `uv sync`, or `pip install -e .` when `uv` is absent. |
| `requires` | System tools to install. `ffmpeg` is currently the only one handled. |
| `env` | Env vars the skill needs; the installer reports missing ones instead of prompting. |

**Which layout?** If the repo root has a `SKILL.md`, it's `single`. If it has
`.claude-plugin/plugin.json` and a `skills/` folder, it's `multi` — link each skill folder
individually or none of them are discoverable.

## Secrets

Never commit API keys. The installer only reports what's missing. Set them per machine:

```powershell
setx ELEVENLABS_API_KEY "your-key"     # Windows, then restart the shell
```

```bash
echo 'export ELEVENLABS_API_KEY="your-key"' >> ~/.zshrc   # macOS/Linux
```

## Currently installed

| Skill | Source | How | Needs |
|-------|--------|-----|-------|
| `video-use` | [browser-use/video-use](https://github.com/browser-use/video-use) | linked | ffmpeg, `ELEVENLABS_API_KEY` |
| `design-dna` | [zanwei/design-dna](https://github.com/zanwei/design-dna) | linked | nothing |
| `gsap-core`, `gsap-timeline`, `gsap-scrolltrigger`, `gsap-plugins`, `gsap-utils`, `gsap-react`, `gsap-frameworks`, `gsap-performance` | [greensock/gsap-skills](https://github.com/greensock/gsap-skills) | plugin | nothing |

## Tested on

- **Windows** — `install.ps1` run end to end on Windows 11, repeatedly, including the
  re-run/update path.
- **macOS / Linux** — `install.sh` is syntax-checked and written for bash 3.2 (the version
  macOS ships), but has not yet been executed on a real machine. Expect to shake out
  something the first time you run it.
