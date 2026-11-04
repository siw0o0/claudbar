#!/bin/sh
# Installs (or upgrades) the Claudbar Plasma widget for the current user.
# Usage: ./install.sh          install or upgrade
#        ./install.sh remove   uninstall the widget
set -eu

here=$(cd "$(dirname "$0")" && pwd)

if ! command -v kpackagetool6 >/dev/null 2>&1; then
    echo "kpackagetool6 not found: Claudbar needs KDE Plasma 6." >&2
    exit 1
fi

if [ "${1:-}" = "remove" ]; then
    kpackagetool6 -t Plasma/Applet -r claudbar
    echo "Widget removed. Remove the mod in Claude Code with: /plugin uninstall claudbar"
    exit 0
fi

if kpackagetool6 -t Plasma/Applet -s claudbar >/dev/null 2>&1; then
    kpackagetool6 -t Plasma/Applet -u "$here/plasmoid"
else
    kpackagetool6 -t Plasma/Applet -i "$here/plasmoid"
fi

cat <<'EOF'

Widget installed. Next:
  1. Right-click your panel > Add Widgets… > search "Claudbar" > drag it onto the panel.
     (After an upgrade, restart Plasma to load the new version: kquitapp6 plasmashell && kstart plasmashell)
  2. Install the Claude Code mod that feeds it (see README, "Install").
EOF
