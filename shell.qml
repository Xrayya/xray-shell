import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Widgets
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
    property int batteryLevel: 0
    property string batteryStatus: "Unknown"
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

                if (lastCpuTotal > 0) {
                    var totalDiff = total - lastCpuTotal;
                    var idleDiff = idleTime - lastCpuIdle;
                    if (totalDiff > 0) {
                        cpuUsage = Math.round(100 * (totalDiff - idleDiff) / totalDiff);
                    }
                }
                lastCpuTotal = total;
                lastCpuIdle = idleTime;
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
                memUsage = Math.round(100 * used / total);
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
                    volumeLevel = Math.round(parseFloat(match[1]) * 100);
                }
            }
        }
        Component.onCompleted: running = true
    }

    // Active window title
    Process {
        id: windowProc
        command: ["sh", "-c", "hyprctl activewindow -j | jq -r '.title // empty'"]
        stdout: SplitParser {
            onRead: data => {
                if (data && data.trim()) {
                    activeWindow = data.trim();
                }
            }
        }
        Component.onCompleted: running = true
    }

    // Battery level
    Process {
        id: batteryProc
        command: ["sh", "-c", "cat /sys/class/power_supply/BAT0/capacity"]
        stdout: SplitParser {
            onRead: data => {
                if (!data)
                    return;
                batteryLevel = parseInt(data.trim()) || 0;
            }
        }
        Component.onCompleted: running = true
    }

    Process {
        id: batteryStatusProc
        command: ["sh", "-c", "cat /sys/class/power_supply/BAT0/status"]
        stdout: SplitParser {
            onRead: data => {
                if (!data)
                    return;
                batteryStatus = data.trim();
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
            batteryProc.running = true;
            batteryStatusProc.running = true;
        }
    }

    // Event-based updates for window/layout (instant)
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            windowProc.running = true;
        }
    }

    // Backup timer for window/layout (catches edge cases)
    Timer {
        interval: 200
        running: true
        repeat: true
        onTriggered: {
            windowProc.running = true;
        }
    }

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

                    Item {
                        width: 8
                    }

                    Item {
                        width: 8
                    }

                    RowLayout {
                        implicitHeight: parent.height
                        spacing: 6

                        Repeater {
                            model: Hyprland.workspaces

                            Rectangle {
                                implicitWidth: workspaceRow.implicitWidth
                                implicitHeight: parent.height
                                color: "transparent"

                                RowLayout {
                                    id: workspaceRow
                                    implicitHeight: parent.height
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 4

                                    Text {
                                        text: `${modelData.id}:`
                                        color: root.colCyan
                                        font.pixelSize: root.fontSize
                                        font.family: root.fontFamily
                                        font.bold: true
                                    }

                                    RowLayout {
                                        implicitHeight: parent.height
                                        spacing: 4

                                        Repeater {
                                            model: modelData.toplevels

                                            Rectangle {
                                              implicitWidth: appIcon.width
                                              implicitHeight: parent.height
                                                color: "transparent"

                                                IconImage {
                                                    id: appIcon
                                                    source: Quickshell.iconPath(DesktopEntries.heuristicLookup(modelData.wayland.appId).icon) || ""
                                                    width: 16
                                                    height: 16
                                                    anchors.centerIn: parent
                                                }

                                                Rectangle {
                                                    anchors.left: parent.left
                                                    anchors.right: parent.right
                                                    anchors.bottom: parent.bottom 
                                                    anchors.bottomMargin: 3
                                                    height: 2
                                                    color: modelData.activated ? root.colYellow : "transparent"
                                                    // isActiveWindow: boolean, tentukan sendiri logikanya
                                                }
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    width: parent.width
                                    height: 2
                                    color: modelData.active ? root.colPurple : "transparent"
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.bottom
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: Hyprland.dispatch("workspace " + modelData.id)
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: 16
                        Layout.alignment: Qt.AlignVCenter
                        Layout.leftMargin: 8
                        Layout.rightMargin: 8
                        color: root.colMuted
                    }

                    Text {
                        text: activeWindow
                        color: root.colPurple
                        font.pixelSize: root.fontSize
                        font.family: root.fontFamily
                        font.bold: true
                        Layout.fillWidth: true
                        Layout.maximumWidth: 400
                        Layout.leftMargin: 8
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 16
                        Layout.alignment: Qt.AlignVCenter
                        Layout.leftMargin: 8
                        Layout.rightMargin: 8
                        color: "transparent"
                    }

                    Text {
                        text: "CPU: " + cpuUsage + "%"
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
                        text: "Mem: " + memUsage + "%"
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
                        text: "Vol: " + volumeLevel + "%"
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
                        text: `Bat: ${batteryLevel}% (${batteryStatus})`
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
