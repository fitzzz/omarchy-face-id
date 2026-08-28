import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "components"
import qs.Commons
import qs.Ui

// Unlocked visual playground. It simulates states only; it never opens a
// camera, invokes PAM, or calls the lock service.
Item {
    id: root

    property var shell: null
    property var manifest: null
    property bool opened: false
    property bool autoPlay: true
    property bool reducedMotion: false
    property int stateIndex: 0
    readonly property var states: ["searching", "checking", "success", "unavailable"]
    readonly property string previewState: states[stateIndex]
    readonly property string statusText: previewState === "searching" ? "Looking for you..." : previewState === "checking" ? "Checking face..." : previewState === "success" ? "Face verified" : "Face unlock unavailable — use password"
    readonly property string detailText: previewState === "searching" ? "The password field remains ready." : previewState === "checking" ? "Local liveness and face match are in progress." : previewState === "success" ? "Only PAM success may unlock the session." : "Any failure returns to the existing password path."

    function setState(next) {
        var index = states.indexOf(String(next || ""));
        if (index !== -1)
            stateIndex = index;

    }

    function open(payloadJson) {
        var payload = {
        };
        try {
            payload = JSON.parse(payloadJson || "{}") || {
            };
        } catch (e) {
        }
        autoPlay = payload.mode !== "manual";
        reducedMotion = payload.reducedMotion === true;
        if (payload.state)
            setState(payload.state);
        else
            stateIndex = 0;
        opened = true;
        if (autoPlay)
            stateTimer.restart();

        Qt.callLater(function() {
            keyCatcher.forceActiveFocus();
        });
    }

    function close() {
        stateTimer.stop();
        opened = false;
    }

    function dismiss() {
        if (shell && typeof shell.hide === "function")
            shell.hide((manifest && manifest.id) || "fitzzz.face-unlock");
        else
            close();
    }

    function step(delta) {
        autoPlay = false;
        stateTimer.stop();
        stateIndex = (stateIndex + delta + states.length) % states.length;
    }

    PanelWindow {
        id: panel

        visible: root.opened
        color: "transparent"
        WlrLayershell.namespace: "fitzzz-face-unlock-preview"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        exclusionMode: ExclusionMode.Ignore

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        Rectangle {
            anchors.fill: parent
            color: Color.menu.scrim
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.dismiss()
        }

        BorderSurface {
            id: card

            width: Math.min(Style.space(460), panel.width - Style.gapsOut * 2)
            height: Math.min(Style.space(330), panel.height - Style.gapsOut * 2)
            anchors.centerIn: parent
            radius: Style.cornerRadius
            color: Color.lock.background
            borderSpec: Border.surfaceSpec("lock", "border", Color.lock.border, Math.max(1, Style.space(2)), "border-alpha")
            padding: Style.spacing.panelPadding

            MouseArea {
                anchors.fill: parent
                onClicked: {
                }
            }

            Item {
                id: keyCatcher

                anchors.fill: parent
                focus: true
                Keys.priority: Keys.BeforeItem
                Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Escape) {
                        root.dismiss();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Left || event.key === Qt.Key_H) {
                        root.step(-1);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Right || event.key === Qt.Key_L) {
                        root.step(1);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Space) {
                        root.autoPlay = !root.autoPlay;
                        if (root.autoPlay)
                            stateTimer.restart();
                        else
                            stateTimer.stop();
                        event.accepted = true;
                    }
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.topMargin: card.contentTopInset
                anchors.rightMargin: card.contentRightInset
                anchors.bottomMargin: card.contentBottomInset
                anchors.leftMargin: card.contentLeftInset
                spacing: Style.spacing.lg

                Text {
                    Layout.fillWidth: true
                    text: "Face unlock preview"
                    color: Color.lock.text
                    font.family: Style.font.family
                    font.pixelSize: Style.font.title
                    font.weight: Font.DemiBold
                    horizontalAlignment: Text.AlignHCenter
                }

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Style.space(96)

                    EyeIndicator {
                        anchors.centerIn: parent
                        state: root.previewState
                        reducedMotion: root.reducedMotion
                        iconSize: Style.space(72)
                        neutralColor: Color.lock.text
                        unavailableColor: Color.muted
                        backgroundColor: Color.lock.background
                    }

                }

                Text {
                    Layout.fillWidth: true
                    text: root.statusText
                    color: Color.lock.text
                    font.family: Style.font.family
                    font.pixelSize: Style.font.heading
                    font.weight: Font.Medium
                    horizontalAlignment: Text.AlignHCenter
                }

                Text {
                    Layout.fillWidth: true
                    text: root.detailText
                    color: Color.lock.placeholder
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: Style.spacing.sm

                    Repeater {
                        model: root.states

                        Rectangle {
                            required property string modelData
                            required property int index

                            width: Style.space(72)
                            height: Style.spacing.controlHeight
                            radius: Style.cornerRadius
                            color: index === root.stateIndex ? Style.selectedFillFor(Color.lock.text, Color.lock.borderActive) : Style.normalFillFor(Color.lock.text, Color.lock.borderActive)

                            Text {
                                anchors.centerIn: parent
                                text: parent.modelData
                                color: Color.lock.text
                                font.family: Style.font.family
                                font.pixelSize: Style.font.caption
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.autoPlay = false;
                                    stateTimer.stop();
                                    root.stateIndex = index;
                                }
                            }

                        }

                    }

                }

                Text {
                    Layout.fillWidth: true
                    text: "←/→ change state   Space toggles autoplay   Esc closes"
                    color: Color.muted
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    horizontalAlignment: Text.AlignHCenter
                }

            }

        }

    }

    Timer {
        id: stateTimer

        interval: root.previewState === "searching" ? 3600 : root.previewState === "checking" ? 2200 : 1400
        repeat: false
        onTriggered: {
            root.stateIndex = (root.stateIndex + 1) % root.states.length;
            if (root.opened && root.autoPlay)
                restart();

        }
    }

}
