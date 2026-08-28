// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "components"

ApplicationWindow {
    id: root

    width: 1040
    height: 700
    minimumWidth: 900
    minimumHeight: 620
    visible: true
    title: "Omarchy Face Unlock"
    color: backgroundColor

    readonly property color backgroundColor: gazeClient.themeDarkerBackground
    readonly property color sidebarColor: gazeClient.themeDarkBackground
    readonly property color surfaceColor: gazeClient.themeBackground
    readonly property color raisedColor: gazeClient.themeLighterBackground
    readonly property color borderColor: gazeClient.themeMuted
    readonly property color textColor: gazeClient.themeForeground
    readonly property color mutedColor: gazeClient.themeMuted
    readonly property color accentColor: gazeClient.themeAccent
    readonly property color amberColor: gazeClient.themeOrange
    readonly property color successColor: gazeClient.themeGreen
    readonly property color errorColor: gazeClient.themeRed
    readonly property var stepNames: ["Welcome", "Ready", "Scan", "Done"]

    property int currentStep: Qt.application.arguments.indexOf("--camera-page-test") >= 0 ? 2 : 0
    property bool enrollmentStarted: false
    readonly property string activePrompt: friendlyPrompt(gazeClient.enrollmentPrompt)
    readonly property int activeProgress: gazeClient.enrollmentProgress
    readonly property int activeMaximum: Math.max(1, gazeClient.enrollmentMaximum)
    readonly property string activePose: poseForPrompt(gazeClient.enrollmentPrompt)
    readonly property bool scanFailed: enrollmentStarted
        && !beginGazeTimer.running
        && !gazeClient.enrolling
        && !gazeClient.enrollmentComplete
        && ["camera-failed", "db-failed", "cancelled"].indexOf(gazeClient.enrollmentPrompt) >= 0
    readonly property bool gazeReady: gazeClient.installed
        && gazeClient.serviceAvailable
        && gazeClient.cameraAvailable

    function friendlyPrompt(prompt) {
        const labels = {
            "look-straight": "Look straight ahead",
            "look-up": "Look up slightly",
            "look-down": "Look down slightly",
            "look-left": "Turn slightly left",
            "look-right": "Turn slightly right",
            "captured": "Perfect. Hold still.",
            "completed": "Scan complete",
            "camera-failed": "Camera connection lost",
            "db-failed": "Your face scan could not be saved",
            "cancelled": "Scan cancelled"
        }
        return labels[String(prompt)] || String(prompt || "Preparing camera…")
    }

    function poseForPrompt(prompt) {
        const value = String(prompt)
        if (value.indexOf("left") !== -1)
            return "left"
        if (value.indexOf("right") !== -1)
            return "right"
        return "center"
    }

    function readinessTitle() {
        if (gazeReady)
            return "Camera Ready"
        if (!gazeClient.installed)
            return "Setup Required"
        if (!gazeClient.serviceAvailable)
            return "Face Scanning Is Offline"
        return "Camera Unavailable"
    }

    function readinessDetail() {
        if (gazeReady)
            return "Your face scan stays on this computer."
        if (!gazeClient.installed)
            return "Install the face-scanning service, then check again."
        if (!gazeClient.serviceAvailable)
            return "Start the face-scanning service, then check again."
        return "Close other camera apps, then check again."
    }

    function startEnrollment() {
        gazeClient.refresh()
        if (!gazeReady)
            return
        currentStep = 2
        enrollmentStarted = true
        beginGazeTimer.restart()
    }

    function cancelEnrollment() {
        beginGazeTimer.stop()
        if (gazeClient.enrolling)
            gazeClient.cancelEnrollment()
        enrollmentStarted = false
        if (currentStep === 2)
            currentStep = 1
    }

    onClosing: {
        if (gazeClient.enrolling)
            gazeClient.cancelEnrollment()
    }

    Timer {
        id: beginGazeTimer
        interval: 240
        repeat: false
        onTriggered: gazeClient.beginEnrollment("default")
    }

    Connections {
        target: gazeClient
        function onEnrollmentChanged() {
            if (gazeClient.enrollmentComplete)
                root.currentStep = 3
        }
    }

    component PageTitle: ColumnLayout {
        property string eyebrow: "SETUP"
        property string title: ""
        property string description: ""
        spacing: 8

        Text {
            text: parent.eyebrow
            color: root.accentColor
            font.family: "monospace"
            font.pixelSize: 11
            font.letterSpacing: 1.4
            font.weight: Font.Bold
        }
        Text {
            Layout.fillWidth: true
            text: parent.title
            color: root.textColor
            font.family: "monospace"
            font.pixelSize: 30
            font.weight: Font.DemiBold
        }
        Text {
            Layout.fillWidth: true
            text: parent.description
            color: root.mutedColor
            font.family: "monospace"
            font.pixelSize: 14
            lineHeight: 1.4
            wrapMode: Text.WordWrap
        }
    }

    component ThemedActionButton: ActionButton {
        accentColor: root.accentColor
        textColor: primary ? root.backgroundColor : root.textColor
        surfaceColor: root.surfaceColor
        hoverColor: root.raisedColor
        borderColor: root.borderColor
        disabledTextColor: root.mutedColor
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 268
            color: root.sidebarColor

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 30
                spacing: 28

                RowLayout {
                    spacing: 12
                    EyeIndicator {
                        iconSize: 40
                        state: root.currentStep === 3 ? "success" : "searching"
                        backgroundColor: root.sidebarColor
                        neutralColor: root.accentColor
                        successColor: root.successColor
                    }
                    ColumnLayout {
                        spacing: 1
                        Text {
                            text: "FACE UNLOCK"
                            color: root.textColor
                            font.family: "monospace"
                            font.pixelSize: 16
                            font.weight: Font.Bold
                        }
                        Text {
                            text: "FOR OMARCHY"
                            color: root.mutedColor
                            font.family: "monospace"
                            font.pixelSize: 10
                            font.letterSpacing: 1.1
                        }
                    }
                }

                StepRail {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    currentStep: root.currentStep
                    steps: root.stepNames
                    accentColor: root.accentColor
                    textColor: root.textColor
                    mutedColor: root.mutedColor
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 82
                    radius: 8
                    color: "transparent"
                    border.width: 1
                    border.color: root.borderColor

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 5
                        Text {
                            text: "PASSWORD BACKUP"
                            color: root.accentColor
                            font.family: "monospace"
                            font.pixelSize: 10
                            font.weight: Font.Bold
                        }
                        Text {
                            Layout.fillWidth: true
                            text: "You can always unlock with your password."
                            color: root.mutedColor
                            font.family: "monospace"
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: root.backgroundColor

            StackLayout {
                anchors.fill: parent
                anchors.leftMargin: 56
                anchors.rightMargin: 56
                anchors.topMargin: 42
                anchors.bottomMargin: 38
                currentIndex: root.currentStep

                Item {
                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 22

                        Item { Layout.fillHeight: true }
                        EyeIndicator {
                            Layout.alignment: Qt.AlignHCenter
                            iconSize: 122
                            state: "searching"
                            neutralColor: root.accentColor
                            backgroundColor: root.backgroundColor
                        }
                        Text {
                            Layout.fillWidth: true
                            text: "Setup Face Unlock"
                            color: root.textColor
                            font.family: "monospace"
                            font.pixelSize: 34
                            font.weight: Font.DemiBold
                            horizontalAlignment: Text.AlignHCenter
                        }
                        Text {
                            Layout.maximumWidth: 520
                            Layout.alignment: Qt.AlignHCenter
                            text: "Unlock your computer with a glance. Your face stays on this computer."
                            color: root.mutedColor
                            font.family: "monospace"
                            font.pixelSize: 15
                            lineHeight: 1.45
                            wrapMode: Text.WordWrap
                            horizontalAlignment: Text.AlignHCenter
                        }
                        ThemedActionButton {
                            Layout.alignment: Qt.AlignHCenter
                            text: "Get Started"
                            primary: true
                            onClicked: {
                                gazeClient.refresh()
                                root.currentStep = 1
                            }
                        }
                        Item { Layout.fillHeight: true }
                    }
                }

                Item {
                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 22

                        PageTitle {
                            Layout.fillWidth: true
                            eyebrow: "STEP 2 OF 4"
                            title: "Ready when you are"
                            description: "Keep your face uncovered and look directly at the camera."
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.minimumHeight: 330
                            radius: 12
                            color: root.surfaceColor
                            border.width: 1
                            border.color: root.gazeReady ? root.accentColor : root.errorColor

                            Rectangle {
                                anchors.centerIn: parent
                                width: 238
                                height: 238
                                radius: 119
                                color: "transparent"
                                border.width: 1
                                border.color: root.gazeReady ? root.accentColor : root.mutedColor
                                opacity: 0.6

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 188
                                    height: 188
                                    radius: 94
                                    color: Qt.rgba(root.accentColor.r, root.accentColor.g,
                                                   root.accentColor.b, 0.05)
                                    border.width: 1
                                    border.color: root.borderColor
                                }
                            }

                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 12
                                EyeIndicator {
                                    Layout.alignment: Qt.AlignHCenter
                                    iconSize: 82
                                    state: root.gazeReady ? "success" : "unavailable"
                                    backgroundColor: root.surfaceColor
                                    neutralColor: root.accentColor
                                    successColor: root.successColor
                                    unavailableColor: root.mutedColor
                                }
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: root.readinessTitle()
                                    color: root.textColor
                                    font.family: "monospace"
                                    font.pixelSize: 20
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    Layout.maximumWidth: 360
                                    Layout.alignment: Qt.AlignHCenter
                                    text: root.readinessDetail()
                                    color: root.mutedColor
                                    font.family: "monospace"
                                    font.pixelSize: 12
                                    wrapMode: Text.WordWrap
                                    horizontalAlignment: Text.AlignHCenter
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            ThemedActionButton {
                                text: "Back"
                                onClicked: root.currentStep = 0
                            }
                            ThemedActionButton {
                                text: "Check Again"
                                visible: !root.gazeReady
                                onClicked: gazeClient.refresh()
                            }
                            Item { Layout.fillWidth: true }
                            ThemedActionButton {
                                text: "Authorize and Scan Face"
                                primary: true
                                enabled: root.gazeReady
                                onClicked: root.startEnrollment()
                            }
                        }
                    }
                }

                Item {
                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 18

                        PageTitle {
                            Layout.fillWidth: true
                            eyebrow: "STEP 3 OF 4"
                            title: root.activePrompt
                            description: root.scanFailed
                                ? "Check the camera and try again."
                                : "Move slowly and keep your face inside the ring."
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.minimumHeight: 390
                            radius: 12
                            color: root.surfaceColor
                            border.width: 1
                            border.color: root.scanFailed ? root.errorColor
                                : gazeClient.enrolling ? root.amberColor : root.accentColor
                            clip: true

                            Image {
                                anchors.fill: parent
                                visible: gazeClient.previewDataUrl.length > 0
                                source: gazeClient.previewDataUrl
                                fillMode: Image.PreserveAspectCrop
                                cache: false
                            }

                            Rectangle {
                                anchors.fill: parent
                                color: Qt.rgba(root.backgroundColor.r, root.backgroundColor.g,
                                               root.backgroundColor.b,
                                               gazeClient.previewDataUrl.length > 0 ? 0.16 : 0)
                            }

                            Item {
                                id: scanRing
                                anchors.centerIn: parent
                                width: Math.min(parent.width * 0.58, 350)
                                height: width
                                readonly property int segmentCount: 48
                                readonly property int filledSegments: gazeClient.enrollmentComplete
                                    ? segmentCount
                                    : Math.round((root.activeProgress / root.activeMaximum) * segmentCount)

                                Repeater {
                                    model: scanRing.segmentCount
                                    delegate: Item {
                                        required property int index
                                        anchors.centerIn: parent
                                        width: scanRing.width
                                        height: scanRing.height
                                        rotation: index * (360 / scanRing.segmentCount)

                                        Rectangle {
                                            anchors.top: parent.top
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            width: 3
                                            height: 13
                                            radius: 2
                                            color: index < scanRing.filledSegments
                                                ? root.accentColor : root.mutedColor
                                            opacity: index < scanRing.filledSegments ? 1 : 0.24
                                        }
                                    }
                                }

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: parent.width - 42
                                    height: width
                                    radius: width / 2
                                    color: "transparent"
                                    border.width: 1
                                    border.color: root.accentColor
                                    opacity: 0.72
                                }

                                EyeIndicator {
                                    anchors.centerIn: parent
                                    visible: gazeClient.previewDataUrl.length === 0
                                    iconSize: 96
                                    state: root.scanFailed ? "unavailable" : "checking"
                                    gazeDirection: root.activePose
                                    backgroundColor: root.surfaceColor
                                    checkingColor: root.amberColor
                                    unavailableColor: root.errorColor
                                }
                            }

                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 20
                                width: Math.min(parent.width - 48, 440)
                                height: 64
                                radius: 10
                                color: Qt.rgba(root.sidebarColor.r, root.sidebarColor.g,
                                               root.sidebarColor.b, 0.92)
                                border.width: 1
                                border.color: root.borderColor

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 7
                                    Text {
                                        Layout.fillWidth: true
                                        text: root.scanFailed ? root.activePrompt : "SCANNING"
                                        color: root.scanFailed ? root.errorColor : root.textColor
                                        font.family: "monospace"
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                        font.letterSpacing: 1.1
                                        horizontalAlignment: Text.AlignHCenter
                                    }
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 4
                                        radius: 2
                                        color: Qt.rgba(root.mutedColor.r, root.mutedColor.g,
                                                       root.mutedColor.b, 0.3)
                                        Rectangle {
                                            width: parent.width * Math.min(1, root.activeProgress / root.activeMaximum)
                                            height: parent.height
                                            radius: parent.radius
                                            color: root.accentColor
                                            Behavior on width { NumberAnimation { duration: 260 } }
                                        }
                                    }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            ThemedActionButton {
                                text: "Cancel"
                                onClicked: root.cancelEnrollment()
                            }
                            Item { Layout.fillWidth: true }
                            ThemedActionButton {
                                visible: root.scanFailed
                                text: "Try Again"
                                primary: true
                                onClicked: root.startEnrollment()
                            }
                        }
                    }
                }

                Item {
                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 22

                        Item { Layout.fillHeight: true }
                        EyeIndicator {
                            Layout.alignment: Qt.AlignHCenter
                            iconSize: 128
                            state: "success"
                            backgroundColor: root.backgroundColor
                            successColor: root.successColor
                        }
                        Text {
                            Layout.fillWidth: true
                            text: "Face Scan Complete"
                            color: root.textColor
                            font.family: "monospace"
                            font.pixelSize: 34
                            font.weight: Font.DemiBold
                            horizontalAlignment: Text.AlignHCenter
                        }
                        Text {
                            Layout.maximumWidth: 520
                            Layout.alignment: Qt.AlignHCenter
                            text: "Your face profile is saved locally on this computer."
                            color: root.mutedColor
                            font.family: "monospace"
                            font.pixelSize: 15
                            lineHeight: 1.45
                            wrapMode: Text.WordWrap
                            horizontalAlignment: Text.AlignHCenter
                        }
                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 12
                            ThemedActionButton {
                                text: "Scan Again"
                                onClicked: {
                                    root.enrollmentStarted = false
                                    root.currentStep = 1
                                }
                            }
                            ThemedActionButton {
                                text: "Done"
                                primary: true
                                onClicked: root.close()
                            }
                        }
                        Item { Layout.fillHeight: true }
                    }
                }
            }
        }
    }
}
