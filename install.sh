#!/bin/bash
# Tiberian Sun Audio Hooks — Interactive Installer
# C&C Tiberian Sun voice lines for Claude Code event hooks. macOS only (uses afplay).
# Additive: installs alongside any existing packs (SC2, Halo) without clobbering them.

set -e

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'
DIM='\033[2m'; BOLD='\033[1m'; NC='\033[0m'
print_step()    { echo -e "  ${CYAN}▶${NC} $1"; }
print_success() { echo -e "  ${GREEN}✓${NC} $1"; }
print_warning() { echo -e "  ${YELLOW}⚠${NC} $1"; }
print_error()   { echo -e "  ${RED}✗${NC} $1"; }

FORCE=false
for arg in "$@"; do [ "$arg" = "--force" ] && FORCE=true; done

PACKS=(tiberian-sun-gdi tiberian-sun-cabal)

echo ""
echo -e "  ${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "  ${CYAN}║${NC}     ${BOLD}TIBERIAN SUN AUDIO HOOKS${NC}             ${CYAN}║${NC}"
echo -e "  ${CYAN}║${NC}  ${DIM}EVA + CABAL for Claude Code${NC}             ${CYAN}║${NC}"
echo -e "  ${CYAN}╚══════════════════════════════════════════╝${NC}"
echo ""

print_step "Checking requirements..."
if [[ "$(uname)" == "Darwin" ]]; then
  print_success "macOS detected"
else
  print_warning "Non-macOS detected — afplay won't work"
  echo -e "  ${DIM}  Swap afplay for aplay/paplay/mpv in play-random.sh, then re-run with --force${NC}"
  [ "$FORCE" = false ] && exit 1
  print_warning "Continuing with --force..."
fi
if command -v python3 &>/dev/null; then
  print_success "python3 found"
else
  print_error "python3 is required (for hooks merge)"; exit 1
fi
CLAUDE_DIR="$HOME/.claude"
[ -d "$CLAUDE_DIR" ] && print_success "Claude Code directory found" || { print_warning "~/.claude not found — creating it"; mkdir -p "$CLAUDE_DIR"; }
echo ""

# ── Source detection (local repo vs remote curl) ────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
if [[ -d "$SCRIPT_DIR/sounds/tiberian-sun-gdi" ]]; then
  SOURCE_DIR="$SCRIPT_DIR"
else
  print_step "Downloading from GitHub..."
  SOURCE_DIR=$(mktemp -d); trap "rm -rf '$SOURCE_DIR'" EXIT
  curl -fsSL https://github.com/samhayek-code/tiberian-sun-audio-hooks/archive/main.tar.gz \
    | tar xz -C "$SOURCE_DIR" --strip-components=1 \
    || { print_error "Download failed"; exit 1; }
  print_success "Downloaded"; echo ""
fi

# ── Pack picker ─────────────────────────────────────────────────────────────
echo -e "  ${CYAN}┌────────────────────────────────────────────────┐${NC}"
echo -e "  ${CYAN}│${NC}  ${BOLD}SELECT YOUR VOICE${NC}                              ${CYAN}│${NC}"
echo -e "  ${CYAN}├────────────────────────────────────────────────┤${NC}"
echo -e "  ${CYAN}│${NC}   ${BOLD}[1]${NC} GDI EVA  — ${DIM}\"Construction complete\"${NC}        ${CYAN}│${NC}"
echo -e "  ${CYAN}│${NC}   ${BOLD}[2]${NC} CABAL    — ${DIM}\"Prepare for sterilization\"${NC}     ${CYAN}│${NC}"
echo -e "  ${CYAN}└────────────────────────────────────────────────┘${NC}"
echo ""
if [ -t 0 ]; then
  read -p "  Enter choice [1-2, default=1]: " CHOICE
else
  CHOICE=$(bash -c 'read -p "  Enter choice [1-2, default=1]: " c < /dev/tty && echo "$c"' 2>/dev/null) || { CHOICE="1"; echo -e "  ${DIM}Non-interactive — defaulting to GDI EVA${NC}"; }
fi
case "$CHOICE" in 2) PACK="tiberian-sun-cabal" ;; *) PACK="tiberian-sun-gdi" ;; esac
echo ""

