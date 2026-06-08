#!/bin/bash
# Tiberian Sun Audio Hooks — Uninstaller
# Removes only the Tiberian Sun packs. Leaves shared scripts/hooks and other packs
# (SC2, Halo) intact — unless this was the only thing installed, then it fully cleans up.

set -e

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'
DIM='\033[2m'; BOLD='\033[1m'; NC='\033[0m'
print_step()    { echo -e "  ${CYAN}▶${NC} $1"; }
print_success() { echo -e "  ${GREEN}✓${NC} $1"; }
print_warning() { echo -e "  ${YELLOW}⚠${NC} $1"; }

PACKS=(gdi nod)
SOUNDS_DIR="$HOME/.claude/sounds"
SETTINGS_FILE="$HOME/.claude/settings.json"
CACHE_FILE="$HOME/.cache/sc2-claude-last-error"

echo ""
echo -e "  ${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "  ${CYAN}║${NC}  ${BOLD}TIBERIAN SUN AUDIO HOOKS — Uninstall${NC}    ${CYAN}║${NC}"
echo -e "  ${CYAN}╚══════════════════════════════════════════╝${NC}"
echo ""

if [ ! -d "$SOUNDS_DIR" ]; then
  print_warning "Nothing to uninstall — ~/.claude/sounds not found"; echo ""; exit 0
fi

present=(); for p in "${PACKS[@]}"; do [ -d "$SOUNDS_DIR/$p" ] && present+=("$p"); done
if [ ${#present[@]} -eq 0 ]; then
  print_warning "No Tiberian Sun packs found in ~/.claude/sounds"; echo ""; exit 0
fi

echo -e "  ${YELLOW}This will remove these Tiberian Sun packs:${NC} ${present[*]}"
echo ""
if [ -t 0 ]; then read -p "  Continue? [y/N]: " CONFIRM
else CONFIRM=$(bash -c 'read -p "  Continue? [y/N]: " c < /dev/tty && echo "$c"' 2>/dev/null) || CONFIRM="y"; fi
[[ ! "$CONFIRM" =~ ^[Yy]$ ]] && { echo -e "\n  ${DIM}Aborted.${NC}\n"; exit 0; }
echo ""

# Remove Tiberian Sun pack dirs
print_step "Removing Tiberian Sun packs..."
active_target="$(basename "$(readlink "$SOUNDS_DIR/active" 2>/dev/null)" 2>/dev/null || true)"
for p in "${present[@]}"; do rm -rf "$SOUNDS_DIR/$p"; print_success "removed $p"; done

# What non-script pack folders remain?
remaining=()
for d in "$SOUNDS_DIR"/*/; do
  name="$(basename "$d")"; [ -L "${d%/}" ] && continue; [ "${name#_}" != "$name" ] && continue
  remaining+=("$name")
done

if [ ${#remaining[@]} -gt 0 ]; then
  # Other packs still here — keep shared infra, just fix the active symlink
  if printf '%s\n' "${present[@]}" | grep -qx "$active_target" || [ -z "$active_target" ]; then
    rm -f "$SOUNDS_DIR/active"; ln -s "$SOUNDS_DIR/${remaining[0]}" "$SOUNDS_DIR/active"
    print_success "active voice repointed to: ${remaining[0]}"
  fi
  echo ""
  print_success "Tiberian Sun removed. Kept shared scripts + hooks for remaining packs: ${remaining[*]}"
  echo ""
  exit 0
fi

# No packs left — full cleanup (scripts, hooks, cache)
print_step "No packs remain — removing shared scripts + hooks..."
if [ -f "$SETTINGS_FILE" ] && command -v python3 &>/dev/null; then
  cp "$SETTINGS_FILE" "$SETTINGS_FILE.backup"
  python3 << 'PYEOF'
import json, os
p = os.path.expanduser("~/.claude/settings.json")
with open(p) as f: settings = json.load(f)
MARKER = ".claude/sounds/"
hooks = settings.get("hooks", {}); drop=[]
for event, entries in hooks.items():
    kept = [e for e in entries if not any(MARKER in h.get("command","") for h in e.get("hooks",[]))]
    if kept: hooks[event] = kept
    else: drop.append(event)
for e in drop: hooks.pop(e, None)
if hooks: settings["hooks"] = hooks
else: settings.pop("hooks", None)
with open(p,"w") as f: json.dump(settings, f, indent=2); f.write("\n")
PYEOF
  print_success "hooks removed from settings.json (backup saved)"
fi
rm -rf "$SOUNDS_DIR"; print_success "removed ~/.claude/sounds/"
[ -f "$CACHE_FILE" ] && { rm -f "$CACHE_FILE"; print_success "removed error cooldown cache"; }
echo ""
print_success "Fully uninstalled."
echo ""
