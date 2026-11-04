import QtQuick

// Session state dot. Only a permission request blinks, and in steps: every blink repaints
// the whole panel, and a smooth animation would do that at the display's refresh rate.
Rectangle {
    id: dot
    property string mode: "idle"
    property bool dim: false
    width: 9; height: 9; radius: 4.5
    color: mode === "waiting" ? "#e8913a" : mode === "working" ? "#5aa3e0" : "#6fb07a"
    opacity: dim ? 0.35 : 1
    Timer {
        interval: 700
        repeat: true
        running: dot.visible && dot.mode === "waiting"
        onTriggered: dot.dim = !dot.dim
        onRunningChanged: if (!running) dot.dim = false
    }
}
