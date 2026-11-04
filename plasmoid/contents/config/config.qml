import QtQuick
import org.kde.plasma.configuration
import "../ui/tr.js" as T

ConfigModel {
    ConfigCategory {
        name: T.tr("General")
        icon: "configure"
        source: "configGeneral.qml"
    }
}
