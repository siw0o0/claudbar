import QtQuick
import QtQuick.Layouts

// Rząd przycisków z jednym aktywnym trybem. Tryb to { arg, value, label }.
RowLayout {
    id: row
    property var modes: []
    property string current
    property bool busy: false
    property color accent
    property Theme theme: Theme {}
    signal picked(string arg, string label)
    Layout.fillWidth: true
    spacing: 6
    Repeater {
        model: row.modes
        delegate: Rectangle {
            required property var modelData
            readonly property bool active: row.current === modelData.value
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            implicitHeight: 30
            radius: 10
            color: active ? row.accent : row.theme.track
            opacity: row.busy ? 0.55 : 1
            Behavior on color { ColorAnimation { duration: 200 } }
            Text {
                anchors.centerIn: parent
                text: modelData.label
                color: active ? row.theme.onAccent : row.theme.ink
                font.pixelSize: 12; font.weight: Font.Medium
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                enabled: !row.busy && !active
                onClicked: row.picked(modelData.arg, modelData.label)
            }
        }
    }
}
