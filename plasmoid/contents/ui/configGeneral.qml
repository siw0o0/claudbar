import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import "tr.js" as T

// Settings of the bar on the panel (right-click the widget, Configure).
KCM.SimpleKCM {
    property alias cfg_width: width.value
    property alias cfg_compact: compact.checked
    property alias cfg_claudeStyle: claudeStyle.checked
    property alias cfg_autoCompact: autoCompact.checked
    property alias cfg_showCost: showCost.checked
    property alias cfg_notify: notify.checked

    Kirigami.FormLayout {
        QQC2.SpinBox {
            id: width
            Kirigami.FormData.label: T.tr("Width")
            from: 20; to: 80
            // The bar never gets narrower than its meters need, whatever is set here.
            QQC2.ToolTip.text: T.tr("Width of the bar on the panel, in grid units. It never goes below what the meters need.")
            QQC2.ToolTip.visible: hovered
        }
        QQC2.CheckBox {
            id: compact
            Kirigami.FormData.label: T.tr("Compact")
            text: T.tr("Percentages only, without the bars")
        }
        QQC2.CheckBox {
            id: autoCompact
            text: T.tr("Compact by itself on a small screen")
        }
        QQC2.CheckBox {
            id: showCost
            Kirigami.FormData.label: T.tr("Cost")
            text: T.tr("Show what the session would cost on the API")
        }
        QQC2.CheckBox {
            id: notify
            Kirigami.FormData.label: T.tr("Notifications")
            text: T.tr("Notify when a session waits for you or fails")
        }
        QQC2.CheckBox {
            id: claudeStyle
            Kirigami.FormData.label: T.tr("Look")
            text: T.tr("Claude style: warm colours and a spark per session")
        }
    }
}
