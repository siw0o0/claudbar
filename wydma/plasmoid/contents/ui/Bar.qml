import QtQuick

Item {
    id: bar
    property real value: 0
    property color color: "#3d86c6"
    property color track: Qt.rgba(0.48, 0.38, 0.28, 0.13)
    implicitHeight: 8
    Rectangle { anchors.fill: parent; radius: height / 2; color: bar.track }
    Rectangle {
        height: parent.height; radius: height / 2; color: bar.color
        width: Math.max(height, parent.width * Math.max(0, Math.min(100, bar.value)) / 100)
        visible: bar.value > 0
        Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
    }
}
