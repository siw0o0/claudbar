import QtQuick
import QtQuick.Layouts

Item {
    id: gauge
    property string name
    property real value: 0
    property real temp: 0
    property string tempText
    property color color
    property Theme theme: Theme {}
    Layout.fillWidth: true
    implicitHeight: 128

    Ring {
        id: ring
        anchors.horizontalCenter: parent.horizontalCenter
        width: 104; height: 104
        value: gauge.value; color: gauge.color; track: theme.track
    }
    Column {
        anchors.centerIn: ring
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: Math.round(gauge.value) + "%"; color: theme.ink; font.pixelSize: 24; font.weight: Font.Light; font.features: { "tnum": 1 } }
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: gauge.name; color: theme.muted; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 1.2 }
    }
    Text {
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
        text: "🌡 " + gauge.tempText
        color: gauge.temp >= 85 ? theme.alert : gauge.temp >= 70 ? theme.warn : theme.muted
        font.pixelSize: 12
    }
}
