// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Shapes
import qs.Commons

Item {
    id: indicator
    width: 220
    height: 250
    property string displayState: "checking"
    property string successText: "UNLOCKED"
    property string unauthorizedText: "LOCKED"
    property color textColor: Color.lock.text
    property color accentColor: Color.lock.borderActive
    property color waitingAccentColor: Color.accent
    property bool statusVisible: true
    property string verifyingWord: "VERIFYING"
    property real verifyingWordOpacity: 0.9

    readonly property bool checking: displayState === "checking"
    readonly property bool waking: displayState === "waking"
    readonly property bool sleeping: displayState === "sleeping"
    readonly property bool unauthorized: displayState === "unauthorized"
    readonly property bool success: displayState === "success"
    readonly property color lockedColor: Util.alpha(textColor, 0.58)
    readonly property color unlockedColor: accentColor
    readonly property color checkingColor: accentColor
    readonly property color waitingColor: waitingAccentColor
    readonly property color sleepingColor: Util.alpha(textColor, 0.32)
    readonly property color activeColor: success ? unlockedColor
        : unauthorized ? lockedColor
        : sleeping ? sleepingColor
        : checking || waking ? checkingColor : waitingColor
    property int sweepIndex: 0
    property int glanceIndex: 0
    property int glanceStep: 0
    property bool blinking: false

    Repeater {
        model: 72

        delegate: Item {
            required property int index
            x: 14
            y: 4
            width: 192
            height: 192
            rotation: index * 5

            Rectangle {
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                width: 2
                height: indicator.success
                    ? 9 : indicator.unauthorized ? 8 : 7
                radius: 1
                color: indicator.activeColor
                opacity: {
                    if (indicator.success) return 0.8
                    if (indicator.unauthorized) return 0.72
                    if (indicator.sleeping) return 0.09
                    if (!indicator.checking) return 0.2
                    const distance = (index - indicator.sweepIndex + 72) % 72
                    return distance < 10 ? 0.92 - distance * 0.075 : 0.13
                }
                Behavior on color { ColorAnimation { duration: 180 } }
                Behavior on opacity { NumberAnimation { duration: 120 } }
            }
        }
    }

    Rectangle {
        x: 28
        y: 18
        width: 164
        height: 164
        radius: 82
        color: "transparent"
        border.width: 1
        border.color: indicator.activeColor
        opacity: indicator.success ? 0 : 0.32
        Behavior on opacity { NumberAnimation { duration: 180 } }
        Behavior on border.color { ColorAnimation { duration: 180 } }
    }

    Item {
        id: faceAvatar
        width: 76
        height: 76
        x: 72 + indicator.glanceIndex * 3
        y: 62
        opacity: indicator.success
            ? 0 : indicator.sleeping ? 0.42 : 1
        scale: indicator.checking ? 1.05 : 1

        Behavior on x { NumberAnimation { duration: 420; easing.type: Easing.InOutCubic } }
        Behavior on opacity { NumberAnimation { duration: 160 } }
        Behavior on scale { NumberAnimation { duration: 360; easing.type: Easing.InOutSine } }

        Shape {
            anchors.fill: parent
            antialiasing: true
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                fillColor: "transparent"
                strokeColor: indicator.activeColor
                strokeWidth: 4
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg {
                    path: "M22 5H14C9 5 5 9 5 14V22 M54 5H62C67 5 71 9 71 14V22 M71 54V62C71 67 67 71 62 71H54 M22 71H14C9 71 5 67 5 62V54"
                }
            }

            ShapePath {
                fillColor: "transparent"
                strokeColor: indicator.activeColor
                strokeWidth: 3.5
                capStyle: ShapePath.RoundCap
                PathSvg {
                    path: indicator.unauthorized
                        ? "M25 55C31 48 45 48 51 55"
                        : "M25 48C31 55 45 55 51 48"
                }
            }
        }

        Rectangle {
            x: 23 + indicator.glanceIndex * 2
            y: 28
            width: 5
            height: indicator.blinking ? 2 : 7
            radius: 3
            color: indicator.activeColor
            Behavior on x { NumberAnimation { duration: 300 } }
        }

        Rectangle {
            x: 48 + indicator.glanceIndex * 2
            y: 28
            width: 5
            height: indicator.blinking ? 2 : 7
            radius: 3
            color: indicator.activeColor
            Behavior on x { NumberAnimation { duration: 300 } }
        }
    }

    Item {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 56
        width: 86
        height: 86
        opacity: indicator.success ? 1 : 0
        scale: indicator.success ? 1 : 0.72

        Behavior on opacity { NumberAnimation { duration: 220 } }
        Behavior on scale { NumberAnimation { duration: 420; easing.type: Easing.OutBack } }

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Util.alpha(indicator.unlockedColor, 0.12)
            border.width: 2
            border.color: indicator.unlockedColor
        }

        Shape {
            anchors.fill: parent
            antialiasing: true
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: "transparent"
                strokeColor: indicator.unlockedColor
                strokeWidth: 6
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg { path: "M24 44L37 57L64 28" }
            }
        }
    }

    Text {
        visible: indicator.statusVisible
        anchors.horizontalCenter: parent.horizontalCenter
        y: 212
        text: indicator.success ? indicator.successText
            : indicator.unauthorized ? indicator.unauthorizedText
            : indicator.sleeping ? "STANDBY"
            : indicator.waking ? "WAKING"
            : indicator.checking ? indicator.verifyingWord : "LOOK AT THE CAMERA"
        color: indicator.unauthorized ? indicator.lockedColor
            : indicator.success ? indicator.unlockedColor
            : indicator.sleeping ? indicator.sleepingColor
            : indicator.checking || indicator.waking
                ? indicator.checkingColor : indicator.textColor
        font.family: Style.font.family
        font.pixelSize: Math.max(16, Style.font.caption + 3)
        font.bold: true
        font.letterSpacing: 1.8
        opacity: indicator.checking ? indicator.verifyingWordOpacity
            : indicator.sleeping ? 0.58 : 0.9
    }

    Timer {
        interval: 46
        running: indicator.visible && indicator.checking
        repeat: true
        onTriggered: indicator.sweepIndex = (indicator.sweepIndex + 1) % 72
    }

    Timer {
        interval: 860
        running: indicator.visible && !indicator.success
            && !indicator.sleeping
        repeat: true
        onTriggered: {
            const sequence = [-1, 0, 1, 0]
            indicator.glanceIndex = sequence[indicator.glanceStep]
            indicator.glanceStep = (indicator.glanceStep + 1) % sequence.length
        }
    }

    Timer {
        id: blinkTimer
        interval: 2800
        running: indicator.visible && !indicator.success
            && !indicator.sleeping
        repeat: true
        onTriggered: {
            indicator.blinking = true
            blinkClose.restart()
        }
    }

    Timer {
        id: blinkClose
        interval: 120
        repeat: false
        onTriggered: indicator.blinking = false
    }
}
