import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    property real fivePct: -1
    property real fiveResets: 0
    property real weekPct: -1
    property real weekResets: 0
    property string error: ""
    property real now: Date.now()

    readonly property string fetchCmd: "python3 -I '" +
        Qt.resolvedUrl("../code/fetch.py").toString().replace("file://", "") + "'"

    function barColor(pct) {
        if (pct >= 90) return Kirigami.Theme.negativeTextColor
        if (pct >= 70) return Kirigami.Theme.neutralTextColor
        return Kirigami.Theme.positiveTextColor
    }

    function resetTime(epoch) {
        if (!epoch) return "unknown"
        var t = new Date(epoch * 1000)
        // Add the weekday when the reset isn't today, e.g. the weekly limit
        var fmt = t.toDateString() === new Date(now).toDateString() ? "HH:mm" : "ddd HH:mm"
        return Qt.formatDateTime(t, fmt)
    }

    function fmtPct(pct) {
        return pct < 0 ? "?" : Math.round(pct) + "%"
    }

    function refresh() {
        exec.connectSource(fetchCmd)
    }

    preferredRepresentation: compactRepresentation
    Plasmoid.constraintHints: Plasmoid.CanFillArea
    onExpandedChanged: if (expanded) refresh()
    toolTipMainText: "Claude usage"
    toolTipSubText: error !== "" ? error :
        "5-hour: " + fmtPct(fivePct) + " (resets " + resetTime(fiveResets) + ")\n" +
        "Weekly: " + fmtPct(weekPct) + " (resets " + resetTime(weekResets) + ")"

    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source)
            root.now = Date.now()
            try {
                var r = JSON.parse(data["stdout"])
            } catch (e) {
                root.error = "Bad response from fetch script"
                return
            }
            root.error = r.error || ""
            if (r.five) { root.fivePct = r.five.pct; root.fiveResets = r.five.resets || 0 }
            if (r.week) { root.weekPct = r.week.pct; root.weekResets = r.week.resets || 0 }
        }
    }

    Timer {
        interval: 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    component UsageBar: Rectangle {
        property real pct: -1
        property string label

        radius: Kirigami.Units.cornerRadius
        color: Qt.alpha(Kirigami.Theme.textColor, 0.15)
        border.color: Qt.alpha(Kirigami.Theme.textColor, 0.3)

        Rectangle {
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: parent.width * Math.min(100, Math.max(0, parent.pct)) / 100
            radius: parent.radius
            color: root.barColor(parent.pct)
            opacity: root.error !== "" ? 0.4 : 1
        }

        PlasmaComponents.Label {
            anchors.centerIn: parent
            // Transient failures keep the last good value (dimmed); "!" only when there is none
            text: root.error !== "" && parent.pct < 0 ? "!" : parent.label + " " + root.fmtPct(parent.pct)
            font.pixelSize: parent.height * 0.8
            font.bold: true
        }
    }

    compactRepresentation: MouseArea {
        id: compact
        Layout.preferredWidth: Kirigami.Units.gridUnit * 4
        Layout.minimumWidth: Kirigami.Units.gridUnit * 3
        onClicked: root.expanded = !root.expanded

        Column {
            anchors.centerIn: parent
            width: parent.width - Kirigami.Units.smallSpacing * 2
            spacing: 2

            UsageBar {
                width: parent.width
                height: (compact.height - 6) / 2
                pct: root.fivePct
                label: "5h"
            }
            UsageBar {
                width: parent.width
                height: (compact.height - 6) / 2
                pct: root.weekPct
                label: "wk"
            }
        }
    }

    fullRepresentation: ColumnLayout {
        Layout.preferredWidth: Kirigami.Units.gridUnit * 14

        PlasmaComponents.Label {
            visible: root.error !== ""
            text: root.error
            color: Kirigami.Theme.negativeTextColor
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }

        Repeater {
            model: [
                { name: "5-hour", pct: root.fivePct, resets: root.fiveResets },
                { name: "Weekly", pct: root.weekPct, resets: root.weekResets }
            ]
            delegate: ColumnLayout {
                required property var modelData
                Layout.fillWidth: true

                PlasmaComponents.Label {
                    text: modelData.name + ": " + root.fmtPct(modelData.pct) +
                          " (resets " + root.resetTime(modelData.resets) + ")"
                }
                PlasmaComponents.ProgressBar {
                    Layout.fillWidth: true
                    from: 0
                    to: 100
                    value: Math.max(0, modelData.pct)
                }
            }
        }
    }
}
