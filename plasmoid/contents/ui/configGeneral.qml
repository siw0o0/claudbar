import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import "tr.js" as T

// Settings of the bar on the panel (right-click the widget, Configure).
KCM.SimpleKCM {
    property alias cfg_width: width.value
    property alias cfg_compact: compact.checked

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
    }
}
