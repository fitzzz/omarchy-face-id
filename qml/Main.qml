// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia
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

    readonly property color backgroundColor: "#0d1513"
    readonly property color sidebarColor: "#101b17"
    readonly property color surfaceColor: "#14211c"
    readonly property color raisedColor: "#192821"
    readonly property color borderColor: "#355046"
    readonly property color textColor: "#d5ddd8"
    readonly property color mutedColor: "#79877f"
    readonly property color accentColor: "#65d1a7"
    readonly property color amberColor: "#f59e0b"
    readonly property var stepNames: ["Welcome", "Camera", "Gaze", "Enroll", "Finish"]

    property int currentStep: 0
    property bool enrollmentStarted: false
    property bool realEnrollment: false
    property bool demoFinished: false
    property int demoProgress: 0
    property string demoPrompt: "Face the camera"
    property string demoPose: "center"
    readonly property var demoPrompts: [
        { text: "Face the camera", pose: "center" },
        { text: "Tilt your face slightly up", pose: "center" },
        { text: "Tilt your face slightly down", pose: "center" },
        { text: "Turn your face slightly left", pose: "left" },
        { text: "Turn your face slightly right", pose: "right" }
    ]
    readonly property bool cameraPresent: mediaDevices.videoInputs.length > 0
    readonly property bool gazeReady: gazeClient.serviceAvailable
        && gazeClient.cameraAvailable
    readonly property bool localPreviewActive: currentStep === 1
        || (currentStep === 3 && (!enrollmentStarted || !realEnrollment))
    readonly property string activePrompt: realEnrollment
        ? friendlyPrompt(gazeClient.enrollmentPrompt) : demoPrompt
    readonly property int activeProgress: realEnrollment
        ? gazeClient.enrollmentProgress : demoProgress
    readonly property int activeMaximum: realEnrollment
        ? Math.max(1, gazeClient.enrollmentMaximum) : demoPrompts.length
    readonly property string activePose: realEnrollment
        ? poseForPrompt(gazeClient.enrollmentPrompt) : demoPose

    function friendlyPrompt(prompt) {
        const labels = {
            "look-straight": "Face the camera",
            "look-up": "Tilt your face slightly up",
            "look-down": "Tilt your face slightly down",
            "look-left": "Turn your face slightly left",
            "look-right": "Turn your face slightly right",
            "captured": "Captured — hold position",
            "completed": "Enrollment complete",
            "camera-failed": "The camera stopped responding",
            "db-failed": "Gaze could not save the face profile",
            "cancelled": "Enrollment cancelled"
        }
        return labels[String(prompt)] || String(prompt || "Hold still")
    }

    function poseForPrompt(prompt) {
        const value = String(prompt)
        if (value.indexOf("left") !== -1)
            return "left"
        if (value.indexOf("right") !== -1)
            return "right"
        return "center"
    }

    function startEnrollment() {
        enrollmentStarted = true
        demoFinished = false
        realEnrollment = root.gazeReady
        if (realEnrollment) {
            beginGazeTimer.restart()
        } else {
            demoProgress = 0
            demoPrompt = demoPrompts[0].text
            demoPose = demoPrompts[0].pose
            demoTimer.restart()
        }
    }

    function cancelEnrollment() {
        demoTimer.stop()
        beginGazeTimer.stop()
        if (realEnrollment)
            gazeClient.cancelEnrollment()
        enrollmentStarted = false
        demoProgress = 0
        demoPrompt = demoPrompts[0].text
        demoPose = demoPrompts[0].pose
    }

    onClosing: cancelEnrollment()

    MediaDevices { id: mediaDevices }

    Camera {
        id: camera
        active: root.localPreviewActive && root.cameraPresent
        cameraDevice: cameraSelector.currentIndex >= 0
            && cameraSelector.currentIndex < mediaDevices.videoInputs.length
            ? mediaDevices.videoInputs[cameraSelector.currentIndex]
            : mediaDevices.defaultVideoInput
    }

    CaptureSession {
        camera: camera
        videoOutput: root.currentStep === 1 ? cameraOutput : enrollmentCameraOutput
    }

    Timer {
        id: beginGazeTimer
        interval: 450
        repeat: false
        onTriggered: gazeClient.beginEnrollment("default")
    }

    Timer {
        id: demoTimer
        interval: 1650
        repeat: true
        onTriggered: {
            demoProgress += 1
            if (demoProgress >= demoPrompts.length) {
                stop()
                demoFinished = true
                currentStep = 4
                return
            }
            demoPrompt = demoPrompts[demoProgress].text
            demoPose = demoPrompts[demoProgress].pose
        }
    }

    Connections {
        target: gazeClient
        function onEnrollmentChanged() {
            if (root.realEnrollment && gazeClient.enrollmentComplete) {
                root.demoFinished = false
                root.currentStep = 4
            }
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
            font.pixelSize: 28
            font.weight: Font.DemiBold
        }
        Text {
            Layout.fillWidth: true
            text: parent.description
            color: root.mutedColor
            font.family: "monospace"
            font.pixelSize: 14
            lineHeight: 1.35
            wrapMode: Text.WordWrap
        }
    }

    component StatusRow: Rectangle {
        property string label: ""
        property string detail: ""
        property bool ok: false
        property bool warning: false

        implicitHeight: 64
        radius: 7
        color: root.raisedColor
        border.width: 1
        border.color: root.borderColor

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            spacing: 14

            Rectangle {
                width: 10
                height: 10
                radius: 5
                color: parent.parent.ok ? root.accentColor
                    : parent.parent.warning ? root.amberColor : "#d16d6d"
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3
                Text {
                    text: parent.parent.parent.label
                    color: root.textColor
                    font.family: "monospace"
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                }
                Text {
                    Layout.fillWidth: true
                    text: parent.parent.parent.detail
                    color: root.mutedColor
                    font.family: "monospace"
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 278
            color: root.sidebarColor
            border.width: 0

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 30
                spacing: 28

                RowLayout {
                    spacing: 12
                    EyeIndicator {
                        iconSize: 40
                        state: root.currentStep === 4 ? "success" : "searching"
                        backgroundColor: root.sidebarColor
                        neutralColor: root.accentColor
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
                    Layout.preferredHeight: 84
                    radius: 7
                    color: "#15231d"
                    border.width: 1
                    border.color: root.borderColor

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 5
                        Text {
                            text: "PASSWORD FALLBACK"
                            color: root.accentColor
                            font.family: "monospace"
                            font.pixelSize: 10
                            font.weight: Font.Bold
                        }
                        Text {
                            Layout.fillWidth: true
                            text: "This app never removes or replaces your password."
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
                id: pages
                anchors.fill: parent
                anchors.leftMargin: 54
                anchors.rightMargin: 54
                anchors.topMargin: 42
                anchors.bottomMargin: 38
                currentIndex: root.currentStep

                Item {
                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 24

                        Item { Layout.fillHeight: true }
                        EyeIndicator {
                            Layout.alignment: Qt.AlignHCenter
                            iconSize: 112
                            state: "searching"
                            neutralColor: root.amberColor
                            backgroundColor: root.backgroundColor
                        }
                        Text {
                            Layout.fillWidth: true
                            text: "Set up face unlock"
                            color: root.textColor
                            font.family: "monospace"
                            font.pixelSize: 32
                            font.weight: Font.DemiBold
                            horizontalAlignment: Text.AlignHCenter
                        }
                        Text {
                            Layout.maximumWidth: 560
                            Layout.alignment: Qt.AlignHCenter
                            text: "Check your webcam, connect to Gaze, and capture five guided angles. Everything stays on this computer."
                            color: root.mutedColor
                            font.family: "monospace"
                            font.pixelSize: 15
                            lineHeight: 1.4
                            wrapMode: Text.WordWrap
                            horizontalAlignment: Text.AlignHCenter
                        }
                        Rectangle {
                            Layout.maximumWidth: 560
                            Layout.fillWidth: true
                            Layout.preferredHeight: 68
                            Layout.alignment: Qt.AlignHCenter
                            radius: 7
                            color: root.surfaceColor
                            border.width: 1
                            border.color: root.borderColor
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 15
                                spacing: 12
                                Text {
                                    text: "✓"
                                    color: root.accentColor
                                    font.pixelSize: 18
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: "Opening this app does not enable face authentication or change PAM."
                                    color: root.textColor
                                    font.family: "monospace"
                                    font.pixelSize: 12
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }
                        ActionButton {
                            Layout.alignment: Qt.AlignHCenter
                            text: "Begin setup"
                            primary: true
                            accentColor: root.accentColor
                            onClicked: root.currentStep = 1
                        }
                        Item { Layout.fillHeight: true }
                    }
                }

                Item {
                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 20

                        PageTitle {
                            Layout.fillWidth: true
                            eyebrow: "STEP 1 OF 4"
                            title: "Check your camera"
                            description: "Center your face and make sure the image is clear. The preview is never saved."
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.minimumHeight: 330
                            radius: 10
                            color: "#080d0b"
                            border.width: 2
                            border.color: root.cameraPresent ? root.accentColor : "#71484a"
                            clip: true

                            VideoOutput {
                                id: cameraOutput
                                anchors.fill: parent
                                visible: root.cameraPresent
                                fillMode: VideoOutput.PreserveAspectCrop
                            }

                            ColumnLayout {
                                anchors.centerIn: parent
                                visible: !root.cameraPresent
                                spacing: 12
                                EyeIndicator {
                                    Layout.alignment: Qt.AlignHCenter
                                    state: "unavailable"
                                    backgroundColor: "#080d0b"
                                }
                                Text {
                                    text: "No camera found"
                                    color: root.textColor
                                    font.family: "monospace"
                                    font.pixelSize: 16
                                }
                            }

                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: 50
                                color: "#cc0d1513"
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 14
                                    anchors.rightMargin: 14
                                    Text {
                                        text: root.cameraPresent ? "● LIVE — NOT RECORDING" : "CAMERA UNAVAILABLE"
                                        color: root.cameraPresent ? root.accentColor : "#d16d6d"
                                        font.family: "monospace"
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                    }
                                    Item { Layout.fillWidth: true }
                                    ComboBox {
                                        id: cameraSelector
                                        Layout.preferredWidth: 300
                                        model: mediaDevices.videoInputs
                                        textRole: "description"
                                        enabled: root.cameraPresent
                                    }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            ActionButton { text: "Back"; onClicked: root.currentStep = 0 }
                            Item { Layout.fillWidth: true }
                            ActionButton {
                                text: "Camera looks good"
                                primary: true
                                enabled: root.cameraPresent
                                accentColor: root.accentColor
                                onClicked: {
                                    gazeClient.refresh()
                                    root.currentStep = 2
                                }
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
                            eyebrow: "STEP 2 OF 4"
                            title: "Check Gaze"
                            description: "Gaze handles local face recognition and liveness. The portable app talks to its system service when it is installed."
                        }

                        StatusRow {
                            Layout.fillWidth: true
                            label: "Webcam"
                            detail: root.cameraPresent ? "A local video input is available" : "No webcam is available"
                            ok: root.cameraPresent
                        }
                        StatusRow {
                            Layout.fillWidth: true
                            label: "Gaze command"
                            detail: gazeClient.installed ? "/usr/bin/gaze is installed" : "Not installed — preview mode remains available"
                            ok: gazeClient.installed
                            warning: !gazeClient.installed
                        }
                        StatusRow {
                            Layout.fillWidth: true
                            label: "Gaze service"
                            detail: !gazeClient.serviceAvailable
                                ? "Not running — no face data can be saved yet"
                                : gazeClient.cameraAvailable
                                    ? "Connected and able to use a camera"
                                    : "Connected, but Gaze cannot access a camera"
                            ok: root.gazeReady
                            warning: !root.gazeReady
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 96
                            radius: 7
                            color: root.surfaceColor
                            border.width: 1
                            border.color: root.gazeReady ? root.borderColor : "#725b2f"
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 16
                                spacing: 14
                                Text {
                                    text: root.gazeReady ? "✓" : "!"
                                    color: root.gazeReady ? root.accentColor : root.amberColor
                                    font.family: "monospace"
                                    font.pixelSize: 22
                                    font.weight: Font.Bold
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: root.gazeReady
                                        ? "Ready for a real enrollment. Face embeddings will be managed locally by Gaze."
                                        : "You can continue through a camera-based preview. It will demonstrate every pose without saving or enabling anything."
                                    color: root.textColor
                                    font.family: "monospace"
                                    font.pixelSize: 12
                                    lineHeight: 1.35
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: gazeClient.errorMessage.length > 0
                            text: gazeClient.errorMessage
                            color: "#d98989"
                            font.family: "monospace"
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                        }

                        Item { Layout.fillHeight: true }

                        RowLayout {
                            Layout.fillWidth: true
                            ActionButton { text: "Back"; onClicked: root.currentStep = 1 }
                            ActionButton {
                                text: "Recheck"
                                onClicked: gazeClient.refresh()
                            }
                            Item { Layout.fillWidth: true }
                            ActionButton {
                                text: root.gazeReady ? "Continue" : "Preview walkthrough"
                                primary: true
                                accentColor: root.accentColor
                                enabled: root.cameraPresent
                                onClicked: root.currentStep = 3
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
                            title: enrollmentStarted ? root.activePrompt : "Capture five angles"
                            description: enrollmentStarted
                                ? (realEnrollment ? "Follow the prompt and move only slightly. Gaze captures automatically."
                                                  : "Preview mode is demonstrating the guided sequence. No face data is being saved.")
                                : "Keep your shoulders still and make small, comfortable movements when prompted."
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.minimumHeight: 330
                            radius: 10
                            color: "#080d0b"
                            border.width: 2
                            border.color: enrollmentStarted ? root.amberColor : root.accentColor
                            clip: true

                            VideoOutput {
                                id: enrollmentCameraOutput
                                anchors.fill: parent
                                visible: root.localPreviewActive && root.cameraPresent
                                fillMode: VideoOutput.PreserveAspectCrop
                            }

                            Image {
                                anchors.fill: parent
                                visible: realEnrollment && gazeClient.previewDataUrl.length > 0
                                source: gazeClient.previewDataUrl
                                fillMode: Image.PreserveAspectCrop
                                cache: false
                            }

                            Rectangle {
                                anchors.centerIn: parent
                                width: Math.min(parent.width * 0.54, 300)
                                height: Math.min(parent.height * 0.78, 330)
                                radius: width / 2
                                color: "transparent"
                                border.width: 2
                                border.color: enrollmentStarted ? root.amberColor : root.accentColor
                                opacity: 0.85
                            }

                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 20
                                width: Math.min(parent.width - 40, 430)
                                height: 78
                                radius: 9
                                color: "#e8111c18"
                                border.width: 1
                                border.color: root.borderColor
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 14
                                    EyeIndicator {
                                        iconSize: 50
                                        state: enrollmentStarted ? "checking" : "searching"
                                        gazeDirection: enrollmentStarted ? root.activePose : "auto"
                                        backgroundColor: "#111c18"
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 4
                                        Text {
                                            Layout.fillWidth: true
                                            text: enrollmentStarted ? root.activePrompt : "Ready when you are"
                                            color: root.textColor
                                            font.family: "monospace"
                                            font.pixelSize: 13
                                            font.weight: Font.DemiBold
                                            elide: Text.ElideRight
                                        }
                                        ProgressBar {
                                            Layout.fillWidth: true
                                            from: 0
                                            to: root.activeMaximum
                                            value: root.activeProgress
                                        }
                                        Text {
                                            text: root.activeProgress + " of " + root.activeMaximum + " angles"
                                            color: root.mutedColor
                                            font.family: "monospace"
                                            font.pixelSize: 10
                                        }
                                    }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            ActionButton {
                                text: enrollmentStarted ? "Cancel" : "Back"
                                onClicked: {
                                    if (enrollmentStarted)
                                        root.cancelEnrollment()
                                    else
                                        root.currentStep = 2
                                }
                            }
                            Item { Layout.fillWidth: true }
                            ActionButton {
                                visible: !enrollmentStarted
                                text: root.gazeReady ? "Start enrollment" : "Start preview"
                                primary: true
                                accentColor: root.accentColor
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
                            iconSize: 112
                            state: realEnrollment && gazeClient.enrollmentComplete ? "success" : "checking"
                            backgroundColor: root.backgroundColor
                        }
                        Text {
                            Layout.fillWidth: true
                            text: realEnrollment && gazeClient.enrollmentComplete
                                ? "Face enrolled" : "Walkthrough complete"
                            color: root.textColor
                            font.family: "monospace"
                            font.pixelSize: 30
                            font.weight: Font.DemiBold
                            horizontalAlignment: Text.AlignHCenter
                        }
                        Text {
                            Layout.maximumWidth: 570
                            Layout.alignment: Qt.AlignHCenter
                            text: realEnrollment && gazeClient.enrollmentComplete
                                ? "Gaze saved the face profile locally. Face unlocking is still disabled until the separate system integration passes its safety checks."
                                : "You completed the guided preview. No biometric data was saved, and system authentication was not changed."
                            color: root.mutedColor
                            font.family: "monospace"
                            font.pixelSize: 14
                            lineHeight: 1.4
                            wrapMode: Text.WordWrap
                            horizontalAlignment: Text.AlignHCenter
                        }
                        Rectangle {
                            Layout.maximumWidth: 570
                            Layout.fillWidth: true
                            Layout.preferredHeight: 76
                            Layout.alignment: Qt.AlignHCenter
                            radius: 7
                            color: root.surfaceColor
                            border.width: 1
                            border.color: root.borderColor
                            Text {
                                anchors.fill: parent
                                anchors.margins: 15
                                text: "Next: install Gaze without automatic PAM changes, test authentication, then add the isolated Omarchy lock service."
                                color: root.textColor
                                font.family: "monospace"
                                font.pixelSize: 12
                                lineHeight: 1.35
                                wrapMode: Text.WordWrap
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 12
                            ActionButton {
                                text: "Run again"
                                onClicked: {
                                    root.cancelEnrollment()
                                    root.currentStep = 1
                                }
                            }
                            ActionButton {
                                text: "Done"
                                primary: true
                                accentColor: root.accentColor
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
