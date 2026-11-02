#!/usr/bin/env bash
# GitHub Update — install / restore into the current Omarchy session.
#
# Copies the bar plugin and the `zen-gh` helper, wires the widget into the bar
# and the Super+Space menu, then refreshes the menu rows it auto-manages.
# Safe to run again: existing entries are preserved and the old pre-rename id
# (dbeaudry.zengithubupdate) is migrated automatically.
set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="github-update"
LEGACY_ID="dbeaudry.zengithubupdate"   # pre-rename plugin id, migrated on install
SHELL_JSON="$HOME/.config/omarchy/shell.json"
MENU_FILE="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"

say() { printf '  %s\n' "$*"; }

echo "GitHub Update — installing from $HERE"

# --- requirements ---------------------------------------------------------
command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 is required." >&2; exit 1; }

# --- files ----------------------------------------------------------------
install -d "$HOME/.local/bin" \
           "$HOME/.config/omarchy/plugins/$PLUGIN_ID"

install -m 755 "$HERE/files/.local/bin/zen-gh" "$HOME/.local/bin/zen-gh"
install -m 644 "$HERE/files/.config/omarchy/plugins/$PLUGIN_ID/manifest.json" \
               "$HOME/.config/omarchy/plugins/$PLUGIN_ID/manifest.json"
install -m 644 "$HERE/files/.config/omarchy/plugins/$PLUGIN_ID/Panel.qml" \
               "$HOME/.config/omarchy/plugins/$PLUGIN_ID/Panel.qml"

# --- migrate from the pre-rename plugin id ---------------------------------
if [ -d "$HOME/.config/omarchy/plugins/$LEGACY_ID" ]; then
  rm -rf "$HOME/.config/omarchy/plugins/$LEGACY_ID"
  say "removed legacy plugin folder ($LEGACY_ID)"
fi

# --- bar widget -----------------------------------------------------------
if [ -f "$SHELL_JSON" ]; then
  python3 - "$SHELL_JSON" "$PLUGIN_ID" "$LEGACY_ID" <<'PY'
import json, sys

path, plugin, legacy = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as fh:
    data = json.load(fh)
layout = data.setdefault("bar", {}).setdefault("layout", {})
changed = False
for side in ("left", "center", "centerBegin", "centerEnd", "right"):
    entries = layout.get(side) or []
    rebuilt = []
    side_changed = False
    for e in entries:
        if isinstance(e, dict) and e.get("id") == legacy:
            if side == "right":
                rebuilt.append({"id": plugin})
            side_changed = True
            continue
        rebuilt.append(e)
    if side_changed:
        layout[side] = rebuilt
        changed = True
        print(f"  migrated legacy bar entry ({legacy}) on {side}")
right = layout.setdefault("right", [])
if not any(isinstance(e, dict) and e.get("id") == plugin for e in right):
    right.append({"id": plugin})
    changed = True
    print(f"  added {plugin} to the bar (right side)")
if changed:
    with open(path, "w") as fh:
        json.dump(data, fh, indent=2)
        fh.write("\n")
PY
else
  say "no shell.json found — add { \"id\": \"$PLUGIN_ID\" } to bar.layout.right yourself"
fi

# --- main menu entry ------------------------------------------------------
if [ -f "$MENU_FILE" ]; then
  python3 - "$MENU_FILE" "$PLUGIN_ID" "$LEGACY_ID" <<'PY'
import json, re, sys, time, shutil

path, plugin, legacy = sys.argv[1], sys.argv[2], sys.argv[3]
row = ('  "github-update": ' + json.dumps(
    {
        "icon": "\U000F0907",
        "label": "GitHub Update",
        "aliases": ["github", "github-update", "updates"],
        "description": "Track, update and install GitHub projects",
        "action": "omarchy-shell %s toggle" % plugin,
    },
    ensure_ascii=False,
) + '\n')

with open(path) as fh:
    text = fh.read()

# Fix any stale action from the pre-rename id, wherever it appears.
text = text.replace(
    '"action":"omarchy-shell %s' % legacy,
    '"action":"omarchy-shell %s' % plugin,
)

changed = False
lines = text.split("\n")
kept = []
for ln in lines:
    m = re.match(r'^\s*"((?:[^"\\]|\\.)+)"\s*:', ln)
    if m and m.group(1) == "update.githubapps.zen":
        changed = True
        continue  # drop the legacy launcher row
    kept.append(ln)

if '"github-update"' not in "\n".join(kept):
    close = None
    for i in range(len(kept) - 1, -1, -1):
        if kept[i].strip() == "}":
            close = i
            break
    if close is None:
        kept.append(row.rstrip("\n"))
        kept.append("}")
    else:
        for i in range(close - 1, -1, -1):
            s = kept[i].strip()
            if s == "" or s.startswith("//") or s in ("{", "[") or kept[i].rstrip().endswith("{") or kept[i].rstrip().endswith("["):
                continue
            if not kept[i].rstrip().endswith(","):
                kept[i] = kept[i].rstrip() + ","
            break
        kept.insert(close, row.rstrip("\n"))
    changed = True

if changed:
    shutil.copy2(path, path + ".bak." + str(int(time.time())))
    out = "\n".join(kept)
    if not out.endswith("\n"):
        out += "\n"
    with open(path, "w") as fh:
        fh.write(out)
    say "updated the main menu (GitHub Update row)"
else:
    say "main menu already set up (GitHub Update row)"
PY
else
  say "no menu file found — skip the Super+Space entry"
fi

# --- refresh the auto-managed update.githubapps.* rows ---------------------
if command -v zen-gh >/dev/null 2>&1; then
  zen-gh sync-menu >/dev/null 2>&1 || true
fi

# --- shell reload ---------------------------------------------------------
if command -v omarchy >/dev/null 2>&1; then
  say "restarting the Omarchy shell"
  omarchy restart shell >/dev/null 2>&1 || true
fi

echo
echo "Done. Look for the rabbit icon on the right side of the bar,"
echo "or press Super+Space and type 'github'."
echo "If the widget is missing, run: omarchy restart shell"
