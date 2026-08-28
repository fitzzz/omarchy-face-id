// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtQuick.Shapes

Button {
    id: control

    property bool primary: false
    property color accentColor: "#65d1a7"
    property color textColor: primary ? "#10201a" : "#d5ddd8"
    property color surfaceColor: "#18241f"
    property color hoverColor: "#24322d"
    property color borderColor: "#476258"
    property color disabledTextColor: "#66706b"
    property bool forwardIcon: false
    property bool quiet: false
    readonly property color contentColor: !enabled ? disabledTextColor
        : quiet ? (hovered ? textColor : disabledTextColor) : textColor

    implicitWidth: Math.max(quiet ? 88 : 132,
                            contentItem.implicitWidth + (quiet ? 24 : 40))
    implicitHeight: 44
    leftPadding: 20
    rightPadding: 20
    font.family: "monospace"
    font.pixelSize: 14
    font.weight: Font.DemiBold

    HoverHandler {
        cursorShape: control.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    }

    contentItem: Item {
        implicitWidth: contentRow.implicitWidth
        implicitHeight: Math.max(buttonText.implicitHeight, 22)

        Row {
            id: contentRow
            anchors.centerIn: parent
            spacing: control.forwardIcon ? 9 : 0

            Text {
                id: buttonText
                anchors.verticalCenter: parent.verticalCenter
                text: control.text
                color: control.contentColor
                font: control.font
            }

            Item {
                width: control.forwardIcon ? 24 : 0
                height: 22
                visible: control.forwardIcon

                Shape {
                    width: 22
                    height: 22
                    x: control.hovered && control.enabled ? 2 : 0
                    antialiasing: true
                    preferredRendererType: Shape.CurveRenderer

                    Behavior on x {
                        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                    }

                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: control.contentColor
                        strokeWidth: 1.5
                        capStyle: ShapePath.RoundCap
                        joinStyle: ShapePath.RoundJoin
                        PathSvg {
                            path: "M17.25 8.25L21 12M21 12L17.25 15.75M21 12H3"
                        }
                    }
                }
            }
        }
    }

    background: Rectangle {
        radius: 7
        color: control.quiet
            ? (control.hovered ? control.hoverColor : "transparent")
            : control.primary
            ? (control.down ? Qt.darker(control.accentColor, 1.14) : control.accentColor)
            : (control.hovered ? control.hoverColor : control.surfaceColor)
        border.width: control.primary || control.quiet ? 0 : 1
        border.color: control.borderColor

        Behavior on color { ColorAnimation { duration: 120 } }
    }
}
