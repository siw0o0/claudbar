import QtQuick
import QtQuick.Layouts

// Wiersz z nazwą, opisem, procentem i paskiem. Stały element (nie delegat), żeby
// pasek płynnie zmieniał długość zamiast rosnąć od zera przy każdym odczycie.
ColumnLayout {
    id: row
    property string name
    property string detail
    property real value: 0
    property color color
    property int nameSize: 13
    property int barHeight: 6
    property Theme theme: Theme {}
    Layout.fillWidth: true
    spacing: 4

    RowLayout {
        Text { text: row.name; color: theme.ink; font.pixelSize: row.nameSize; font.weight: Font.Medium }
        Item { Layout.fillWidth: true }
        Text { text: row.detail; color: theme.faint; font.pixelSize: 12 }
        Text {
            text: Math.round(row.value) + "%"
            color: theme.level(row.value, theme.ink)
            font.pixelSize: row.nameSize; font.weight: Font.DemiBold
            font.features: { "tnum": 1 }
            Layout.leftMargin: 6
            Layout.minimumWidth: 34
            horizontalAlignment: Text.AlignRight
        }
    }
    Bar { Layout.fillWidth: true; implicitHeight: row.barHeight; value: row.value; color: theme.level(row.value, row.color); track: theme.track }
}
