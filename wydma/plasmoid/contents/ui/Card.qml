import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

Item {
    id: card
    property string title
    property string note
    property color accent: theme.sky
    default property alias content: body.data
    property Theme theme: Theme {}
    width: parent ? parent.width : 330
    implicitHeight: body.implicitHeight + 46
    height: implicitHeight

    Rectangle {
        id: bg
        anchors.fill: parent
        radius: 18
        color: theme.card
        border.color: theme.edge
        border.width: 1
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 0.4)
            shadowBlur: 0.7
            shadowVerticalOffset: 4
        }
    }
    RowLayout {
        id: head
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14; topMargin: 12 }
        Rectangle { width: 7; height: 7; radius: 4; color: card.accent }
        Text { text: card.title; color: theme.muted; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 1.4; font.capitalization: Font.AllUppercase }
        Item { Layout.fillWidth: true }
        Text { text: card.note; color: theme.faint; font.pixelSize: 11 }
    }
    ColumnLayout {
        id: body
        anchors { left: parent.left; right: parent.right; top: head.bottom; margins: 14; topMargin: 8 }
        spacing: 8
    }
}
