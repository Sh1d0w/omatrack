#!/usr/bin/env bash
# Install the Quattro Time Tracker plugin into the Omarchy third-party plugin
# dir. Copies only the runtime files: the plugin registry forbids symlinks, so
# a live dev checkout cannot be linked. Re-run after any change — the shell
# hot-reloads plugin files on save (run `omarchy restart shell` if a
# Service.qml change does not take effect).
set -euo pipefail

PLUGIN_ID="io.github.sh1d0w.timetrack"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${OMARCHY_PLUGINS_DIR:-$HOME/.config/omarchy/plugins}/$PLUGIN_ID"

echo "Installing $PLUGIN_ID"
echo "  from: $SRC"
echo "  to:   $DEST"

# The destination is a generated copy; wipe it so removed files don't survive.
rm -rf "$DEST"
mkdir -p "$DEST/components" "$DEST/views"

for f in manifest.json Service.qml BarWidget.qml Popup.qml Dashboard.qml timetrack.py; do
  cp -f "$SRC/$f" "$DEST/$f"
done
cp -f "$SRC"/components/*.qml "$DEST/components/"
cp -f "$SRC"/views/*.qml "$DEST/views/"
chmod +x "$DEST/timetrack.py"

# Best-effort rescan so a first-time install shows up in the registry.
omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true

cat <<EOF

Installed. Enable it (idempotent):

  omarchy plugin enable $PLUGIN_ID

The bar widget appears in the center section of the bar. The dashboard
window opens with:

  omarchy-shell shell toggle $PLUGIN_ID '{"tab":"timer"}'
EOF
