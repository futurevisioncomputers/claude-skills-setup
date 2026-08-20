#!/usr/bin/env bash
# Installs every skill listed in skills.json into ~/.claude/skills on macOS / Linux.
# Idempotent: re-run any time to pull updates and repair broken links.
#   bash install.sh
set -euo pipefail

MANIFEST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/skills.json"
PROJECTS_DIR="$HOME/Developer"
SKILLS_DIR="$HOME/.claude/skills"

info() { echo "  $*"; }
ok()   { echo "  OK   $*"; }
warn() { echo "  WARN $*"; }
fail() { echo "  FAIL $*"; }

command -v git >/dev/null || { echo "git is required and not on PATH"; exit 1; }
command -v python3 >/dev/null || { echo "python3 is required and not on PATH"; exit 1; }

mkdir -p "$PROJECTS_DIR" "$SKILLS_DIR"

# Read the manifest through python3 so the script has no jq dependency.
read_manifest() { python3 -c "
import json, sys
m = json.load(open(sys.argv[1]))
for s in m['skills']:
    print('\t'.join([
        s['name'], s['repo'], s['layout'], s.get('subdir', ''),
        '1' if s.get('pip') else '0',
        ','.join(s.get('requires', [])),
        ','.join(s.get('env', [])),
    ]))
" "$MANIFEST"; }

link_dir() {  # link_dir <link> <target>
    local link="$1" target="$2"
    [ -d "$target" ] || { fail "target missing: $target"; return 1; }
    if [ -L "$link" ]; then rm -f "$link"
    elif [ -e "$link" ]; then warn "$link is a real directory, not a link -- leaving it alone"; return 1
    fi
    ln -sfn "$target" "$link"
}

verify_skill() {  # verify_skill <name>
    local f="$SKILLS_DIR/$1/SKILL.md"
    if [ -r "$f" ]; then ok "$1 ($(($(wc -c < "$f") / 1024)) KB)"; return 0; fi
    fail "$1 -- SKILL.md not readable through the link"; return 1
}

echo ""
echo "=== Claude skills bootstrap ==="

need_ffmpeg=0; installed=0
need_env=""   # newline-delimited; arrays are unsafe on bash 3.2 + set -u
failed=""
mkt_count=$(python3 -c "import json,sys; print(len(json.load(open(sys.argv[1])).get('marketplaces', [])))" "$MANIFEST")

while IFS=$'\t' read -r name repo layout subdir pip requires envs; do
    echo ""
    echo "[$name]"
    clone="$PROJECTS_DIR/$name"

    if [ -d "$clone/.git" ]; then info "pulling latest"; git -C "$clone" pull --ff-only >/dev/null 2>&1 || warn "pull failed, keeping existing checkout"
    else info "cloning $repo"; git clone --depth 1 "$repo" "$clone" >/dev/null 2>&1
    fi

    if [ "$pip" = "1" ]; then
        if command -v uv >/dev/null; then info "uv sync"; (cd "$clone" && uv sync >/dev/null 2>&1)
        else info "pip install -e ."; python3 -m pip install -e "$clone" --quiet >/dev/null 2>&1
        fi
    fi

    if [ "$layout" = "multi" ]; then
        # Repo is a plugin: each directory under <subdir>/ is its own skill and needs
        # its own link, otherwise none of them are discoverable.
        for d in "$clone/$subdir"/*/; do
            [ -f "${d}SKILL.md" ] || continue
            n="$(basename "$d")"
            link_dir "$SKILLS_DIR/$n" "${d%/}" || true
            if verify_skill "$n"; then installed=$((installed + 1)); else failed="$failed $n"; fi
        done
    else
        # Whole repo is one skill -- helpers/ must stay a sibling of SKILL.md.
        link_dir "$SKILLS_DIR/$name" "$clone" || true
        if verify_skill "$name"; then installed=$((installed + 1)); else failed="$failed $name"; fi
    fi

    if [[ ",$requires," == *",ffmpeg,"* ]]; then need_ffmpeg=1; fi
    if [ -n "$envs" ]; then
        IFS=',' read -ra evs <<< "$envs"
        for e in "${evs[@]}"; do
            if [ -z "${!e:-}" ]; then need_env="$need_env$e  (needed by $name)
"; fi
        done
    fi
done < <(read_manifest)

# Repos that ship a Claude Code marketplace manifest are installed as plugins instead of
# linked by hand, so Claude owns their updates and uninstall. Both commands are no-ops
# when the marketplace/plugin is already present.
read_marketplaces() { python3 -c "
import json, sys
m = json.load(open(sys.argv[1]))
for mk in m.get('marketplaces', []):
    print('\t'.join([mk['marketplace'], ','.join(mk.get('plugins', []))]))
" "$MANIFEST"; }

while IFS=$'\t' read -r mkt plugins; do
    [ -n "$mkt" ] || continue
    echo ""
    echo "[$mkt]"
    if ! command -v claude >/dev/null; then warn "claude CLI not on PATH -- skipped"; continue; fi
    info "adding marketplace"
    claude plugin marketplace add "$mkt" >/dev/null 2>&1 || warn "marketplace add reported an error (may already exist)"
    IFS=',' read -ra pls <<< "$plugins"
    for p in "${pls[@]}"; do
        [ -n "$p" ] || continue
        info "installing $p"
        claude plugin install "$p" >/dev/null 2>&1 || warn "install reported an error (may already be installed)"
    done
    ok "$mkt"
done < <(read_marketplaces)

if [ "$need_ffmpeg" = "1" ] && ! command -v ffmpeg >/dev/null; then
    echo ""
    echo "[ffmpeg]"
    if command -v brew >/dev/null; then info "brew install ffmpeg"; brew install ffmpeg
    elif command -v apt-get >/dev/null; then info "apt-get install ffmpeg (sudo)"; sudo apt-get update -qq && sudo apt-get install -y ffmpeg
    elif command -v pacman >/dev/null; then info "pacman -S ffmpeg (sudo)"; sudo pacman -S --noconfirm ffmpeg
    else warn "ffmpeg missing and no known package manager. Install manually: https://ffmpeg.org/download.html"
    fi
fi

echo ""
echo "=== $installed linked skill(s), $mkt_count marketplace plugin(s) ==="
if [ -n "$failed" ]; then fail "failed:$failed"; fi
if [ -n "$need_env" ]; then
    echo ""
    echo "Still needed on this machine:"
    printf '%s' "$need_env" | while IFS= read -r e; do
        if [ -n "$e" ]; then echo "  - $e"; fi
    done
    echo "  Add to ~/.zshrc or ~/.bashrc:  export VARNAME=\"value\""
fi
echo ""
echo "Restart Claude Code to pick up newly linked skills."
echo ""