SOUNDS_DEST="$CLAUDE_DIR/sounds"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"

# ── Copy packs (additive) ───────────────────────────────────────────────────
print_step "Deploying Tiberian Sun packs..."
mkdir -p "$SOUNDS_DEST"
for pack in "${PACKS[@]}"; do
  rm -rf "$SOUNDS_DEST/$pack"
  cp -R "$SOURCE_DIR/sounds/$pack" "$SOUNDS_DEST/"
  count=$(find "$SOUNDS_DEST/$pack" \( -name '*.mp3' -o -name '*.m4a' \) | wc -l | tr -d ' ')
  print_success "$pack ($count clips)"
done

print_step "Installing scripts..."
for s in play-random.sh play-error.sh set-faction.sh; do
  cp "$SOURCE_DIR/sounds/$s" "$SOUNDS_DEST/"; chmod +x "$SOUNDS_DEST/$s"
done
print_success "play-random.sh, play-error.sh, set-faction.sh"

print_step "Setting active voice to: $PACK"
rm -f "$SOUNDS_DEST/active"; ln -s "$SOUNDS_DEST/$PACK" "$SOUNDS_DEST/active"
print_success "Active: $PACK"

# ── Merge hooks into settings.json (idempotent, shared with SC2 / Halo) ──────
print_step "Configuring hooks..."
mkdir -p "$CLAUDE_DIR"
[ -f "$SETTINGS_FILE" ] || echo "{}" > "$SETTINGS_FILE"
cp "$SETTINGS_FILE" "$SETTINGS_FILE.backup"
python3 << 'PYEOF'
import json, os
p = os.path.expanduser("~/.claude/settings.json")
with open(p) as f: settings = json.load(f)
HOOKS = {
  "SessionStart": {"hooks": [{"type":"command","command":"$HOME/.claude/sounds/play-random.sh $HOME/.claude/sounds/active/session-start"}]},
  "Stop": {"hooks": [{"type":"command","command":"$HOME/.claude/sounds/play-random.sh $HOME/.claude/sounds/active/task-complete"}]},
  "Notification": {"matcher":"permission_prompt","hooks": [{"type":"command","command":"$HOME/.claude/sounds/play-random.sh $HOME/.claude/sounds/active/needs-permission"}]},
  "PostToolUseFailure": {"matcher":"Bash","hooks": [{"type":"command","command":"$HOME/.claude/sounds/play-error.sh"}]},
}
MARKER = ".claude/sounds/"
hooks = settings.get("hooks", {})
for event, entry in HOOKS.items():
    kept = [e for e in hooks.get(event, []) if not any(MARKER in h.get("command","") for h in e.get("hooks",[]))]
    kept.append(entry)
    hooks[event] = kept
settings["hooks"] = hooks
with open(p,"w") as f: json.dump(settings, f, indent=2); f.write("\n")
PYEOF
print_success "Hooks merged into settings.json (backup: settings.json.backup)"

echo ""
echo -e "  ${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "  ${GREEN}║${NC}        ${BOLD}INSTALLATION COMPLETE${NC}             ${GREEN}║${NC}"
echo -e "  ${GREEN}╚══════════════════════════════════════════╝${NC}"
case "$PACK" in
  tiberian-sun-gdi)   echo -e "  ${DIM}\"Establishing Battlefield Control. Stand by.\"${NC}" ;;
  tiberian-sun-cabal) echo -e "  ${DIM}\"Your probability of success is insignificant and dropping.\"${NC}" ;;
esac
echo ""
echo -e "  ${CYAN}Switch voice:${NC}  ~/.claude/sounds/set-faction.sh tiberian-sun-cabal"
echo -e "  ${DIM}(also works with SC2 / Halo packs if installed)${NC}"
echo -e "  ${CYAN}Test:${NC}         ~/.claude/sounds/play-random.sh ~/.claude/sounds/active/session-start"
echo -e "  ${CYAN}Uninstall:${NC}    ./uninstall.sh"
echo ""
echo -e "  ${DIM}Start a new Claude Code session to hear it.${NC}"
echo ""
