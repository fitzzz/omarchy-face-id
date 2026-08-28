// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls

Button {
    id: control

    property bool primary: false
    property color accentColor: "#65d1a7"
    property color textColor: primary ? "#10201a" : "#d5ddd8"
    property color surfaceColor: "#18241f"
    property color hoverColor: "#24322d"
    property color borderColor: "#476258"
    property color disabledTextColor: "#66706b"

    implicitWidth: Math.max(132, contentItem.implicitWidth + 40)
    implicitHeight: 44
    leftPadding: 20
    rightPadding: 20
    font.family: "monospace"
    font.pixelSize: 14
    font.weight: Font.DemiBold

    HoverHandler {
        cursorShape: control.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    }

    contentItem: Text {
        text: control.text
        color: control.enabled ? control.textColor : control.disabledTextColor
        font: control.font
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    background: Rectangle {
        radius: 7
        color: control.primary
            ? (control.down ? Qt.darker(control.accentColor, 1.14) : control.accentColor)
            : (control.hovered ? control.hoverColor : control.surfaceColor)
        border.width: control.primary ? 0 : 1
        border.color: control.borderColor

        Behavior on color { ColorAnimation { duration: 120 } }
    }
}
