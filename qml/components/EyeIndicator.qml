// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Shapes

Item {
    id: root

    property string state: "searching" // searching | checking | success | unavailable
    property string gazeDirection: "auto" // auto | left | center | right
    property bool reducedMotion: false
    property real iconSize: 72
    property color neutralColor: "#d5ddd8"
    property color checkingColor: "#f59e0b"
    property color successColor: "#65d1a7"
    property color unavailableColor: "#748078"
    property color backgroundColor: "#101916"
    readonly property bool searching: state === "searching"
    readonly property bool checking: state === "checking"
    readonly property bool success: state === "success"
    readonly property bool unavailable: state === "unavailable"
    readonly property color statusColor: checking ? checkingColor
        : success ? successColor : unavailable ? unavailableColor : neutralColor
    readonly property real pupilTravel: width * 0.105
    readonly property int directedIndex: gazeDirection === "left" ? -1
        : gazeDirection === "right" ? 1 : 0
    property int glanceIndex: 0
    property int glanceStep: 0
    property bool blinking: false

    function resetMotion() {
        glanceIndex = 0
        glanceStep = 0
        blinking = false
        blinkClose.stop()
        if (searching && gazeDirection === "auto" && !reducedMotion) {
            glanceTimer.start()
            blinkTimer.restart()
        } else {
            glanceTimer.stop()
            blinkTimer.stop()
        }
    }

    width: iconSize
    height: iconSize
    opacity: unavailable ? 0.64 : 1
    onStateChanged: resetMotion()
    onGazeDirectionChanged: resetMotion()
    onReducedMotionChanged: resetMotion()
    Component.onCompleted: resetMotion()

    Rectangle {
        anchors.centerIn: parent
        width: root.width * 0.88
        height: root.height * 0.66
        radius: width / 2
        color: Qt.rgba(root.statusColor.r, root.statusColor.g, root.statusColor.b,
                       root.checking ? 0.13 : root.success ? 0.16 : 0.06)
        opacity: root.unavailable ? 0 : 1
        Behavior on color { ColorAnimation { duration: 180 } }
    }

    Item {
        id: openEye
        anchors.fill: parent
        visible: !root.blinking && !root.unavailable

        Shape {
            width: 24
            height: 24
            anchors.centerIn: parent
            scale: root.width / 24
            transformOrigin: Item.Center
            antialiasing: true
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                fillColor: "transparent"
                strokeColor: root.statusColor
                strokeWidth: 2
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg {
                    path: "M2.062 12.348a1 1 0 0 1 0-.696 10.75 10.75 0 0 1 19.876 0 1 1 0 0 1 0 .696 10.75 10.75 0 0 1-19.876 0"
                }
            }
        }

        Rectangle {
            width: root.width * 0.205
            height: width
            radius: width / 2
            y: (parent.height - height) / 2
            x: (parent.width - width) / 2
               + (root.gazeDirection === "auto" ? root.glanceIndex : root.directedIndex)
                 * root.pupilTravel
            color: root.statusColor

            Rectangle {
                width: parent.width * 0.24
                height: width
                radius: width / 2
                x: parent.width * 0.23
                y: parent.height * 0.18
                color: Qt.rgba(root.backgroundColor.r, root.backgroundColor.g,
                               root.backgroundColor.b, 0.9)
            }

            Behavior on x {
                enabled: !root.reducedMotion
                NumberAnimation { duration: 260; easing.type: Easing.InOutCubic }
            }
            Behavior on color { ColorAnimation { duration: 180 } }
        }

        SequentialAnimation on scale {
            running: root.checking && !root.reducedMotion
            loops: Animation.Infinite
            NumberAnimation { to: 1.05; duration: 520; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1; duration: 520; easing.type: Easing.InOutSine }
        }

        SequentialAnimation on scale {
            running: root.success && !root.reducedMotion
            NumberAnimation { to: 1.12; duration: 120; easing.type: Easing.OutCubic }
            NumberAnimation { to: 1; duration: 220; easing.type: Easing.OutBack }
        }
    }

    Shape {
        width: 24
        height: 24
        anchors.centerIn: parent
        scale: root.width / 24
        transformOrigin: Item.Center
        visible: root.blinking || root.unavailable
        antialiasing: true
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: "transparent"
            strokeColor: root.statusColor
            strokeWidth: 2
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg {
                path: "M15 18l-.722-3.25 M2 8a10.645 10.645 0 0 0 20 0 M20 15l-1.726-2.05 M4 15l1.726-2.05 M9 18l.722-3.25"
            }
        }
    }

    Timer {
        id: glanceTimer
        interval: 620
        repeat: true
        onTriggered: {
            const sequence = [-1, 0, 1, 0]
            root.glanceIndex = sequence[root.glanceStep]
            root.glanceStep = (root.glanceStep + 1) % sequence.length
        }
    }

    Timer {
        id: blinkTimer
        interval: 3300
        repeat: false
        onTriggered: {
            if (!root.searching || root.gazeDirection !== "auto" || root.reducedMotion)
                return
            root.blinking = true
            blinkClose.restart()
        }
    }

    Timer {
        id: blinkClose
        interval: 125
        repeat: false
        onTriggered: {
            root.blinking = false
            if (root.searching && root.gazeDirection === "auto" && !root.reducedMotion)
                blinkTimer.restart()
        }
    }
}
