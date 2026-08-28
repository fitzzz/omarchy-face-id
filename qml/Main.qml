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
    title: "Omarchy Face ID"
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

    property int currentStep: Qt.application.arguments.indexOf("--done-page-test") >= 0 ? 3
        : Qt.application.arguments.indexOf("--camera-page-test") >= 0 ? 2 : 0
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
            return "Video is processed locally and is never saved."
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
                scanCompleteTimer.restart()
        }
    }

    Timer {
        id: scanCompleteTimer
        interval: 900
        repeat: false
        onTriggered: root.currentStep = 3
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
                            text: "FACE ID"
                            color: root.textColor
                            font.family: "monospace"
                            font.pixelSize: 16
                            font.weight: Font.Bold
                        }
                        OmarchyWordmark {
                            Layout.preferredWidth: 76
                            Layout.preferredHeight: 18
                            markColor: root.mutedColor
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

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48

                    Text {
                        anchors.fill: parent
                        text: "Your password always works."
                        color: root.textColor
                        opacity: 0.82
                        font.family: "monospace"
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                        verticalAlignment: Text.AlignVCenter
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
                        FaceScanIndicator {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: 172
                            Layout.preferredHeight: 172
                            state: "idle"
                            primaryColor: root.accentColor
                            checkingColor: root.amberColor
                            mutedColor: root.mutedColor
                            backgroundColor: root.backgroundColor
                        }
                        Text {
                            Layout.fillWidth: true
                            text: "Setup Face ID"
                            color: root.textColor
                            font.family: "monospace"
                            font.pixelSize: 34
                            font.weight: Font.DemiBold
                            horizontalAlignment: Text.AlignHCenter
                        }
                        Text {
                            Layout.maximumWidth: 520
                            Layout.alignment: Qt.AlignHCenter
                            text: "Unlock your computer with a glance. Face matching and liveness checks happen locally; your biometric data never leaves this computer."
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

                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 8
                                FaceScanIndicator {
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.preferredWidth: 196
                                    Layout.preferredHeight: 196
                                    state: root.gazeReady ? "idle" : "unavailable"
                                    backgroundColor: root.surfaceColor
                                    primaryColor: root.accentColor
                                    checkingColor: root.amberColor
                                    mutedColor: root.mutedColor
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

                            FaceScanIndicator {
                                anchors.centerIn: parent
                                width: Math.min(parent.width * 0.58, 350)
                                height: width
                                state: gazeClient.enrollmentComplete ? "success"
                                    : root.scanFailed ? "unavailable" : "checking"
                                direction: root.activePose
                                progress: root.activeProgress / root.activeMaximum
                                showAvatar: gazeClient.previewDataUrl.length === 0
                                backgroundColor: root.surfaceColor
                                primaryColor: root.successColor
                                checkingColor: root.amberColor
                                mutedColor: root.scanFailed ? root.errorColor : root.mutedColor
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
                        FaceScanIndicator {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: 164
                            Layout.preferredHeight: 164
                            state: "success"
                            backgroundColor: root.backgroundColor
                            primaryColor: root.successColor
                            checkingColor: root.amberColor
                            mutedColor: root.mutedColor
                        }
                        Text {
                            Layout.fillWidth: true
                            text: gazeClient.lockIntegrationInstalled
                                ? "Omarchy Face ID Is Ready" : "Face Scan Complete"
                            color: root.textColor
                            font.family: "monospace"
                            font.pixelSize: 34
                            font.weight: Font.DemiBold
                            horizontalAlignment: Text.AlignHCenter
                        }
                        Text {
                            Layout.maximumWidth: 520
                            Layout.alignment: Qt.AlignHCenter
                            text: gazeClient.lockIntegrationInstalled
                                ? "Lock your computer and look directly at the camera."
                                : "Authorize one final system change to enable Face ID on the lock screen."
                            color: root.textColor
                            opacity: 0.78
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
                                text: gazeClient.lockIntegrationInstalling
                                    ? "Authorizing…"
                                    : gazeClient.lockIntegrationInstalled
                                        ? "Done" : "Enable Face ID"
                                primary: true
                                enabled: !gazeClient.lockIntegrationInstalling
                                onClicked: {
                                    if (gazeClient.lockIntegrationInstalled)
                                        root.close()
                                    else
                                        gazeClient.enableLockIntegration()
                                }
                            }
                        }
                        Text {
                            Layout.maximumWidth: 520
                            Layout.alignment: Qt.AlignHCenter
                            visible: gazeClient.lockIntegrationError.length > 0
                            text: gazeClient.lockIntegrationError
                            color: root.errorColor
                            font.family: "monospace"
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                            horizontalAlignment: Text.AlignHCenter
                        }
                        Item { Layout.fillHeight: true }
                    }
                }
            }
        }
    }
}
