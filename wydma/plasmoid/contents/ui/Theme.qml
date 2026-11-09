import QtQuick

// Ciemna paleta z tapety: piasek, niebo, terakota, szałwia.
QtObject {
    readonly property color ink: "#f1e7da"
    readonly property color muted: "#bcab99"
    readonly property color faint: "#958676"
    readonly property color card: Qt.rgba(0.13, 0.105, 0.085, 0.86)
    readonly property color edge: Qt.rgba(1, 0.93, 0.84, 0.12)
    readonly property color track: Qt.rgba(1, 0.92, 0.82, 0.14)
    readonly property color sky: "#6eb0e6"
    readonly property color clay: "#e58d66"
    readonly property color sage: "#86bd8c"
    readonly property color dusk: "#ad98da"
    readonly property color gold: "#dcb15f"
    readonly property color teal: "#62b5af"
    readonly property color warn: "#eda24f"
    readonly property color alert: "#e8695d"
    readonly property color onAccent: "#20180f"
    function level(p, base) { return p >= 95 ? alert : p >= 80 ? warn : base; }
}
