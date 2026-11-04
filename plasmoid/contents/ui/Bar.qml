import QtQuick

Item {
    id: bar
    property real value: 0
    property color color: "#5aa3e0"
    property color track: Qt.rgba(1, 1, 1, 0.14)
    implicitHeight: 6
    Rectangle { anchors.fill: parent; radius: height / 2; color: bar.track }
    Rectangle {
        height: parent.height; radius: height / 2; color: bar.color
        width: Math.max(height, parent.width * Math.max(0, Math.min(100, bar.value)) / 100)
        visible: bar.value > 0
    }
}
