#!/usr/bin/env bash
# GitHub Update — remove the plugin and the zen-gh helper.
#
# The tracked app state (~/.config/omarchy/github-update) is kept unless you
# pass --purge, so a reinstall keeps your ignored/links/transactions.
set -euo pipefail

PLUGIN_ID="github-update"
LEGACY_ID="dbeaudry.zengithubupdate"
SHELL_JSON="$HOME/.config/omarchy/shell.json"
PURGE=0
[ "${1:-}" = "--purge" ] && PURGE=1

echo "GitHub Update — uninstalling"

rm -rf "$HOME/.config/omarchy/plugins/$PLUGIN_ID"
rm -rf "$HOME/.config/omarchy/plugins/$LEGACY_ID"
rm -f "$HOME/.local/bin/zen-gh"

if [ "$PURGE" = 1 ]; then
  rm -rf "$HOME/.config/omarchy/github-update"
  echo "  removed tracked app state"
else
  echo "  kept tracked app state: ~/.config/omarchy/github-update"
fi

if [ -f "$SHELL_JSON" ]; then
  python3 - "$SHELL_JSON" "$PLUGIN_ID" "$LEGACY_ID" <<'PY'
import json, sys

path, plugin, legacy = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as fh:
    data = json.load(fh)
layout = data.get("bar", {}).get("layout", {})
removed = False
for side in ("left", "center", "centerBegin", "centerEnd", "right"):
    entries = layout.get(side) or []
    kept = [e for e in entries
            if not (isinstance(e, dict) and e.get("id") in (plugin, legacy))]
    if len(kept) != len(entries):
        layout[side] = kept
        removed = True
if removed:
    with open(path, "w") as fh:
        json.dump(data, fh, indent=2)
        fh.write("\n")
    print("  removed the bar entry")
else:
    print("  no bar entry to remove")
PY
fi

echo "  (the 'github-update' menu row and any update.githubapps.* rows are left in place — delete by hand if you want them gone)"

if command -v omarchy >/dev/null 2>&1; then
  omarchy restart shell >/dev/null 2>&1 || true
fi

echo "Done."
