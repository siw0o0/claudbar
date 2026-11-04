import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami
import org.kde.plasma.workspace.dbus as DBus
import org.kde.taskmanager as TaskManager
import QtCore
import Qt.labs.folderlistmodel
import "tr.js" as T

PlasmoidItem {
    id: root
    // No process polling: Claude is detected by its tray icon (D-Bus), and the state files the
    // claudbar mod writes are read only when their modification times change.
    readonly property string home: StandardPaths.writableLocation(StandardPaths.HomeLocation).toString().replace("file://", "")
    readonly property string dir: home + "/.cache/claudbar"
    property string trayService: ""
    property var files: []
    property var usage: null
    property real now: Date.now()
    readonly property var alive: files.filter(s => s.state !== "ended" && now - s.at < 86400000)
    // Terminal sessions have no tray icon: working or waiting is enough for them.
    readonly property bool running: tray.registered || alive.some(s => s.state !== "idle" && now - s.at < 600000)
    readonly property var order: ({ waiting: 0, working: 1, idle: 2 })
    readonly property var sessions: running ? alive.slice().sort((a, b) => (order[a.state] - order[b.state]) || (b.at - a.at)) : []
    // A session pinned in the list; otherwise the most urgent one (waiting, work, latest).
    property string picked: ""
    readonly property var lead: sessions.find(s => s.id === picked) || (sessions.length ? sessions[0] : null)
    // Dots: working and waiting always, finished ones for 5 minutes, the latest finished one stays.
    readonly property var lastDone: sessions.reduce((best, s) => s.state === "idle" && (!best || s.since > best.since) ? s : best, null)
    readonly property var shown: sessions.filter(s => s.state !== "idle" || now - s.since < 300000 || s === lastDone || s === lead)
    // Popup list: active in the last 10 minutes, but never fewer than 3 (filled with the most recent).
    readonly property var listed: {
        var recent = sessions.filter(s => now - s.at < 600000);
        if (recent.length >= 3) return recent;
        var fill = sessions.filter(s => recent.indexOf(s) < 0).sort((a, b) => b.at - a.at).slice(0, 3 - recent.length);
        return sessions.filter(s => recent.indexOf(s) >= 0 || fill.indexOf(s) >= 0);
    }
    function pick(id) { picked = picked === id ? "" : id; }
    readonly property var limits: usage ? usage.limits : []
    readonly property real cost: sessions.reduce((sum, s) => sum + (s.cost || 0), 0)

    // Shown name: a custom one from the popup, else the first meaningful word of the conversation title, else the project.
    readonly property var names: { try { return JSON.parse(Plasmoid.configuration.names); } catch (e) { return {}; } }
    function titleWord(t) {
        var words = (t || "").split(/\s+/).map(w => w.replace(/^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$/gu, "")).filter(w => w);
        var w = words.find(w => w.length >= 4) || words[0] || "";
        return w.charAt(0).toUpperCase() + w.slice(1);
    }
    function nameOf(s) { return names[s.id] || titleWord(s.title) || s.project; }
    function rename(id, text) {
        var map = Object.assign({}, names);
        var t = text.trim();
        if (t) map[id] = t; else delete map[id];
        Plasmoid.configuration.names = JSON.stringify(map);
    }

    readonly property color sky: "#5aa3e0"
    readonly property color sage: "#6fb07a"
    readonly property color dusk: "#a08ad0"
    readonly property color warn: "#e8913a"
    readonly property color alert: "#e05a4f"
    function level(p, base) { return p >= 95 ? alert : p >= 80 ? warn : base; }

    preferredRepresentation: compactRepresentation
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    // Without Claude the widget takes no space; the spacers around it take over.
    Plasmoid.status: running ? PlasmaCore.Types.ActiveStatus : PlasmaCore.Types.HiddenStatus
    toolTipMainText: "Claude"
    toolTipSubText: lead ? nameOf(lead) + ": " + stateText(lead) : T.tr("No active session")

    // Claude's tray icon: its disappearance arrives as an event; it is searched for only while missing.
    DBus.DBusServiceWatcher {
        id: tray
        busType: DBus.BusType.Session
        watchedService: root.trayService
        onRegisteredChanged: if (!registered) root.trayService = ""
    }
    // Plasma's D-Bus module: the signature lists the arguments as a struct, "(ss)", and a call
    // resolves with its pending reply, whose value is the answer.
    function dbus(message, done) {
        DBus.SessionBus.asyncCall(message, reply => (done || (() => {}))(reply && reply.value !== undefined ? reply.value : reply), () => {});
    }
    function findTray() {
        dbus({
            service: "org.kde.StatusNotifierWatcher", path: "/StatusNotifierWatcher",
            iface: "org.freedesktop.DBus.Properties", member: "Get",
            signature: "(ss)", arguments: ["org.kde.StatusNotifierWatcher", "RegisteredStatusNotifierItems"]
        }, items => Array.from(items || []).forEach(item => {
            var cut = String(item).indexOf("/");
            var service = String(item).slice(0, cut), path = String(item).slice(cut);
            dbus({
                service: service, path: path, iface: "org.freedesktop.DBus.Properties", member: "Get",
                signature: "(ss)", arguments: ["org.kde.StatusNotifierItem", "Id"]
            }, id => { if (String(id).startsWith("Claude_")) root.trayService = service; });
        }));
    }
    Timer { interval: 5000; repeat: true; running: !tray.registered; triggeredOnStart: true; onTriggered: root.findTray() }

    // Qt reads the files' modification times inside Plasma (no new process). The mod rewrites files
    // in place, which a directory watcher does not report, so the folder is listed again.
    FolderListModel {
        id: folder
        nameFilters: ["*.json"]
        showDirs: false
        onStatusChanged: if (status === FolderListModel.Ready) root.compare()
    }
    property string stamp: ""
    function compare() {
        var parts = [];
        for (var i = 0; i < folder.count; i++)
            parts.push(folder.get(i, "fileName") + folder.get(i, "fileModified").getTime() + "/" + folder.get(i, "fileSize"));
        var next = parts.join(";");
        if (next !== stamp) { stamp = next; reread.restart(); }
    }
    Timer {
        // Often while Claude runs, rarely otherwise (only to catch a terminal session).
        interval: root.running ? 1500 : 10000
        repeat: true; running: true; triggeredOnStart: true
        onTriggered: { folder.folder = ""; folder.folder = "file://" + root.dir + "/sessions"; }
    }
    // Writes come in bursts (several per tool call): read once after a short quiet spell.
    Timer { id: reread; interval: 200; onTriggered: root.readFiles() }
    // A clock for "X min ago" and for fading dots; it reads nothing.
    Timer { interval: 15000; repeat: true; running: root.running; onTriggered: root.now = Date.now() }
    onRunningChanged: if (running) reread.restart()

    P5Support.DataSource {
        id: exec
        engine: "executable"
        onNewData: (source, data) => {
            disconnectSource(source);
            if (!source.startsWith("awk")) return;
            var files = [], usage = root.usage;
            String(data["stdout"]).split("\n").forEach(line => {
                try {
                    var o = JSON.parse(line);
                    if (o.limits) usage = o; else if (o.id) files.push(o);
                } catch (e) {}
            });
            root.files = files;
            root.usage = usage;
            root.now = Date.now();
        }
    }
    // Opens the session's chat in the Claude desktop app; runs only on a click. open.py hands the
    // deep link straight to the running app (no second app instance to start). Without python3
    // the shell finds the session and uses xdg-open, which is slower. Terminal sessions have no
    // chat in the app, and nothing opens.
    P5Support.DataSource {
        id: launcher
        engine: "executable"
        onNewData: (source, data) => {
            disconnectSource(source);
            var opened = String(data["stdout"]).indexOf("opened") >= 0;
            if (opened) root.raiseClaude();
            // A click on the panel that opened no chat shows the list instead: a terminal session,
            // a session the app no longer has, or the chat Claude already shows ("shown").
            else if (source === root.fromPanel) root.expanded = true;
            if (source === root.fromPanel) root.fromPanel = "";
        }
    }
    property string fromPanel: ""
    // If the opener never answers, the panel is not left waiting for it.
    Timer { interval: 5000; running: root.fromPanel !== ""; onTriggered: root.fromPanel = "" }
    readonly property string openScript: Qt.resolvedUrl("../code/open.py").toString().replace("file://", "")
    function openChat(id, panel) {
        if (!/^[0-9a-f-]{36}$/.test(id || "")) return false;
        var unless = panel && claudeInFront() ? " --unless-shown" : "";
        var command = "if command -v python3 >/dev/null; then python3 -I '" + openScript + "' " + id + unless + "; else "
            + "f=$(grep -rlE --include='local_*.json' '\"cliSessionId\": *\"" + id + "\"' \"$HOME/.config/Claude/claude-code-sessions\" 2>/dev/null | head -1); "
            + "[ -n \"$f\" ] && xdg-open \"claude://code/continue?session=$(basename \"$f\" .json)&source=claudbar\" && echo opened; fi; true";
        if (panel) fromPanel = command;
        launcher.connectSource(command);
        root.expanded = false;
        return true;
    }

    // The window in front, without asking KWin: the task manager's model knows it.
    TaskManager.TasksModel { id: tasks; groupMode: TaskManager.TasksModel.GroupDisabled }
    function claudeInFront() {
        var app = String(tasks.data(tasks.activeTask, TaskManager.AbstractTasksModel.AppId) || "");
        return app.indexOf("com.anthropic.Claude") === 0 || app.toLowerCase() === "claude";
    }

    // A click on the panel: while a session waits for the user it opens that chat straight away
    // (the pinned one if it waits, else the latest waiting one); otherwise it toggles the list.
    // When Claude is in front and already shows that chat, the list opens instead.
    function activate() {
        if (expanded || fromPanel !== "") { expanded = false; return; }
        var waiting = lead && lead.state === "waiting" ? lead : sessions.find(s => s.state === "waiting");
        if (!waiting || !openChat(waiting.id, true)) expanded = true;
    }

    // On Wayland an app cannot raise its own window, so KWin does it: raise.js un-minimizes and
    // focuses Claude's window. Loaded, run and unloaded over D-Bus, without starting a process.
    readonly property string raiseScript: Qt.resolvedUrl("../code/raise.js").toString().replace("file://", "")
    function kwin(path, iface, member, signature, args, done) {
        var message = { service: "org.kde.KWin", path: path, iface: iface, member: member };
        if (signature) { message.signature = "(" + signature + ")"; message.arguments = args; }
        dbus(message, done);
    }
    function raiseClaude() {
        var name = "claudbar-raise";
        kwin("/Scripting", "org.kde.kwin.Scripting", "unloadScript", "s", [name], () =>
            kwin("/Scripting", "org.kde.kwin.Scripting", "loadScript", "ss", [raiseScript, name], id => {
                if (id < 0) return;
                kwin("/Scripting/Script" + id, "org.kde.kwin.Script", "run", "", [], () =>
                    kwin("/Scripting", "org.kde.kwin.Scripting", "unloadScript", "s", [name]));
            }));
    }

    // One awk process per read: each file as one JSON line.
    function readFiles() { exec.connectSource("awk 1 '" + dir + "'/sessions/*.json '" + dir + "/usage.json' 2>/dev/null"); }
    // Once at start: remove session files older than a week.
    Component.onCompleted: exec.connectSource("find '" + dir + "/sessions' -name '*.json' -mtime +7 -delete 2>/dev/null; true")

    function span(ms) {
        var m = Math.max(0, Math.round(ms / 60000));
        if (m < 1) return T.tr("now");
        if (m < 60) return m + " min";
        if (m < 1440) return Math.floor(m / 60) + " h " + (m % 60) + " min";
        return Math.floor(m / 1440) + " d " + Math.floor((m % 1440) / 60) + " h";
    }
    function ago(ms) { return ms < 60000 ? span(ms) : T.tr("%1 ago", span(ms)); }
    function stateText(s) {
        // A permission prompt names its tool; a question at the end of a turn names none.
        // The tool's description comes last: on a narrow bar it is the part that gets shortened.
        var doing = s.tool ? " · " + shortTool(s.tool) + (s.detail ? ": " + s.detail : "") : "";
        if (s.state === "waiting") return s.tool && s.tool !== "AskUserQuestion" && s.tool !== "ExitPlanMode"
            ? T.tr("waiting for approval") + doing : T.tr("waiting for you");
        if (s.state === "working") return T.tr("working") + " · " + span(now - s.since) + doing;
        return T.tr("done") + " · " + ago(now - s.since);
    }
    // mcp__server__tool → tool
    function shortTool(name) { return name.startsWith("mcp__") ? name.split("__").pop() : name; }
    function limitName(kind) { return ({ five_hour: T.tr("5 h"), seven_day: T.tr("Week") })[kind] || kind.replace(/_/g, " "); }
    function resetIn(l) { return l.resetsAt ? "↻ " + span(Date.parse(l.resetsAt) - now) : ""; }
    // claude-opus-5-5[1m] → Opus 5.5
    function modelName(m) {
        var parts = (m || "").replace(/^claude-/, "").replace(/\[.*\]$/, "").split("-");
        if (!parts[0]) return "";
        return parts[0].charAt(0).toUpperCase() + parts[0].slice(1) + (parts.length > 1 ? " " + parts.slice(1).join(".") : "");
    }
    function usd(v) { return "$" + v.toFixed(2); }

    component Label: PlasmaComponents3.Label {
        color: Kirigami.Theme.textColor
        font: Kirigami.Theme.smallFont
    }
    component Dim: Label { opacity: 0.65 }
    component Divider: Rectangle { width: 1; Layout.preferredHeight: 18; color: Kirigami.Theme.textColor; opacity: 0.18 }
    component Meter: RowLayout {
        property string name
        property real value: 0
        property string extra: ""
        property color tint: root.sky
        spacing: Kirigami.Units.smallSpacing
        Dim { text: parent.name }
        Bar { visible: !Plasmoid.configuration.compact; Layout.preferredWidth: Kirigami.Units.gridUnit * 4; value: parent.value; color: root.level(parent.value, parent.tint) }
        // In compact mode the percentage takes the bar's colour, so a high value still stands out.
        Label {
            text: Math.round(parent.value) + "%"; font.bold: true; Layout.minimumWidth: Kirigami.Units.gridUnit * 1.6
            color: Plasmoid.configuration.compact && parent.value >= 80 ? root.level(parent.value, Kirigami.Theme.textColor) : Kirigami.Theme.textColor
        }
        // Fixed width, so a reset time getting shorter does not move what follows.
        Dim { text: parent.extra; visible: text !== ""; Layout.preferredWidth: Kirigami.Units.gridUnit * 4; elide: Text.ElideRight }
    }

    // The bar's fixed width; the popup follows it within sensible bounds. It never drops below what
    // the meters need plus room for a session's dots, name and a few words of its state (minBar),
    // so nothing overlaps; a wider bar shows more of what the session is doing.
    property real minBar: 0
    readonly property real barWidth: Math.max(Kirigami.Units.gridUnit * Plasmoid.configuration.width, minBar)

    // Repeaters below count by index, so a read updates rows in place instead of rebuilding them.
    compactRepresentation: MouseArea {
        id: compact
        readonly property int pad: Kirigami.Units.largeSpacing
        // A fixed width: the panel does not shift when names, states or times change.
        Layout.minimumWidth: root.running ? root.barWidth : 0
        Layout.preferredWidth: Layout.minimumWidth
        Layout.maximumWidth: Layout.minimumWidth
        Layout.fillWidth: false
        hoverEnabled: true
        onClicked: root.activate()
        Binding { target: root; property: "minBar"; value: gauges.implicitWidth + Kirigami.Units.gridUnit * 14 + compact.pad * 2 + Kirigami.Units.largeSpacing }

        Rectangle {
            anchors.fill: parent
            anchors.topMargin: 6; anchors.bottomMargin: 6
            radius: 8
            color: Kirigami.Theme.textColor
            opacity: compact.containsMouse ? 0.12 : 0.06
            border.width: root.lead && root.lead.state === "waiting" ? 1 : 0
            border.color: root.warn
        }

        RowLayout {
            id: row
            anchors.fill: parent
            anchors.leftMargin: compact.pad; anchors.rightMargin: compact.pad
            spacing: Kirigami.Units.largeSpacing
            visible: root.running
            clip: true

            // The session part takes what is left and shortens its text; the meters keep their place on the right.
            RowLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: Kirigami.Units.smallSpacing
                Row {
                    spacing: 1
                    Repeater {
                        model: root.shown.length
                        delegate: Item {
                            id: chip
                            required property int index
                            readonly property var item: root.shown[index] || ({})
                            readonly property bool current: !!root.lead && item.id === root.lead.id
                            width: 15; height: 15
                            Rectangle {
                                anchors.fill: parent; radius: width / 2
                                color: "transparent"
                                border.width: chip.current ? 1.5 : 0
                                border.color: Kirigami.Theme.textColor
                                opacity: 0.7
                            }
                            Dot { anchors.centerIn: parent; mode: chip.item.state || "idle" }
                            // Hover only: a click goes to the panel (pinning is in the list).
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.NoButton
                                PlasmaComponents3.ToolTip { text: chip.item.state ? root.nameOf(chip.item) + ": " + root.stateText(chip.item) : "" }
                            }
                        }
                    }
                }
                Kirigami.Icon {
                    visible: root.picked !== "" && !!root.lead && root.lead.id === root.picked
                    source: "window-pin"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small; Layout.preferredHeight: Layout.preferredWidth
                    opacity: 0.7
                }
                Label {
                    text: root.lead ? root.nameOf(root.lead) : "Claude"; font.bold: true
                    elide: Text.ElideRight
                    Layout.maximumWidth: Kirigami.Units.gridUnit * 8
                }
                Dim {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                    text: root.lead ? root.stateText(root.lead) : T.tr("no session")
                    color: root.lead && root.lead.state === "waiting" ? root.warn : Kirigami.Theme.textColor
                    opacity: root.lead && root.lead.state === "waiting" ? 1 : 0.65
                }
            }
            // Meters keep their natural width; the bar is never narrower than they need.
            RowLayout {
                id: gauges
                spacing: Kirigami.Units.largeSpacing
                Divider { opacity: !!root.lead && root.lead.context !== null ? 0.18 : 0 }
                Meter { opacity: !!root.lead && root.lead.context !== null ? 1 : 0; name: T.tr("Context"); value: root.lead ? root.lead.context || 0 : 0; tint: root.dusk }
                Repeater {
                    model: root.limits.length
                    delegate: RowLayout {
                        required property int index
                        readonly property var item: root.limits[index] || ({})
                        spacing: Kirigami.Units.largeSpacing
                        Divider {}
                        Meter { name: root.limitName(item.kind || ""); value: item.percent || 0; extra: root.resetIn(item); tint: item.kind === "seven_day" ? root.sage : root.sky }
                    }
                }
                // Cost is priced as on the API; the panel shows the current session, the popup the total.
                Divider { opacity: !!root.lead && root.lead.cost > 0 ? 0.18 : 0 }
                Label {
                    opacity: !!root.lead && root.lead.cost > 0 ? 1 : 0; text: root.lead ? root.usd(root.lead.cost || 0) : ""; font.bold: true
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 3.2; horizontalAlignment: Text.AlignRight
                }
            }
        }
    }

    // One-line rows with fixed column widths: nothing moves on hover or on refresh.
    fullRepresentation: ColumnLayout {
        readonly property real unit: Kirigami.Units.gridUnit
        // As wide as the bar, but not narrower than the list needs nor wider than reads well.
        readonly property real fit: Math.max(unit * 25, Math.min(root.barWidth, unit * 44))
        Layout.minimumWidth: fit
        Layout.maximumWidth: fit
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: Kirigami.Units.smallSpacing
            PlasmaComponents3.Label { text: root.listed.length ? T.tr("Sessions · %1", root.listed.length) : T.tr("No active session"); font.bold: true }
            Item { Layout.fillWidth: true }
            PlasmaComponents3.Label {
                visible: root.listed.length > 0
                text: T.tr("click to open the chat")
                opacity: 0.55
                font: Kirigami.Theme.smallFont
            }
        }
        Repeater {
            model: root.listed.length
            delegate: MouseArea {
                id: entry
                required property int index
                readonly property var item: root.listed[index] || ({})
                readonly property bool current: !!root.lead && item.id === root.lead.id
                readonly property real unit: Kirigami.Units.gridUnit
                Layout.fillWidth: true
                Layout.preferredHeight: unit * 1.7
                readonly property bool pinned: root.picked !== "" && root.picked === item.id
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openChat(item.id)

                Rectangle {
                    anchors.fill: parent
                    radius: Kirigami.Units.cornerRadius
                    color: Kirigami.Theme.highlightColor
                    opacity: entry.current ? 0.22 : entry.containsMouse ? 0.1 : 0
                    border.width: entry.pinned ? 1 : 0
                    border.color: Kirigami.Theme.highlightColor
                }
                PlasmaComponents3.ToolTip { text: entry.item.project + " · " + root.modelName(entry.item.model); visible: entry.containsMouse && !edit.visible }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Kirigami.Units.smallSpacing; anchors.rightMargin: 2
                    spacing: Kirigami.Units.smallSpacing
                    Dot { mode: entry.item.state || "idle" }
                    Item {
                        Layout.preferredWidth: entry.unit * 5.5
                        Layout.fillHeight: true
                        PlasmaComponents3.Label {
                            anchors.fill: parent
                            visible: !edit.visible
                            verticalAlignment: Text.AlignVCenter
                            text: root.nameOf(entry.item)
                            font.bold: true
                            elide: Text.ElideRight
                        }
                        // Custom name: Enter saves, Esc cancels, an empty field goes back to the title's word.
                        PlasmaComponents3.TextField {
                            id: edit
                            anchors.fill: parent
                            anchors.topMargin: 1; anchors.bottomMargin: 1
                            visible: false
                            placeholderText: root.titleWord(entry.item.title) || entry.item.project || ""
                            onAccepted: { root.rename(entry.item.id, text); visible = false; }
                            Keys.onEscapePressed: visible = false
                            onActiveFocusChanged: if (!activeFocus) visible = false
                        }
                    }
                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        text: entry.item.state ? root.stateText(entry.item) : ""
                        elide: Text.ElideRight
                        font: Kirigami.Theme.smallFont
                        color: entry.item.state === "waiting" ? root.warn : Kirigami.Theme.textColor
                        opacity: entry.item.state === "waiting" ? 1 : 0.65
                    }
                    Bar {
                        Layout.preferredWidth: entry.unit * 2.2
                        value: entry.item.context || 0
                        color: root.level(entry.item.context || 0, root.dusk)
                        opacity: entry.item.context === null ? 0 : 1
                    }
                    PlasmaComponents3.Label {
                        Layout.preferredWidth: entry.unit * 1.8
                        horizontalAlignment: Text.AlignRight
                        text: entry.item.context === null || entry.item.context === undefined ? "" : entry.item.context + "%"
                        font: Kirigami.Theme.smallFont
                    }
                    PlasmaComponents3.Label {
                        Layout.preferredWidth: entry.unit * 2.6
                        horizontalAlignment: Text.AlignRight
                        text: entry.item.cost ? root.usd(entry.item.cost) : ""
                        font: Kirigami.Theme.smallFont
                        opacity: 0.8
                    }
                    // Buttons stay in the layout and only fade in, so the row keeps its width.
                    PlasmaComponents3.ToolButton {
                        icon.name: "window-pin"
                        display: PlasmaComponents3.AbstractButton.IconOnly
                        text: entry.pinned ? T.tr("Unpin from the panel") : T.tr("Pin to the panel")
                        checkable: true
                        checked: entry.pinned
                        Layout.preferredWidth: Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing * 2
                        Layout.preferredHeight: Layout.preferredWidth
                        opacity: entry.pinned || entry.containsMouse || hovered ? 1 : 0
                        onClicked: root.pick(entry.item.id)
                        PlasmaComponents3.ToolTip { text: parent.text }
                    }
                    PlasmaComponents3.ToolButton {
                        icon.name: "edit-rename"
                        display: PlasmaComponents3.AbstractButton.IconOnly
                        text: T.tr("Rename")
                        Layout.preferredWidth: Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing * 2
                        Layout.preferredHeight: Layout.preferredWidth
                        opacity: entry.containsMouse || hovered ? 1 : 0
                        onClicked: { edit.text = root.names[entry.item.id] || ""; edit.visible = true; edit.forceActiveFocus(); }
                    }
                }
            }
        }

        Kirigami.Separator { Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.smallSpacing; visible: root.limits.length > 0 }
        Repeater {
            model: root.limits.length
            delegate: RowLayout {
                required property int index
                readonly property var item: root.limits[index] || ({})
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing; Layout.rightMargin: Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.smallSpacing
                PlasmaComponents3.Label { text: root.limitName(item.kind || ""); Layout.preferredWidth: Kirigami.Units.gridUnit * 3.5; font: Kirigami.Theme.smallFont; opacity: 0.7 }
                Bar { Layout.fillWidth: true; value: item.percent || 0; color: root.level(item.percent || 0, item.kind === "seven_day" ? root.sage : root.sky) }
                PlasmaComponents3.Label { text: (item.percent || 0) + "%"; font.bold: true; Layout.preferredWidth: Kirigami.Units.gridUnit * 1.8; horizontalAlignment: Text.AlignRight }
                PlasmaComponents3.Label { text: root.resetIn(item); Layout.preferredWidth: Kirigami.Units.gridUnit * 4.2; font: Kirigami.Theme.smallFont; opacity: 0.6 }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.smallSpacing
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: root.usage ? T.tr("Limits read %1", root.ago(root.now - root.usage.at)) + (root.cost > 0 ? " · " + T.tr("total %1", root.usd(root.cost)) : "") : ""
                elide: Text.ElideRight
                opacity: 0.5
                font: Kirigami.Theme.smallFont
            }
            PlasmaComponents3.Label { text: T.tr("Width"); font: Kirigami.Theme.smallFont; opacity: 0.7 }
            // Applies when released, so the panel does not resize on every step of the drag.
            PlasmaComponents3.Slider {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 5
                from: Math.ceil(root.minBar / Kirigami.Units.gridUnit / 2) * 2; to: 80; stepSize: 2; snapMode: PlasmaComponents3.Slider.SnapAlways
                value: Plasmoid.configuration.width
                onPressedChanged: if (!pressed) Plasmoid.configuration.width = value
                PlasmaComponents3.ToolTip { text: T.tr("Width of the bar on the panel"); visible: parent.hovered }
            }
            PlasmaComponents3.Switch {
                text: T.tr("Compact")
                font: Kirigami.Theme.smallFont
                checked: Plasmoid.configuration.compact
                onToggled: Plasmoid.configuration.compact = checked
            }
        }
    }
}
