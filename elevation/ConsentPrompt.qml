// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Window

Window {
    id: root

    width: 560
    height: 500
    visible: true
    color: "transparent"
    flags: Qt.Tool | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
    modality: Qt.NonModal
    title: "Omarchy Face ID"

    property bool shortcutsEnabled: false
    readonly property string phase: consentBridge.phase
    readonly property real sectionGap: theme.panelGap * 2
    readonly property real stableContentHeight: 220
        + statusText.implicitHeight
        + detailText.implicitHeight
        + Math.max(decisionActions.implicitHeight, cancelAction.implicitHeight)
        + shortcutLegend.implicitHeight
        + theme.panelGap * 4
    readonly property real faceIndicatorTop: contentFrame.y + faceIndicator.y
    readonly property real avatarCopyGap: statusText.y
        - (faceIndicator.y + faceIndicator.height)
    readonly property real copyActionsGap: decisionActions.y
        - (detailText.y + detailText.height)
    readonly property real approveButtonCenter: contentFrame.x
        + decisionActions.x + approveAction.x + approveAction.width / 2
    readonly property real declineButtonCenter: contentFrame.x
        + decisionActions.x + declineAction.x + declineAction.width / 2
    readonly property real approveShortcutCenter: contentFrame.x
        + shortcutLegend.x + shortcutRow.x
        + approveShortcut.x + approveShortcut.width / 2
    readonly property real declineShortcutCenter: contentFrame.x
        + shortcutLegend.x + shortcutRow.x
        + declineShortcut.x + declineShortcut.width / 2
    readonly property string approveShortcutLabel: approveShortcut.text
    readonly property string declineShortcutLabel: declineShortcut.text
    readonly property real approveButtonHeight: approveAction.height
    readonly property real declineButtonHeight: declineAction.height
    readonly property bool approveHoverEnabled: approveAction.hoverEnabled
    readonly property bool shortcutLegendVisible: shortcutLegend.visible

    onClosing: close => {
        close.accepted = true
        consentBridge.dismiss()
    }

    Shortcut {
        sequence: "A"
        enabled: root.shortcutsEnabled && root.phase === "deciding"
        onActivated: consentBridge.respond("approve")
    }
    Shortcut {
        sequence: "D"
        enabled: root.shortcutsEnabled && root.phase === "deciding"
        onActivated: consentBridge.respond("deny")
    }
    Shortcut {
        sequence: "Escape"
        enabled: root.phase === "checking"
        onActivated: consentBridge.cancel()
    }

    Timer {
        interval: 1500
        running: root.phase === "deciding"
        onTriggered: root.shortcutsEnabled = true
    }

    Rectangle {
        anchors.fill: parent
        color: theme.polkitBackground
        radius: 8
        border.width: 1
        border.color: Qt.rgba(theme.polkitBorder.r,
                              theme.polkitBorder.g,
                              theme.polkitBorder.b,
                              theme.polkitBorder.a * 0.5)

        Item {
            id: contentFrame

            anchors.centerIn: parent
            width: Math.min(parent.width - theme.panelPadding * 2, 460)
            height: root.stableContentHeight

            FaceScanIndicator {
                id: faceIndicator

                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                width: 220
                height: width
                state: root.phase === "checking" ? "checking"
                    : root.phase === "success" ? "success"
                    : root.phase === "fallback" ? "unavailable" : "idle"
                progress: 0
                reducedMotion: false
                primaryColor: theme.polkitAccent
                checkingColor: theme.polkitAccent
                mutedColor: theme.muted
                backgroundColor: theme.polkitBackground
            }

            Text {
                id: statusText

                anchors.top: faceIndicator.bottom
                anchors.topMargin: root.sectionGap
                width: parent.width
                text: root.phase === "checking" ? "Look at the camera."
                    : root.phase === "success" ? "Approved."
                    : root.phase === "fallback" ? "Use your password."
                    : "An app requested sudo access"
                horizontalAlignment: Text.AlignHCenter
                color: theme.polkitText
                font.family: theme.fontFamily
                font.pixelSize: theme.fontTitle
                font.weight: Font.DemiBold
            }

            Text {
                id: detailText

                anchors.top: statusText.bottom
                anchors.topMargin: theme.panelGap
                width: parent.width
                text: root.phase === "fallback"
                    ? "Face ID couldn’t verify this request."
                    : "Review the command before approving."
                visible: root.phase === "deciding" || root.phase === "fallback"
                horizontalAlignment: Text.AlignHCenter
                color: theme.muted
                font.family: theme.fontFamily
                font.pixelSize: theme.fontBody
            }

            Row {
                id: decisionActions

                anchors.top: detailText.bottom
                anchors.topMargin: root.sectionGap
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: theme.controlGap
                visible: root.phase === "deciding"

                ActionButton {
                    id: approveAction

                    width: 220
                    text: "Approve with Face ID"
                    primary: true
                    accentColor: theme.polkitAccent
                    textColor: theme.polkitBackground
                    surfaceColor: theme.controlSurface
                    hoverColor: theme.controlHover
                    borderColor: theme.controlBorder
                    disabledTextColor: theme.muted
                    onClicked: consentBridge.respond("approve")
                }

                ActionButton {
                    id: declineAction

                    width: 150
                    text: "Decline"
                    accentColor: theme.polkitAccent
                    textColor: theme.polkitText
                    surfaceColor: theme.controlSurface
                    hoverColor: theme.controlHover
                    borderColor: theme.controlBorder
                    disabledTextColor: theme.muted
                    onClicked: consentBridge.respond("deny")
                }
            }

            ActionButton {
                id: cancelAction

                anchors.top: detailText.bottom
                anchors.topMargin: root.sectionGap
                anchors.horizontalCenter: parent.horizontalCenter
                width: 190
                visible: root.phase === "checking"
                text: "Cancel Request"
                accentColor: theme.polkitAccent
                textColor: theme.polkitText
                surfaceColor: theme.controlSurface
                hoverColor: theme.controlHover
                borderColor: theme.controlBorder
                disabledTextColor: theme.muted
                onClicked: consentBridge.cancel()
            }

            Item {
                id: shortcutLegend

                anchors.top: decisionActions.bottom
                anchors.topMargin: theme.panelGap
                anchors.horizontalCenter: parent.horizontalCenter
                width: decisionActions.width
                implicitHeight: shortcutRow.implicitHeight
                height: implicitHeight
                visible: root.phase === "deciding" && root.shortcutsEnabled

                Row {
                    id: shortcutRow

                    anchors.centerIn: parent
                    spacing: theme.controlGap

                    Text {
                        id: approveShortcut

                        width: approveAction.width
                        text: "Hotkey A"
                        horizontalAlignment: Text.AlignHCenter
                        color: theme.muted
                        font.family: theme.fontFamily
                        font.pixelSize: theme.fontCaption
                    }

                    Text {
                        id: declineShortcut

                        width: declineAction.width
                        text: "Hotkey D"
                        horizontalAlignment: Text.AlignHCenter
                        color: theme.muted
                        font.family: theme.fontFamily
                        font.pixelSize: theme.fontCaption
                    }
                }
            }
        }
    }
}
