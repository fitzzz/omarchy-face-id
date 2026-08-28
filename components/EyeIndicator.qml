import QtQuick
import QtQuick.Shapes

// Lucide-derived eye with a separately animated pupil. The outline stays
// stable while the pupil glances around, so activity reads at lock-screen size
// without looking like several unrelated icons swapping in place.
Item {
    id: root

    property string state: "searching" // searching | checking | success | unavailable
    property bool reducedMotion: false
    property real iconSize: 56
    property color neutralColor: "#cacccc"
    property color checkingColor: "#f59e0b"
    property color successColor: "#22c55e"
    property color unavailableColor: "#707880"
    property color backgroundColor: "#101315"
    readonly property bool searching: state === "searching"
    readonly property bool checking: state === "checking"
    readonly property bool success: state === "success"
    readonly property bool unavailable: state === "unavailable"
    readonly property color statusColor: checking ? checkingColor : success ? successColor : unavailable ? unavailableColor : neutralColor
    readonly property real pupilTravel: width * 0.105
    property int glanceIndex: 0
    property int glanceStep: 0
    property bool blinking: false

    function resetMotion() {
        glanceIndex = 0;
        glanceStep = 0;
        blinking = false;
        openEye.scale = 1;
        blinkClose.stop();
        if (!searching || reducedMotion)
            glanceTimer.stop();
        else
            glanceTimer.start();
        if (!searching || reducedMotion)
            blinkTimer.stop();
        else
            blinkTimer.restart();
    }

    width: iconSize
    height: iconSize
    opacity: unavailable ? 0.64 : 1
    onStateChanged: resetMotion()
    onReducedMotionChanged: resetMotion()
    Component.onCompleted: resetMotion()

    Rectangle {
        anchors.centerIn: parent
        width: root.width * 0.88
        height: root.height * 0.66
        radius: width / 2
        color: Qt.rgba(root.statusColor.r, root.statusColor.g, root.statusColor.b, root.checking ? 0.13 : root.success ? 0.16 : 0.06)
        opacity: root.unavailable ? 0 : 1

        Behavior on color {
            ColorAnimation {
                duration: 180
            }

        }

    }

    Item {
        id: openEye

        anchors.fill: parent
        visible: !root.blinking && !root.unavailable

        Shape {
            id: outline

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
            id: pupil

            width: root.width * 0.205
            height: width
            radius: width / 2
            y: (parent.height - height) / 2
            x: (parent.width - width) / 2 + (root.searching && !root.reducedMotion ? root.glanceIndex * root.pupilTravel : 0)
            color: root.statusColor

            Rectangle {
                width: parent.width * 0.24
                height: width
                radius: width / 2
                x: parent.width * 0.23
                y: parent.height * 0.18
                color: Qt.rgba(root.backgroundColor.r, root.backgroundColor.g, root.backgroundColor.b, 0.9)
            }

            Behavior on x {
                enabled: !root.reducedMotion

                NumberAnimation {
                    duration: 260
                    easing.type: Easing.InOutCubic
                }

            }

            Behavior on color {
                ColorAnimation {
                    duration: 180
                }

            }

        }

        SequentialAnimation on scale {
            running: root.checking && !root.reducedMotion
            loops: Animation.Infinite

            NumberAnimation {
                to: 1.05
                duration: 520
                easing.type: Easing.InOutSine
            }

            NumberAnimation {
                to: 1
                duration: 520
                easing.type: Easing.InOutSine
            }

        }

        SequentialAnimation on scale {
            id: successSettle

            running: root.success && !root.reducedMotion

            NumberAnimation {
                to: 1.12
                duration: 120
                easing.type: Easing.OutCubic
            }

            NumberAnimation {
                to: 1
                duration: 220
                easing.type: Easing.OutBack
            }

        }

    }

    Shape {
        id: closedEye

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
            var sequence = [-1, 0, 1, 0];
            root.glanceIndex = sequence[root.glanceStep];
            root.glanceStep = (root.glanceStep + 1) % sequence.length;
        }
    }

    Timer {
        id: blinkTimer

        interval: 3300
        repeat: false
        onTriggered: {
            if (!root.searching || root.reducedMotion)
                return ;

            root.blinking = true;
            blinkClose.restart();
        }
    }

    Timer {
        id: blinkClose

        interval: 125
        repeat: false
        onTriggered: {
            root.blinking = false;
            if (root.searching && !root.reducedMotion)
                blinkTimer.restart();

        }
    }

}
