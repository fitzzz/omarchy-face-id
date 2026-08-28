// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Layouts

Item {
    id: root

    property int currentStep: 0
    property var steps: []
    property color accentColor: "#65d1a7"
    property color textColor: "#d5ddd8"
    property color mutedColor: "#748078"

    implicitWidth: 220

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Repeater {
            model: root.steps

            Item {
                id: row

                required property string modelData
                required property int index
                Layout.fillWidth: true
                Layout.preferredHeight: 66

                Rectangle {
                    x: 17
                    y: 38
                    width: 1
                    height: 30
                    visible: row.index < root.steps.length - 1
                    color: row.index < root.currentStep ? root.accentColor : "#34413b"
                }

                Rectangle {
                    x: 4
                    y: 10
                    width: 28
                    height: 28
                    radius: 14
                    color: row.index < root.currentStep
                        ? root.accentColor
                        : row.index === root.currentStep ? "#203a30" : "#18231f"
                    border.width: row.index === root.currentStep ? 2 : 1
                    border.color: row.index <= root.currentStep ? root.accentColor : "#3a4741"

                    Text {
                        anchors.centerIn: parent
                        text: row.index < root.currentStep ? "✓" : String(row.index + 1)
                        color: row.index < root.currentStep ? "#10201a"
                            : row.index === root.currentStep ? root.accentColor : root.mutedColor
                        font.family: "monospace"
                        font.pixelSize: 12
                        font.weight: Font.Bold
                    }
                }

                Text {
                    x: 48
                    y: 14
                    width: row.width - x
                    text: row.modelData
                    color: row.index === root.currentStep ? root.textColor : root.mutedColor
                    font.family: "monospace"
                    font.pixelSize: 14
                    font.weight: row.index === root.currentStep ? Font.DemiBold : Font.Normal
                }
            }
        }

        Item { Layout.fillHeight: true }
    }
}
