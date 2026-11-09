import QtQuick

Canvas {
    id: spark
    property var series: []
    property var colors: []
    implicitHeight: 46
    onSeriesChanged: requestPaint()
    onPaint: {
        var c = getContext("2d"); c.reset();
        var max = 1;
        for (var s = 0; s < series.length; ++s) for (var i = 0; i < series[s].length; ++i) max = Math.max(max, series[s][i]);
        for (s = 0; s < series.length; ++s) {
            var d = series[s]; if (d.length < 2) continue;
            var step = width / 39, x0 = width - (d.length - 1) * step;
            c.beginPath();
            for (i = 0; i < d.length; ++i) {
                var x = x0 + i * step, y = height - 2 - (height - 6) * d[i] / max;
                if (i === 0) c.moveTo(x, y); else c.lineTo(x, y);
            }
            c.strokeStyle = colors[s]; c.lineWidth = 2; c.lineJoin = "round"; c.stroke();
            c.lineTo(width, height); c.lineTo(x0, height); c.closePath();
            c.globalAlpha = 0.12; c.fillStyle = colors[s]; c.fill(); c.globalAlpha = 1;
        }
    }
}
