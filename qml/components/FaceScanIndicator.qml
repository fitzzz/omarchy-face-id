// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Shapes

Item {
    id: root

    property string state: "idle" // idle | checking | success | unavailable
    property string direction: "auto" // auto | left | center | right
    property real progress: 0
    property bool reducedMotion: false
    property bool showAvatar: true
    property color primaryColor: "#65d1a7"
    property color checkingColor: "#f59e0b"
    property color mutedColor: "#748078"
    property color backgroundColor: "#101916"

    readonly property bool checking: state === "checking"
    readonly property bool success: state === "success"
    readonly property bool unavailable: state === "unavailable"
    readonly property color activeColor: checking ? checkingColor
        : unavailable ? mutedColor : primaryColor
    readonly property real boundedProgress: Math.max(0, Math.min(1, progress))
    readonly property int segmentCount: 72
    readonly property int filledSegments: success ? segmentCount
        : checking ? Math.round(boundedProgress * segmentCount) : 0
    readonly property int directedIndex: direction === "left" ? -1
        : direction === "right" ? 1 : 0

    property int glanceIndex: 0
    property int glanceStep: 0
    property int sweepIndex: 0
    property bool blinking: false

    function resetAvatarMotion() {
        glanceIndex = 0
        glanceStep = 0
        blinking = false
        if (!reducedMotion && !success && direction === "auto") {
            glanceTimer.restart()
            blinkTimer.restart()
        } else {
            glanceTimer.stop()
            blinkTimer.stop()
            blinkClose.stop()
        }
    }

    width: 240
    height: width
    opacity: unavailable ? 0.58 : 1

    onStateChanged: resetAvatarMotion()
    onDirectionChanged: resetAvatarMotion()
    onReducedMotionChanged: resetAvatarMotion()
    Component.onCompleted: resetAvatarMotion()

    Repeater {
        model: root.segmentCount

        delegate: Item {
            required property int index
            anchors.centerIn: parent
            width: root.width
            height: root.height
            rotation: index * (360 / root.segmentCount)

            Rectangle {
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.max(1.5, root.width * 0.008)
                height: root.width * 0.045
                radius: width / 2
                color: root.activeColor
                opacity: {
                    if (root.success) return 0.82
                    if (root.checking && index < root.filledSegments) return 0.94
                    if (root.checking) {
                        const distance = (index - root.sweepIndex + root.segmentCount)
                            % root.segmentCount
                        return distance < 7 ? 0.68 - distance * 0.075 : 0.16
                    }
                    return 0.26
                }
                Behavior on opacity { NumberAnimation { duration: 180 } }
                Behavior on color { ColorAnimation { duration: 180 } }
            }
        }
    }

    Rectangle {
        anchors.centerIn: parent
        width: root.width * 0.72
        height: width
        radius: width / 2
        color: "transparent"
        border.width: Math.max(1, root.width * 0.005)
        border.color: root.activeColor
        opacity: root.success ? 0 : 0.34
        scale: root.checking && !root.reducedMotion ? 1.015 : 1
        Behavior on opacity { NumberAnimation { duration: 160 } }
        Behavior on scale { NumberAnimation { duration: 420; easing.type: Easing.InOutSine } }
    }

    Item {
        id: avatar
        anchors.centerIn: parent
        width: root.width * 0.31
        height: width
        visible: root.showAvatar
        opacity: root.success ? 0 : 1
        x: (root.width - width) / 2
            + (root.direction === "auto" ? root.glanceIndex : root.directedIndex)
                * root.width * 0.022
        scale: root.checking && !root.reducedMotion ? 1.04 : 1

        Behavior on x {
            enabled: !root.reducedMotion
            NumberAnimation { duration: 420; easing.type: Easing.InOutCubic }
        }
        Behavior on opacity { NumberAnimation { duration: 150 } }
        Behavior on scale { NumberAnimation { duration: 360; easing.type: Easing.InOutSine } }

        Shape {
            width: 24
            height: 24
            anchors.centerIn: parent
            scale: avatar.width / 24
            transformOrigin: Item.Center
            antialiasing: true
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                fillColor: "transparent"
                strokeColor: root.activeColor
                strokeWidth: 1.8
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg {
                    path: "M7 2H5a3 3 0 0 0-3 3v2 M17 2h2a3 3 0 0 1 3 3v2 M22 17v2a3 3 0 0 1-3 3h-2 M7 22H5a3 3 0 0 1-3-3v-2"
                }
            }
        }

        Item {
            anchors.centerIn: parent
            width: parent.width * 0.62
            height: parent.height * 0.62
            readonly property real eyeShift: (root.direction === "auto"
                ? root.glanceIndex : root.directedIndex) * width * 0.055

            Rectangle {
                x: parent.width * 0.22 + parent.eyeShift
                y: parent.height * 0.30
                width: parent.width * 0.075
                height: root.blinking ? 1.5 : width * 1.35
                radius: width / 2
                color: root.activeColor
                Behavior on x { NumberAnimation { duration: 300 } }
            }
            Rectangle {
                x: parent.width * 0.70 + parent.eyeShift
                y: parent.height * 0.30
                width: parent.width * 0.075
                height: root.blinking ? 1.5 : width * 1.35
                radius: width / 2
                color: root.activeColor
                Behavior on x { NumberAnimation { duration: 300 } }
            }

            Shape {
                width: 24
                height: 24
                anchors.centerIn: parent
                scale: parent.width / 24
                transformOrigin: Item.Center
                antialiasing: true
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: "transparent"
                    strokeColor: root.activeColor
                    strokeWidth: 1.55
                    capStyle: ShapePath.RoundCap
                    PathSvg { path: "M6.5 14.5c2.7 2.4 8.3 2.4 11 0" }
                }
            }
        }
    }

    Item {
        id: successMark
        anchors.centerIn: parent
        width: root.width * 0.34
        height: width
        opacity: root.success ? 1 : 0
        scale: root.success ? 1 : 0.72

        Behavior on opacity { NumberAnimation { duration: 220 } }
        Behavior on scale {
            NumberAnimation { duration: 420; easing.type: Easing.OutBack }
        }

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Qt.rgba(root.primaryColor.r, root.primaryColor.g,
                           root.primaryColor.b, 0.08)
            border.width: 2
            border.color: root.primaryColor
        }

        Shape {
            width: 24
            height: 24
            anchors.centerIn: parent
            scale: successMark.width / 24
            transformOrigin: Item.Center
            antialiasing: true
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: "transparent"
                strokeColor: root.primaryColor
                strokeWidth: 2.2
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg { path: "M7 12.5l3.2 3.2L17.5 8" }
            }
        }
    }

    Timer {
        id: sweepTimer
        interval: 46
        running: root.checking && !root.reducedMotion
        repeat: true
        onTriggered: root.sweepIndex = (root.sweepIndex + 1) % root.segmentCount
    }

    Timer {
        id: glanceTimer
        interval: 860
        repeat: true
        onTriggered: {
            const sequence = [-1, 0, 1, 0]
            root.glanceIndex = sequence[root.glanceStep]
            root.glanceStep = (root.glanceStep + 1) % sequence.length
        }
    }

    Timer {
        id: blinkTimer
        interval: 2800
        repeat: false
        onTriggered: {
            if (root.reducedMotion || root.success) return
            root.blinking = true
            blinkClose.restart()
        }
    }

    Timer {
        id: blinkClose
        interval: 120
        repeat: false
        onTriggered: {
            root.blinking = false
            if (!root.reducedMotion && !root.success && root.direction === "auto")
                blinkTimer.restart()
        }
    }
}
