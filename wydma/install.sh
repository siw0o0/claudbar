#!/bin/sh
# Installs (or upgrades) the Wydma desktop widget for the current user.
# Usage: ./install.sh          install or upgrade
#        ./install.sh remove   uninstall the widget
set -eu

here=$(cd "$(dirname "$0")" && pwd)

if ! command -v kpackagetool6 >/dev/null 2>&1; then
    echo "kpackagetool6 not found: Wydma needs KDE Plasma 6." >&2
    exit 1
fi

if [ "${1:-}" = "remove" ]; then
    kpackagetool6 -t Plasma/Applet -r wydma
    exit 0
fi

if kpackagetool6 -t Plasma/Applet -s wydma >/dev/null 2>&1; then
    kpackagetool6 -t Plasma/Applet -u "$here/plasmoid"
else
    kpackagetool6 -t Plasma/Applet -i "$here/plasmoid"
fi

cat <<'EOT'

Widget installed. Right-click the desktop > Enter Edit Mode > Add Widgets… > search "Wydma".
(After an upgrade, restart Plasma to load the new version: kquitapp6 plasmashell && kstart plasmashell)
EOT
