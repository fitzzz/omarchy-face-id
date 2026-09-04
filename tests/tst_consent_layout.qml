// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtTest

TestCase {
    id: testCase

    name: "ConsentLayout"

    property QtObject consentBridge: QtObject {
        property string phase: "deciding"

        function respond(response) {}
        function cancel() {}
        function dismiss() {}
    }

    property QtObject theme: QtObject {
        property color polkitBackground: "#111c18"
        property color polkitText: "#c1c497"
        property color polkitBorder: "#509475"
        property color polkitAccent: "#509475"
        property color muted: "#53685b"
        property color controlSurface: "#17241f"
        property color controlHover: "#23372b"
        property color controlBorder: "#509475"
        property string fontFamily: "monospace"
        property int fontCaption: 12
        property int fontBody: 14
        property int fontTitle: 20
        property int panelGap: 12
        property int panelPadding: 24
        property int controlGap: 14
        property int controlPaddingX: 18
        property int controlPaddingY: 10
        property int controlHeight: 44
    }

    Component {
        id: promptComponent

        ConsentPrompt {
            visible: false
        }
    }

    function test_face_indicator_does_not_move_between_phases() {
        const prompt = createTemporaryObject(promptComponent, null)
        verify(prompt !== null)
        wait(0)
        const initialTop = prompt.faceIndicatorTop
        compare(prompt.avatarCopyGap, prompt.copyActionsGap)
        compare(prompt.approveButtonCenter, prompt.approveShortcutCenter)
        compare(prompt.declineButtonCenter, prompt.declineShortcutCenter)
        compare(prompt.approveShortcutLabel, "Hotkey A")
        compare(prompt.declineShortcutLabel, "Hotkey D")
        compare(prompt.approveButtonHeight, 44)
        compare(prompt.declineButtonHeight, 44)
        compare(prompt.approveHoverEnabled, true)
        compare(prompt.shortcutLegendVisible, false)
        prompt.shortcutsEnabled = true
        compare(prompt.shortcutLegendVisible, true)

        const phases = ["checking", "success", "fallback", "deciding"]
        for (const phase of phases) {
            consentBridge.phase = phase
            wait(0)
            compare(prompt.faceIndicatorTop, initialTop)
        }
    }

}
