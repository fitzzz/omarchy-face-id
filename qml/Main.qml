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
    readonly property var stepNames: ["Welcome", "Prepare", "Scan", "Done"]
    readonly property int scanPageSpacing: 18
    readonly property int scanPanelMinimumHeight: 390

    property int currentStep: Qt.application.arguments.indexOf("--done-page-test") >= 0 ? 3
        : Qt.application.arguments.indexOf("--camera-page-test") >= 0 ? 2 : 0
    property bool enrollmentStarted: false
    property string displayedPrompt: "Preparing camera…"
    property string pendingPrompt: ""
    property real scanPromptOpacity: 1
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
        && gazeClient.cameraSupportAvailable
        && gazeClient.systemAuthenticationScoped
        && gazeClient.cameraAvailable

    function friendlyPrompt(prompt) {
        const labels = {
            "look-straight": "Look straight ahead.",
            "look-up": "Look up slightly.",
            "look-down": "Look down slightly.",
            "look-left": "Turn slightly left.",
            "look-right": "Turn slightly right.",
            "captured": "Perfect.",
            "completed": "Scan complete.",
            "camera-failed": "Camera connection lost.",
            "db-failed": "Your face scan could not be saved.",
            "cancelled": "Scan cancelled."
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
        if (gazeClient.faceSetupInstalling)
            return !gazeClient.installed ? "Installing Gaze Package…"
                : !gazeClient.cameraSupportAvailable
                    ? "Installing Camera Support…"
                    : !gazeClient.systemAuthenticationScoped
                        ? "Finishing Face ID Setup…" : "Starting Gaze Service…"
        if (gazeReady)
            return "Camera Ready"
        if (!gazeClient.installed)
            return "Install Gaze from AUR"
        if (!gazeClient.cameraSupportAvailable)
            return "Complete Camera Setup"
        if (!gazeClient.systemAuthenticationScoped)
            return "Finish Face ID Setup"
        if (!gazeClient.serviceAvailable)
            return "Face Scanning Is Offline"
        return "Camera Unavailable"
    }

    function readinessDetail() {
        if (gazeClient.faceSetupInstalling)
            return "Enter your system password in the installer. This page will continue automatically."
        if (gazeClient.faceSetupError.length > 0)
            return gazeClient.faceSetupError
        if (gazeReady)
            return "Video is processed locally and is never saved."
        if (!gazeClient.installed)
            return "Gaze powers facial authentication with local liveness anti-spoofing and support for infrared (IR) cameras for secure authentication."
        if (!gazeClient.cameraSupportAvailable)
            return "Face ID needs one camera format component. Setup installs it through Omarchy."
        if (!gazeClient.systemAuthenticationScoped)
            return "Keep Face ID limited to your lock screen, as intended."
        if (!gazeClient.serviceAvailable)
            return "Start the face-scanning service, then check again."
        return "Close other camera apps, then check again."
    }

    function startEnrollment() {
        gazeClient.refresh()
        if (!gazeReady)
            return
        promptTransition.stop()
        displayedPrompt = "Preparing camera…"
        pendingPrompt = ""
        scanPromptOpacity = 1
        currentStep = 2
        enrollmentStarted = true
        beginGazeTimer.restart()
    }

    function cancelEnrollment() {
        beginGazeTimer.stop()
        promptTransition.stop()
        if (gazeClient.enrolling)
            gazeClient.cancelEnrollment()
        enrollmentStarted = false
        if (currentStep === 2)
            currentStep = 1
    }

    function queueScanPrompt(prompt) {
        if (!enrollmentStarted || currentStep !== 2 || gazeClient.enrollmentComplete)
            return
        if (prompt === displayedPrompt && !promptTransition.running)
            return
        pendingPrompt = prompt
        promptTransition.restart()
    }

    onActivePromptChanged: queueScanPrompt(activePrompt)

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
            if (gazeClient.enrollmentComplete) {
                promptTransition.stop()
                root.displayedPrompt = "Scan complete."
                root.scanPromptOpacity = 1
                scanCompleteTimer.restart()
            }
        }
    }

    Timer {
        id: scanCompleteTimer
        interval: 900
        repeat: false
        onTriggered: root.currentStep = 3
    }

    SequentialAnimation {
        id: promptTransition
        NumberAnimation {
            target: root
            property: "scanPromptOpacity"
            to: 0
            duration: 150
            easing.type: Easing.InOutCubic
        }
        ScriptAction { script: root.displayedPrompt = root.pendingPrompt }
        NumberAnimation {
            target: root
            property: "scanPromptOpacity"
            to: 1
            duration: 220
            easing.type: Easing.OutCubic
        }
    }

    component PageTitle: ColumnLayout {
        property string title: ""
        property string description: ""
        property real titleOpacity: 1
        spacing: 8

        Text {
            Layout.fillWidth: true
            text: parent.title
            color: root.textColor
            opacity: parent.titleOpacity
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
                    Layout.preferredHeight: 64

                    Text {
                        anchors.fill: parent
                        text: "Face ID adds a faster way to unlock."
                        color: root.mutedColor
                        font.family: "monospace"
                        font.pixelSize: 13
                        lineHeight: 1.45
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
                            text: "Unlock your computer with a glance. Face matching and liveness checks happen locally. Your biometric data never leaves your computer."
                            color: root.mutedColor
                            font.family: "monospace"
                            font.pixelSize: 14
                            lineHeight: 1.45
                            wrapMode: Text.WordWrap
                            horizontalAlignment: Text.AlignHCenter
                        }
                        Item { Layout.fillHeight: true }
                        RowLayout {
                            Layout.fillWidth: true
                            Item { Layout.fillWidth: true }
                            ThemedActionButton {
                                text: "Get Started"
                                primary: true
                                forwardIcon: true
                                onClicked: {
                                    gazeClient.refresh()
                                    root.currentStep = 1
                                }
                            }
                        }
                    }
                }

                Item {
                    ColumnLayout {
                        id: prepareLayout
                        anchors.fill: parent
                        spacing: root.scanPageSpacing

                        PageTitle {
                            Layout.fillWidth: true
                            title: "Get ready for your scan"
                            description: "Keep your face uncovered and look directly at the camera."
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.minimumHeight: root.scanPanelMinimumHeight
                            radius: 12
                            color: root.surfaceColor
                            border.width: 1
                            border.color: root.accentColor

                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 8
                                FaceScanIndicator {
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.preferredWidth: 196
                                    Layout.preferredHeight: 196
                                    state: gazeClient.faceSetupInstalling
                                        ? "checking"
                                        : root.gazeReady ? "idle" : "unavailable"
                                    backgroundColor: root.surfaceColor
                                    primaryColor: root.accentColor
                                    checkingColor: root.amberColor
                                    mutedColor: root.mutedColor
                                }
                                Item {
                                    id: prepareTitleGap
                                    Layout.preferredHeight: 10
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
                                quiet: true
                                onClicked: root.currentStep = 0
                            }
                            Item { Layout.fillWidth: true }
                            ThemedActionButton {
                                text: "Check Again"
                                visible: gazeClient.installed
                                    && gazeClient.serviceAvailable
                                    && gazeClient.cameraSupportAvailable
                                    && !gazeClient.cameraAvailable
                                onClicked: gazeClient.refresh()
                            }
                            ThemedActionButton {
                                text: gazeClient.faceSetupInstalling
                                    ? "Installing…"
                                    : !gazeClient.installed ? "Install Gaze Package"
                                        : !gazeClient.cameraSupportAvailable
                                            ? "Install Camera Support"
                                            : !gazeClient.systemAuthenticationScoped
                                                ? "Finish Setup" : "Start Gaze Service"
                                visible: !gazeClient.installed
                                    || !gazeClient.cameraSupportAvailable
                                    || !gazeClient.systemAuthenticationScoped
                                    || !gazeClient.serviceAvailable
                                primary: true
                                enabled: !gazeClient.faceSetupInstalling
                                onClicked: gazeClient.installFaceSetup()
                            }
                            ThemedActionButton {
                                text: "Authorize and Scan Face"
                                primary: true
                                forwardIcon: true
                                visible: root.gazeReady
                                enabled: root.gazeReady
                                onClicked: root.startEnrollment()
                            }
                        }
                    }
                }

                Item {
                    ColumnLayout {
                        id: scanLayout
                        anchors.fill: parent
                        spacing: root.scanPageSpacing

                        PageTitle {
                            Layout.fillWidth: true
                            title: root.displayedPrompt
                            titleOpacity: root.scanPromptOpacity
                            description: root.scanFailed
                                ? "Please check the camera and try again."
                                : "Move slowly and keep your face inside the ring."
                        }

                        Rectangle {
                            id: scanSurface
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.minimumHeight: root.scanPanelMinimumHeight
                            radius: 12
                            color: root.surfaceColor
                            border.width: 1
                            border.color: root.scanFailed
                                ? root.errorColor : root.accentColor
                            clip: true

                            readonly property bool showingPreview:
                                gazeClient.previewDataUrl.length > 0

                            Image {
                                anchors.fill: parent
                                visible: gazeClient.previewDataUrl.length > 0
                                source: gazeClient.previewDataUrl
                                fillMode: Image.PreserveAspectCrop
                                mirror: true
                                cache: false
                                retainWhileLoading: true
                            }

                            Rectangle {
                                anchors.fill: parent
                                color: Qt.rgba(root.backgroundColor.r, root.backgroundColor.g,
                                               root.backgroundColor.b,
                                               scanSurface.showingPreview ? 0.16 : 0)
                            }

                            FaceScanIndicator {
                                anchors.centerIn: parent
                                width: Math.min(parent.width * 0.58, 350)
                                height: width
                                state: gazeClient.enrollmentComplete ? "success"
                                    : root.scanFailed ? "unavailable" : "checking"
                                direction: root.activePose
                                progress: root.activeProgress / root.activeMaximum
                                showAvatar: !scanSurface.showingPreview
                                backgroundColor: root.surfaceColor
                                primaryColor: root.successColor
                                checkingColor: root.accentColor
                                mutedColor: root.scanFailed ? root.errorColor : root.mutedColor
                            }

                        }

                        RowLayout {
                            Layout.fillWidth: true
                            ThemedActionButton {
                                text: "Back"
                                quiet: true
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
                                ? "Face ID is ready." : "Face scan complete."
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
                                ? "Try locking your computer.\nFace ID will appear after 3 seconds."
                                : "Approve the system prompt to add Face ID to the lock screen."
                            color: root.textColor
                            opacity: 0.78
                            font.family: "monospace"
                            font.pixelSize: 14
                            lineHeight: 1.45
                            wrapMode: Text.WordWrap
                            horizontalAlignment: Text.AlignHCenter
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
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12
                            Item { Layout.fillWidth: true }
                            ThemedActionButton {
                                visible: !gazeClient.lockIntegrationInstalled
                                text: "Scan Again"
                                onClicked: {
                                    root.enrollmentStarted = false
                                    root.currentStep = 1
                                }
                            }
                            ThemedActionButton {
                                text: gazeClient.lockIntegrationInstalling
                                    ? "Enabling Face ID…"
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
                    }
                }
            }
        }
    }
}
