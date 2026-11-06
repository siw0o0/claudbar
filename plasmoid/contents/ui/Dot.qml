import QtQuick

// Session state mark: a dot, or in the Claude style a spark. Only a permission request blinks,
// and in steps: every blink repaints the whole panel, and a smooth animation would do that at
// the display's refresh rate. For the same reason a working spark turns in steps.
Item {
    id: dot
    property string mode: "idle"
    property bool spark: false
    property bool spin: false
    property real size: 9
    property bool dim: false
    width: size; height: size
    readonly property color tint: spark
        ? (mode === "waiting" ? "#e8a33d" : mode === "working" ? "#d97757" : "#8fae7e")
        : (mode === "waiting" ? "#e8913a" : mode === "working" ? "#5aa3e0" : "#6fb07a")
    opacity: dim ? 0.35 : 1

    Rectangle { anchors.fill: parent; radius: width / 2; color: dot.tint; visible: !dot.spark }
    Item {
        id: rays
        anchors.fill: parent
        visible: dot.spark
        Repeater {
            model: 8
            Rectangle {
                required property int index
                readonly property real len: dot.size / 2 * (index % 2 ? 0.62 : 1)
                width: Math.max(1.5, dot.size / 7); height: len
                radius: width / 2
                color: dot.tint
                x: (dot.size - width) / 2; y: dot.size / 2 - len
                transform: Rotation { origin.x: width / 2; origin.y: len; angle: index * 45 }
            }
        }
    }
    Timer {
        interval: 700
        repeat: true
        running: dot.visible && dot.mode === "waiting"
        onTriggered: dot.dim = !dot.dim
        onRunningChanged: if (!running) dot.dim = false
    }
    Timer {
        interval: 1200
        repeat: true
        running: dot.visible && dot.spark && dot.spin && dot.mode === "working"
        onTriggered: rays.rotation = (rays.rotation + 22.5) % 360
    }
}
