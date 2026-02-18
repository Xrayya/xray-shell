pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import QtQuick
import QtQuick.Layouts

ShellRoot {
    id: root

    // Theme colors
    property color colBg: "#1a1b26"
    property color colFg: "#a9b1d6"
    property color colMuted: "#444b6a"
    property color colCyan: "#0db9d7"
    property color colPurple: "#ad8ee6"
    property color colRed: "#f7768e"
    property color colYellow: "#e0af68"
    property color colBlue: "#7aa2f7"

    // Font
    property string fontFamily: "Noto Sans"
    property int fontSize: 12

    // System info properties
    property int cpuUsage: 0
    property int memUsage: 0
    property int volumeLevel: 0
    property string activeWindow: "Window"

    // CPU tracking
    property var lastCpuIdle: 0
    property var lastCpuTotal: 0

    // CPU usage
    Process {
        id: cpuProc
        command: ["sh", "-c", "head -1 /proc/stat"]
        stdout: SplitParser {
            onRead: data => {
                if (!data)
                    return;
                var parts = data.trim().split(/\s+/);
                var user = parseInt(parts[1]) || 0;
                var nice = parseInt(parts[2]) || 0;
                var system = parseInt(parts[3]) || 0;
                var idle = parseInt(parts[4]) || 0;
                var iowait = parseInt(parts[5]) || 0;
                var irq = parseInt(parts[6]) || 0;
                var softirq = parseInt(parts[7]) || 0;

                var total = user + nice + system + idle + iowait + irq + softirq;
                var idleTime = idle + iowait;

                if (root.lastCpuTotal > 0) {
                    var totalDiff = total - root.lastCpuTotal;
                    var idleDiff = idleTime - root.lastCpuIdle;
                    if (totalDiff > 0) {
                        root.cpuUsage = Math.round(100 * (totalDiff - idleDiff) / totalDiff);
                    }
                }
                root.lastCpuTotal = total;
                root.lastCpuIdle = idleTime;
            }
        }
        Component.onCompleted: running = true
    }

    // Memory usage
    Process {
        id: memProc
        command: ["sh", "-c", "free | grep Mem"]
        stdout: SplitParser {
            onRead: data => {
                if (!data)
                    return;
                var parts = data.trim().split(/\s+/);
                var total = parseInt(parts[1]) || 1;
                var used = parseInt(parts[2]) || 0;
                root.memUsage = Math.round(100 * used / total);
            }
        }
        Component.onCompleted: running = true
    }

    // Volume level (wpctl for PipeWire)
    Process {
        id: volProc
        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]
        stdout: SplitParser {
            onRead: data => {
                if (!data)
                    return;
                var match = data.match(/Volume:\s*([\d.]+)/);
                if (match) {
                    root.volumeLevel = Math.round(parseFloat(match[1]) * 100);
                }
            }
        }
        Component.onCompleted: running = true
    }

    // Slow timer for system stats
    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: {
            cpuProc.running = true;
            memProc.running = true;
            volProc.running = true;
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            Hyprland.refreshToplevels();
        }
    }

    Connections {
        target: DesktopEntries
        function applicationsChanged() {
            Hyprland.refreshToplevels();
        }
    }

    PwObjectTracker {
        objects: Pipewire.ready ? [Pipewire.preferredDefaultAudioSink] : []
    }

    function dumpObject(obj, depth = 0) {
        if (depth > 4) // avoid infinite recursion
            return '[MaxDepth]';
        if (obj === null)
            return 'null';
        if (typeof obj !== 'object')
            return obj;
        let out = '{ ';
        for (let k in obj) {
            try {
                out += k + ': ';
                if (typeof obj[k] === 'object' && obj[k] !== null)
                    out += dumpObject(obj[k], depth + 1);
                else
                    out += obj[k];
                out += ', ';
            } catch (e) {
                out += k + ': [unreadable], ';
            }
        }
        out += '}';
        return out;
    }

    // ReloadPopup {}
    //
    Variants {
        model: Quickshell.screens

        PanelWindow {
            property var modelData
            screen: modelData

            anchors {
                top: true
                left: true
                right: true
            }

            implicitHeight: 30
            color: root.colBg

            margins {
                top: 0
                bottom: 0
                left: 0
                right: 0
            }

            Rectangle {
                anchors.fill: parent
                color: root.colBg

                RowLayout {
                    anchors.fill: parent
                    spacing: 0

                    Text {
                        text: Hyprland.activeToplevel?.title || ""
                        color: root.colPurple
                        // font.pixelSize: root.fontSize
                        font.family: root.fontFamily
                        font.bold: true
                        Layout.fillWidth: true
                        Layout.maximumWidth: 400
                        Layout.leftMargin: 8
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        spacing: 6

                        Repeater {
                            model: {
                                return Hyprland.workspaces;
                            }

                            Rectangle {
                                id: workspaceRect
                                implicitWidth: workspaceRow.implicitWidth
                                Layout.fillHeight: true
                                color: "transparent"

                                required property var modelData

                                RowLayout {
                                    id: workspaceRow
                                    anchors.verticalCenter: parent.verticalCenter
                                    height: parent.height
                                    spacing: 4

                                    Text {
                                        text: `${workspaceRect.modelData.id}:`
                                        // color: root.colCyan
                                        color: workspaceRect.modelData.active ? root.colCyan : root.colMuted
                                        font.pixelSize: root.fontSize
                                        font.family: root.fontFamily
                                        font.bold: true
                                    }

                                    RowLayout {
                                        spacing: 4

                                        Repeater {
                                            model: {
                                                return workspaceRect.modelData.toplevels.values?.slice().sort((a, b) => {
                                                    const aValue = a.lastIpcObject?.at?.[0] || 0;
                                                    const bValue = b.lastIpcObject?.at?.[0] || 0;
                                                    const score = aValue - bValue;
                                                    return score !== 0 ? score : bValue - aValue;
                                                }) || [];
                                            }

                                            Rectangle {
                                                id: windowRect
                                                implicitWidth: appIcon.implicitWidth
                                                Layout.fillHeight: true
                                                color: "transparent"

                                                required property var modelData

                                                IconImage {
                                                    id: appIcon
                                                    source: {
                                                        // console.log("Looking up icon for", windowRect.modelData.wayland?.appId);
                                                        // console.log("Desktop entry data:", dumpObject(DesktopEntries.heuristicLookup(windowRect.modelData.wayland?.appId)));
                                                        // console.log("Icon path:", Quickshell.iconPath(DesktopEntries.heuristicLookup(windowRect.modelData.wayland?.appId || "")?.icon, true));
                                                        return Quickshell.iconPath(DesktopEntries.heuristicLookup(windowRect.modelData.wayland?.appId || "")?.icon, "application-x-executable");
                                                    }
                                                    backer.opacity: windowRect.modelData.activated ? 1 : 0.5
                                                    asynchronous: true
                                                    implicitWidth: 16
                                                    implicitHeight: 16
                                                    anchors.centerIn: parent
                                                }

                                                Rectangle {
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    anchors.bottom: parent.bottom
                                                    anchors.bottomMargin: 3
                                                    height: 2
                                                    width: parent.implicitWidth * 0.5
                                                    color: windowRect.modelData.activated ? root.colYellow : "transparent"
                                                }

                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: Hyprland.dispatch(`focuswindow address:0x${windowRect.modelData.address}`)
                                                }
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    width: parent.width
                                    height: 2
                                    color: workspaceRect.modelData.active ? root.colPurple : "transparent"
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.bottom
                                }

                                // MouseArea {
                                //     anchors.fill: parent
                                //     cursorShape: Qt.PointingHandCursor
                                //     onClicked: Hyprland.focusedWorkspace.id !== modelData.id && Hyprland.dispatch("workspace " + modelData.id)
                                // }
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    Text {
                        text: "CPU: " + root.cpuUsage + "%"
                        color: root.colYellow
                        font.pixelSize: root.fontSize
                        font.family: root.fontFamily
                        font.bold: true
                        Layout.rightMargin: 8
                    }

                    Rectangle {
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: 16
                        Layout.alignment: Qt.AlignVCenter
                        Layout.leftMargin: 0
                        Layout.rightMargin: 8
                        color: root.colMuted
                    }

                    Text {
                        text: "Mem: " + root.memUsage + "%"
                        color: root.colCyan
                        font.pixelSize: root.fontSize
                        font.family: root.fontFamily
                        font.bold: true
                        Layout.rightMargin: 8
                    }

                    Rectangle {
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: 16
                        Layout.alignment: Qt.AlignVCenter
                        Layout.leftMargin: 0
                        Layout.rightMargin: 8
                        color: root.colMuted
                    }

                    Text {
                        text: `Vol: ${Math.floor((Pipewire.preferredDefaultAudioSink?.audio.volume || 0) * 100)}%`
                        color: root.colPurple
                        font.pixelSize: root.fontSize
                        font.family: root.fontFamily
                        font.bold: true
                        Layout.rightMargin: 8
                    }

                    Rectangle {
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: 16
                        Layout.alignment: Qt.AlignVCenter
                        Layout.leftMargin: 0
                        Layout.rightMargin: 8
                        color: root.colMuted
                    }

                    Text {
                        text: `Bat: ${UPower.displayDevice.percentage * 100}% (${UPowerDeviceState.toString(UPower.displayDevice.state)})`
                        color: UPower.displayDevice.percentage <= 0.2 ? root.colRed : UPower.displayDevice.state === 4 || UPower.displayDevice.state === 3 ? root.colCyan : root.colBlue
                        font.pixelSize: root.fontSize
                        font.family: root.fontFamily
                        font.bold: true
                        Layout.rightMargin: 8
                    }

                    Rectangle {
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: 16
                        Layout.alignment: Qt.AlignVCenter
                        Layout.leftMargin: 0
                        Layout.rightMargin: 8
                        color: root.colMuted
                    }

                    SystemClock {
                        id: systemClock
                    }

                    Text {
                        id: clockText
                        text: Qt.formatDateTime(systemClock.date, "HH:mm - MMM dd")
                        color: root.colCyan
                        font.pixelSize: root.fontSize
                        font.family: root.fontFamily
                        font.bold: true
                        Layout.rightMargin: 8
                    }

                    Item {
                        width: 8
                    }
                }
            }
        }
    }
}
