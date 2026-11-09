import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5Support
import org.kde.ksysguard.sensors as Sensors

PlasmoidItem {
    id: root
    // Identyfikator karty w czujnikach systemu (gpu/gpu0, gpu/gpu1…): w Monitorze systemu widać, który to.
    readonly property string gpu: "gpu/gpu2"
    readonly property var pl: Qt.locale("pl_PL")
    property var now: new Date()
    property var status: ({})
    property var down: []
    property var up: []

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    preferredRepresentation: fullRepresentation

    Theme { id: theme }

    function ok(s) { return s.status === Sensors.Sensor.Ready && s.value !== undefined && Number.isFinite(Number(s.value)); }
    // Ostatni poprawny odczyt na czujnik: chwilowy brak danych nie zrzuca paska do zera.
    property var last: ({})
    function num(s) {
        if (ok(s)) last[s.sensorId] = Number(s.value);
        return last[s.sensorId] || 0;
    }
    function txt(s) { return ok(s) ? s.formattedValue : "—"; }
    function pct(v) { return Math.round(v) + "%"; }
    function gib(bytes) { return (bytes / 1073741824).toLocaleString(pl, "f", 1); }
    function span(ms) {
        var m = Math.max(0, Math.round(ms / 60000));
        if (m < 60) return m + " min";
        if (m < 1440) return Math.floor(m / 60) + " h " + (m % 60) + " min";
        return Math.floor(m / 1440) + " d " + Math.floor((m % 1440) / 60) + " h";
    }
    function limitName(kind) { return ({ five_hour: "Sesja 5 h", seven_day: "Tydzień" })[kind] || kind.replace(/_/g, " "); }
    function profileName(p) { return ({ performance: "Wydajność", balanced: "Zrównoważony", "power-saver": "Oszczędzanie" })[p] || "—"; }

    Sensors.Sensor { id: cpu; sensorId: "cpu/all/usage"; updateRateLimit: 1000 }
    Sensors.Sensor { id: cpuTemp; sensorId: "cpu/all/averageTemperature"; updateRateLimit: 2000 }
    // Odczyt NVIDII idzie przez nvidia-smi, który nie pozwala karcie zasnąć, więc tylko na zasilaczu.
    readonly property bool gpuLive: status.ac === 1
    function gpuNum(s) { return gpuLive ? num(s) : 0; }
    function gpuTxt(s) { return gpuLive ? txt(s) : "—"; }
    Sensors.Sensor { id: gpuUse; sensorId: root.gpu + "/usage"; updateRateLimit: 2000; enabled: root.gpuLive }
    Sensors.Sensor { id: gpuTemp; sensorId: root.gpu + "/temperature"; updateRateLimit: 2000; enabled: root.gpuLive }
    Sensors.Sensor { id: vramUsed; sensorId: root.gpu + "/usedVram"; updateRateLimit: 2000; enabled: root.gpuLive }
    Sensors.Sensor { id: vramTotal; sensorId: root.gpu + "/totalVram"; enabled: root.gpuLive }
    Sensors.Sensor { id: gpuName; sensorId: root.gpu + "/name"; enabled: root.gpuLive }
    // Nazwa karty zostaje po przejściu na baterię, kiedy odczyt jest wyłączony.
    property string gpuTitle: ""
    readonly property string gpuSeen: gpuLive && gpuName.status === Sensors.Sensor.Ready && gpuName.value ? String(gpuName.value).replace(/^(NVIDIA|AMD|Intel)\s+(GeForce\s+)?/i, "") : ""
    onGpuSeenChanged: if (gpuSeen) gpuTitle = gpuSeen
    Sensors.Sensor { id: ram; sensorId: "memory/physical/usedPercent"; updateRateLimit: 1000 }
    Sensors.Sensor { id: ramUsed; sensorId: "memory/physical/used"; updateRateLimit: 1000 }
    Sensors.Sensor { id: ramTotal; sensorId: "memory/physical/total" }
    Sensors.Sensor { id: disk; sensorId: "disk/all/usedPercent"; updateRateLimit: 10000 }
    Sensors.Sensor { id: diskFree; sensorId: "disk/all/free"; updateRateLimit: 10000 }
    Sensors.Sensor { id: netDown; sensorId: "network/all/download"; updateRateLimit: 1000 }
    Sensors.Sensor { id: netUp; sensorId: "network/all/upload"; updateRateLimit: 1000 }

    Timer {
        interval: 1000; repeat: true; running: true; triggeredOnStart: true
        onTriggered: {
            root.now = new Date();
            root.down = root.down.concat([root.num(netDown)]).slice(-40);
            root.up = root.up.concat([root.num(netUp)]).slice(-40);
        }
    }

    // Przełącznik VPN: ~/.local/bin/protonvpn-auto on/off, potem szybkie odświeżenie stanu.
    property bool vpnBusy: false
    readonly property string vpnCmd: "sh -c \"$HOME/.local/bin/protonvpn-auto "
    function toggleVpn(on) {
        vpnBusy = true;
        vpnPick = "";
        vpnFailed = "";
        vpnExec.connectSource(vpnCmd + (on ? "on" : "off") + "\"");
    }
    // Lista wyboru: Proton plus profile z NetworkManagera. Łączenie może czekać na okno logowania.
    readonly property string protonName: "Proton VPN"
    readonly property string vpnNow: !status.vpn ? "" : status.vpn.indexOf("ProtonVPN") === 0 ? protonName : status.vpn
    property string vpnPick
    property string vpnFailed
    function pickVpn(name) {
        vpnBusy = true;
        vpnPick = name;
        vpnFailed = "";
        vpnExec.connectSource("\"$HOME/.local/bin/protonvpn-auto\" select '" + name.replace(/'/g, "'\\''") + "'");
    }
    P5Support.DataSource {
        id: vpnExec
        engine: "executable"
        onNewData: (source, data) => {
            disconnectSource(source);
            root.vpnBusy = false;
            if (root.vpnPick && data["exit code"] !== 0) root.vpnFailed = root.vpnPick;
            root.vpnPick = "";
            exec.connectSource(root.statusCmd);
        }
    }

    // Tryb ładowania: /usr/local/sbin/battery-mode przez sudo bez hasła, potem szybkie odświeżenie stanu.
    property bool chargeBusy: false
    property bool chargeFailed: false
    readonly property var chargeModes: [
        { arg: "long", value: "Long_Life", label: "Ochrona", hint: "ładowanie zatrzymuje się w okolicach 80%" },
        { arg: "standard", value: "Standard", label: "Standard", hint: "ładowanie do 100%" },
        { arg: "fast", value: "Fast", label: "Szybkie", hint: "szybko do 100%, mocniej grzeje baterię" }
    ]
    property string chargePick
    property string chargeDone
    function setCharge(arg, label) {
        chargeBusy = true;
        chargeFailed = false;
        chargeDone = "";
        chargePick = label;
        chargeExec.connectSource("sudo -n /usr/local/sbin/battery-mode " + arg);
    }
    // Skrypt odczytuje tryb z powrotem, więc kod 0 oznacza potwierdzoną zmianę.
    P5Support.DataSource {
        id: chargeExec
        engine: "executable"
        onNewData: (source, data) => {
            disconnectSource(source);
            root.chargeBusy = false;
            root.chargeFailed = data["exit code"] !== 0;
            if (!root.chargeFailed) { root.chargeDone = root.chargePick; chargeDoneTimer.restart(); }
            exec.connectSource(root.statusCmd);
        }
    }
    Timer { id: chargeDoneTimer; interval: 6000; onTriggered: root.chargeDone = "" }

    // Tryb grafiki: zapis w firmware przez /usr/local/sbin/gpu-mode, działa dopiero po restarcie.
    property bool gpuBusy: false
    property bool gpuFailed: false
    readonly property var gpuModes: [
        { arg: "hybrid", value: "hybrid", label: "Hybrid", hint: "ekran na Intelu, NVIDIA włącza się w razie potrzeby" },
        { arg: "igpu", value: "igpu", label: "iGPU", hint: "tylko Intel, monitor zewnętrzny może nie działać" },
        { arg: "dgpu", value: "dgpu", label: "dGPU", hint: "wszystko na NVIDII, G-Sync, większy pobór prądu" }
    ]
    function gpuLabel(v) { var m = gpuModes.find(x => x.value === v); return m ? m.label : "—"; }
    function setGpu(arg) {
        gpuBusy = true;
        gpuFailed = false;
        gpuExec.connectSource("sudo -n /usr/local/sbin/gpu-mode " + arg);
    }
    P5Support.DataSource {
        id: gpuExec
        engine: "executable"
        onNewData: (source, data) => {
            disconnectSource(source);
            root.gpuBusy = false;
            root.gpuFailed = data["exit code"] !== 0;
            exec.connectSource(root.statusCmd);
        }
    }

    // Limity Claude, profil zasilania, VPN i słuchawki z jednego skryptu co 10 s.
    readonly property string statusCmd: "sh '" + Qt.resolvedUrl("../code/status.sh").toString().replace("file://", "") + "'"
    P5Support.DataSource {
        id: exec
        engine: "executable"
        onNewData: (source, data) => {
            try {
                var next = JSON.parse(data["stdout"]);
                // Lista VPN-ów przychodzi tylko w pełnym odczycie; między nimi zostaje poprzednia.
                if (next.vpns === null) next.vpns = root.status.vpns || [];
                root.status = next;
            } catch (e) {}
            disconnectSource(source);
        }
    }
    // Co 10 s lekki odczyt, raz na minutę pełny (z listą profili VPN).
    property int ticks: 0
    Timer {
        interval: 10000; repeat: true; running: true; triggeredOnStart: true
        onTriggered: exec.connectSource(root.statusCmd + (root.ticks++ % 6 === 0 ? " full" : ""))
    }

    // Najbliższe zajęcia co minutę. Plan podaje własny program ~/.config/wydma/plan (jedna linia JSON:
    // { pobrano, zajecia: [{ przedmiot, forma, start, koniec, sala, budynek, uwaga }] }); bez niego
    // kafelka nie ma. Kliknięcie uruchamia ~/.config/wydma/plan-open.
    property var plan: null
    readonly property string planCmd: "sh -c 'p=\"$HOME/.config/wydma/plan\"; [ -x \"$p\" ] && \"$p\" || echo null'"
    P5Support.DataSource {
        id: planExec
        engine: "executable"
        onNewData: (source, data) => {
            try { root.plan = JSON.parse(data["stdout"]); } catch (e) {}
            disconnectSource(source);
        }
    }
    Timer { interval: 60000; repeat: true; running: true; triggeredOnStart: true; onTriggered: planExec.connectSource(root.planCmd) }

    P5Support.DataSource {
        id: launcher
        engine: "executable"
        onNewData: (source, data) => disconnectSource(source)
    }
    function openPlan() {
        launcher.connectSource("sh -c 'p=\"$HOME/.config/wydma/plan-open\"; [ -x \"$p\" ] && setsid -f \"$p\" >/dev/null 2>&1'");
    }

    function formName(f) { return ({ W: "wykład", L: "laboratorium", C: "ćwiczenia", P: "projekt", S: "seminarium" })[f] || f; }
    function hm(iso) { return Qt.formatTime(new Date(Date.parse(iso)), "HH:mm"); }
    // „dziś”, „jutro” albo skrót dnia tygodnia z datą.
    function dayName(iso) {
        var day = new Date(Date.parse(iso)), today = new Date(root.now);
        day.setHours(0, 0, 0, 0);
        today.setHours(0, 0, 0, 0);
        var diff = Math.round((day - today) / 86400000);
        if (diff === 0) return "dziś";
        if (diff === 1) return "jutro";
        return new Date(Date.parse(iso)).toLocaleDateString(root.pl, "ddd d.MM");
    }

    fullRepresentation: Item {
        id: rep
        // Gdy panel jest wyższy niż miejsce na ekranie, zmniejsza się w całości zamiast wystawać poza dół.
        readonly property real fit: height > 0 && stack.implicitHeight > height ? height / stack.implicitHeight : 1
        Layout.preferredWidth: 330
        Layout.minimumWidth: 300
        Layout.preferredHeight: stack.implicitHeight

    Column {
        id: stack
        width: parent.width
        scale: rep.fit
        transformOrigin: Item.TopRight
        spacing: 12

        // Zegar
        Item {
            width: parent.width
            implicitHeight: clockCol.implicitHeight + 8
            ColumnLayout {
                id: clockCol
                anchors { right: parent.right; rightMargin: 6 }
                spacing: -4
                Text {
                    Layout.alignment: Qt.AlignRight
                    text: Qt.formatTime(root.now, "HH:mm")
                    color: "white"; font.pixelSize: 64; font.weight: Font.Light
                    style: Text.Raised; styleColor: Qt.rgba(0.25, 0.15, 0.05, 0.25)
                }
                Text {
                    Layout.alignment: Qt.AlignRight
                    text: root.now.toLocaleDateString(root.pl, "dddd, d MMMM")
                    color: "white"; font.pixelSize: 16; font.weight: Font.Medium
                    style: Text.Raised; styleColor: Qt.rgba(0.25, 0.15, 0.05, 0.3)
                }
            }
        }

        // Najbliższe zajęcia
        Card {
            id: classCard
            visible: root.plan !== null
            title: "Zajęcia"
            accent: theme.teal
            readonly property var list: root.plan && root.plan.zajecia ? root.plan.zajecia.filter(z => Date.parse(z.koniec) > root.now) : []
            readonly property var cur: list.length ? list[0] : null
            readonly property real startMs: cur ? Date.parse(cur.start) : 0
            readonly property real endMs: cur ? Date.parse(cur.koniec) : 0
            readonly property bool live: cur !== null && startMs <= root.now
            note: !cur ? "" : live ? "trwa, jeszcze " + root.span(endMs - root.now)
                : startMs - root.now < 12 * 3600000 ? "za " + root.span(startMs - root.now)
                : root.dayName(cur.start)

            // Kliknięcie w kafelek otwiera aplikację z planem.
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.openPlan() }

            RowLayout {
                Layout.fillWidth: true
                visible: classCard.cur !== null
                spacing: 12
                Rectangle {
                    Layout.alignment: Qt.AlignTop
                    implicitWidth: 34; implicitHeight: 34; radius: 10
                    color: Qt.rgba(0.23, 0.56, 0.54, 0.14)
                    Text { anchors.centerIn: parent; text: classCard.cur ? classCard.cur.forma : ""; color: theme.teal; font.pixelSize: 15; font.weight: Font.DemiBold }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        Layout.fillWidth: true
                        text: classCard.cur ? classCard.cur.przedmiot : ""
                        color: theme.ink; font.pixelSize: 15; font.weight: Font.Medium
                        wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: classCard.cur ? root.dayName(classCard.cur.start) + " " + root.hm(classCard.cur.start) + "–" + root.hm(classCard.cur.koniec) + " · " + root.formName(classCard.cur.forma) : ""
                        color: theme.muted; font.pixelSize: 12
                    }
                    Text {
                        Layout.fillWidth: true
                        text: classCard.cur ? "sala " + classCard.cur.sala + " · " + classCard.cur.budynek + (classCard.cur.uwaga ? " · " + classCard.cur.uwaga : "") : ""
                        color: theme.faint; font.pixelSize: 12; elide: Text.ElideRight
                    }
                }
            }
            Bar {
                Layout.fillWidth: true
                visible: classCard.live
                implicitHeight: 6
                value: classCard.live ? 100 * (root.now - classCard.startMs) / (classCard.endMs - classCard.startMs) : 0
                color: theme.teal; track: theme.track
            }
            // Kolejne dwa zajęcia
            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: theme.track; visible: classCard.list.length > 1 }
            Repeater {
                model: Math.min(2, Math.max(0, classCard.list.length - 1))
                delegate: RowLayout {
                    required property int index
                    readonly property var cls: classCard.list[index + 1] || null
                    Layout.fillWidth: true
                    spacing: 8
                    Text {
                        text: cls ? root.dayName(cls.start) + " " + root.hm(cls.start) : ""
                        color: theme.muted; font.pixelSize: 12; font.features: { "tnum": 1 }
                        Layout.preferredWidth: 88
                    }
                    Text { text: cls ? cls.przedmiot + " (" + cls.forma + ")" : ""; color: theme.ink; font.pixelSize: 12; elide: Text.ElideRight; Layout.fillWidth: true }
                    Text { text: cls ? cls.sala : ""; color: theme.faint; font.pixelSize: 12 }
                }
            }
            Text {
                visible: !classCard.cur
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: "Brak zaplanowanych zajęć."
                color: theme.muted; font.pixelSize: 12
            }
            Text {
                visible: !!root.plan && root.now - Date.parse(root.plan.pobrano) > 3 * 86400000
                Layout.fillWidth: true
                text: root.plan ? "plan z " + new Date(Date.parse(root.plan.pobrano)).toLocaleDateString(root.pl, "d.MM") + ", do odświeżenia" : ""
                color: theme.warn; font.pixelSize: 11
            }
        }

        // Limity Claude
        Card {
            id: claudeCard
            title: "Limity Claude"
            accent: theme.clay
            readonly property var usage: root.status.usage || null
            note: usage ? "odczyt " + root.span(root.now - usage.at) + " temu" : ""
            Repeater {
                model: claudeCard.usage ? claudeCard.usage.limits.length : 0
                delegate: MeterRow {
                    required property int index
                    readonly property var lim: claudeCard.usage ? claudeCard.usage.limits[index] : null
                    name: lim ? root.limitName(lim.kind) : ""
                    detail: lim && lim.resetsAt ? "reset za " + root.span(Date.parse(lim.resetsAt) - root.now) : ""
                    value: lim ? lim.percent : 0
                    color: theme.clay
                    nameSize: 14
                    barHeight: 8
                }
            }
            Text {
                visible: !claudeCard.usage
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: "Brak odczytu. Pojawi się po pierwszej odpowiedzi Claude."
                color: theme.muted; font.pixelSize: 12
            }
        }

        // CPU i GPU
        Card {
            title: "Procesor i grafika"
            accent: theme.sky
            note: root.gpuLive ? root.gpuTitle : (root.gpuTitle ? root.gpuTitle + ", " : "") + "odczyt na zasilaczu"
            RowLayout {
                Layout.fillWidth: true
                Gauge { name: "CPU"; value: root.num(cpu); temp: root.num(cpuTemp); tempText: root.txt(cpuTemp); color: theme.sky }
                Gauge { name: "GPU"; value: root.gpuNum(gpuUse); temp: root.gpuNum(gpuTemp); tempText: root.gpuTxt(gpuTemp); color: theme.sage }
            }
        }

        // Pamięć i dysk
        Card {
            title: "Pamięć"
            accent: theme.dusk
            MeterRow { name: "RAM"; value: root.num(ram); detail: root.gib(root.num(ramUsed)) + " / " + root.gib(root.num(ramTotal)) + " GiB"; color: theme.dusk }
            MeterRow { name: "VRAM"; value: root.gpuNum(vramTotal) > 0 ? 100 * root.gpuNum(vramUsed) / root.gpuNum(vramTotal) : 0; detail: root.gpuLive ? root.txt(vramUsed) + " / " + root.txt(vramTotal) : "—"; color: theme.sage }
            MeterRow { name: "Dysk"; value: root.num(disk); detail: "wolne " + root.txt(diskFree); color: theme.gold }
        }

        // Sieć
        Card {
            id: netCard
            title: "Sieć"
            accent: theme.sky
            RowLayout {
                Layout.fillWidth: true
                Text { text: "↓ " + root.txt(netDown); color: theme.sky; font.pixelSize: 15; font.weight: Font.Medium }
                Item { Layout.fillWidth: true }
                Text { text: "↑ " + root.txt(netUp); color: theme.clay; font.pixelSize: 15; font.weight: Font.Medium }
            }
            Spark { Layout.fillWidth: true; series: [root.down, root.up]; colors: [theme.sky, theme.clay] }
        }

        // Zasilanie
        Card {
            id: powerCard
            title: "Zasilanie"
            accent: theme.gold
            readonly property real bat: root.status.bat || 0
            readonly property bool ac: root.status.ac === 1
            note: root.profileName(root.status.profile)
            RowLayout {
                Layout.fillWidth: true
                Text { text: powerCard.ac ? "🔌 Zasilacz" : "🔋 Bateria"; color: theme.ink; font.pixelSize: 13; font.weight: Font.Medium }
                Item { Layout.fillWidth: true }
                Text { text: root.pct(powerCard.bat); color: theme.level(100 - powerCard.bat, theme.ink); font.pixelSize: 13; font.weight: Font.DemiBold }
            }
            Bar { Layout.fillWidth: true; implicitHeight: 6; value: powerCard.bat; color: powerCard.bat <= 15 ? theme.alert : powerCard.bat <= 30 ? theme.warn : theme.sage; track: theme.track }
            // Tryb ładowania
            ModeRow {
                visible: root.status.hasCharge === 1
                modes: root.chargeModes
                current: root.status.charge || ""
                busy: root.chargeBusy
                accent: theme.gold
                onPicked: (arg, label) => root.setCharge(arg, label)
            }
            Text {
                Layout.fillWidth: true
                visible: root.status.hasCharge === 1
                wrapMode: Text.WordWrap
                readonly property var mode: root.chargeModes.find(m => m.value === root.status.charge)
                text: root.chargeFailed ? "⚠ Nie udało się zmienić trybu ładowania."
                    : root.chargeDone ? "✓ Włączono: " + root.chargeDone
                    : mode ? mode.hint : ""
                color: root.chargeFailed ? theme.alert : root.chargeDone ? theme.sage : theme.faint
                font.pixelSize: 11
            }
            RowLayout {
                Layout.fillWidth: true
                visible: root.status.headsetPct !== undefined && root.status.headsetPct !== null
                Text { text: "🎧 " + (root.status.headset || "Słuchawki"); color: theme.ink; font.pixelSize: 13; elide: Text.ElideRight; Layout.fillWidth: true }
                Text { text: root.pct(root.status.headsetPct || 0); color: theme.level(100 - (root.status.headsetPct || 0), theme.ink); font.pixelSize: 13; font.weight: Font.DemiBold }
            }
        }

        // Tryb grafiki
        Card {
            id: gpuCard
            visible: root.status.hasGpu === 1
            title: "Tryb grafiki"
            accent: theme.sage
            readonly property string set: root.status.gpuSet || ""
            readonly property string active: root.status.gpuNow || ""
            readonly property bool pending: set !== "" && active !== "" && set !== active
            readonly property var mode: root.gpuModes.find(m => m.value === set)
            note: "teraz: " + root.gpuLabel(active)
            ModeRow {
                modes: root.gpuModes
                current: gpuCard.set
                busy: root.gpuBusy
                accent: theme.sage
                onPicked: (arg, label) => root.setGpu(arg)
            }
            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                readonly property string missed: root.status.gpuFail || ""
                text: root.gpuFailed ? "⚠ Nie udało się zapisać trybu grafiki."
                    : gpuCard.pending ? "✓ Zapisano: " + root.gpuLabel(gpuCard.set) + ". Zadziała po restarcie."
                    : missed ? "⚠ Po restarcie nadal " + root.gpuLabel(gpuCard.active) + ", firmware nie włączył " + root.gpuLabel(missed) + "."
                    : gpuCard.mode ? "✓ Aktywny: " + gpuCard.mode.label + ", " + gpuCard.mode.hint : ""
                color: root.gpuFailed || missed ? theme.alert : gpuCard.pending ? theme.warn : theme.faint
                font.pixelSize: 11
            }
        }

        // VPN
        Card {
            id: vpnCard
            title: "VPN"
            readonly property bool on: !!root.status.vpn
            readonly property bool blocking: root.status.ks === 1 && !on
            accent: blocking ? theme.alert : on ? theme.sage : theme.faint
            readonly property bool proton: root.vpnNow === root.protonName
            note: root.vpnBusy ? (on && !root.vpnPick ? "rozłączanie…" : "łączenie…") : on ? root.status.vpn.replace("ProtonVPN ", "") : root.status.eduroam === 1 ? "eduroam: wyłączony" : root.status.manualOff === 1 ? "wyłączony ręcznie" : "wyłączony"

            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Text {
                    text: vpnCard.on ? "🛡" : "○"
                    color: vpnCard.on ? theme.sage : theme.faint
                    font.pixelSize: 22
                }
                Column {
                    Layout.fillWidth: true
                    Text { text: !vpnCard.on ? "Bez VPN-a" : vpnCard.proton ? "Chroniony" : "Połączono"; color: theme.ink; font.pixelSize: 15; font.weight: Font.Medium }
                    Text {
                        text: !vpnCard.on ? "wraca sam po zmianie sieci" : vpnCard.proton ? "ruch idzie szyfrowanym tunelem" : "po zmianie sieci wraca Proton"
                        color: theme.faint; font.pixelSize: 11
                    }
                }
                // Przełącznik
                Rectangle {
                    id: toggle
                    visible: root.status.hasVpn === 1
                    width: 52; height: 30; radius: 15
                    color: vpnCard.on ? theme.sage : theme.track
                    opacity: root.vpnBusy ? 0.55 : 1
                    Behavior on color { ColorAnimation { duration: 200 } }
                    Rectangle {
                        width: 24; height: 24; radius: 12
                        y: 3; x: vpnCard.on ? parent.width - width - 3 : 3
                        color: "white"
                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        enabled: !root.vpnBusy
                        onClicked: root.toggleVpn(!vpnCard.on)
                    }
                }
            }
            // Lista wyboru VPN-a
            Repeater {
                model: root.status.hasVpn === 1 ? [root.protonName].concat(root.status.vpns || []) : []
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool active: root.vpnNow === modelData
                    readonly property bool picking: root.vpnPick === modelData
                    Layout.fillWidth: true
                    implicitHeight: 30
                    radius: 10
                    color: active ? Qt.rgba(0.48, 0.60, 0.42, 0.28) : theme.track
                    opacity: root.vpnBusy && !picking ? 0.55 : 1
                    Behavior on color { ColorAnimation { duration: 200 } }
                    RowLayout {
                        anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                        spacing: 8
                        Text { text: modelData; color: theme.ink; font.pixelSize: 12; font.weight: active ? Font.DemiBold : Font.Normal; elide: Text.ElideRight; Layout.fillWidth: true }
                        Text { text: picking ? "łączenie…" : active ? "✓ połączono" : ""; color: active ? theme.sage : theme.faint; font.pixelSize: 11 }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        enabled: !root.vpnBusy && !active
                        onClicked: root.pickVpn(modelData)
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                visible: root.vpnFailed !== ""
                wrapMode: Text.WordWrap
                text: "⚠ Nie udało się połączyć z " + root.vpnFailed + "."
                color: theme.alert; font.pixelSize: 11
            }
            // Ostrzeżenie o kill switchu
            Rectangle {
                Layout.fillWidth: true
                visible: root.status.ks === 1
                implicitHeight: ksText.implicitHeight + 14
                radius: 10
                color: vpnCard.blocking ? Qt.rgba(0.76, 0.27, 0.23, 0.14) : Qt.rgba(0.85, 0.51, 0.17, 0.13)
                Text {
                    id: ksText
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 10; rightMargin: 10 }
                    wrapMode: Text.WordWrap
                    font.pixelSize: 12
                    color: vpnCard.blocking ? theme.alert : theme.warn
                    text: vpnCard.blocking
                        ? "⚠ Kill switch blokuje internet. Włącz VPN, żeby odzyskać połączenie."
                        : "⚠ Kill switch aktywny: jeśli VPN się zerwie, internet zostanie zablokowany."
                }
            }
        }

    }
    }
}
