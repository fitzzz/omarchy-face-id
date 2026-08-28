import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Wayland
import qs.Commons

// Adds face authentication beside Omarchy's existing password flow without
// replacing the first-party lock screen or changing its password PAM service.
Item {
    id: root

    property var shell: null
    property var manifest: null
    property var lockService: null
    property bool pamConfigured: false
    property bool authenticating: false
    property int lockGeneration: 0
    property int attemptGeneration: -1
    property string status: "unavailable"
    property bool overlayPreviewVisible: false
    property string overlayPreviewState: "checking"

    readonly property string overlayState: overlayPreviewVisible ? overlayPreviewState : status
    readonly property bool overlayVisible: overlayPreviewVisible || (lockService
        && compatible
        && lockService.locked
        && (status === "waiting" || status === "checking" || status === "success"))
    readonly property string aboveLockRule: 'hl.layer_rule({ name = "omarchy-face-id-above-lock", match = { namespace = "omarchy-face-id-overlay" }, above_lock = 1 })'

    readonly property string userName: Quickshell.env("USER") || Quickshell.env("LOGNAME")
    readonly property bool compatible: lockService
        && typeof lockService.finishUnlock === "function"
        && lockService.locked !== undefined
        && lockService.authenticatingPassword !== undefined

    function findLockService() {
        if (!shell || typeof shell.serviceFor !== "function") {
            lockService = null
            return
        }

        var next = shell.serviceFor("omarchy.lock")
        if (next !== lockService) lockService = next
    }

    function beginLockGeneration() {
        lockGeneration += 1
        retryTimer.stop()
        startTimer.stop()
        successUnlockTimer.stop()
        abortAttempt()
        ensureLayerRule()

        if (!compatible || !pamConfigured) {
            status = "unavailable"
            return
        }

        status = "waiting"
        startTimer.restart()
    }

    function endLockGeneration() {
        lockGeneration += 1
        retryTimer.stop()
        startTimer.stop()
        successUnlockTimer.stop()
        abortAttempt()
        status = compatible && pamConfigured ? "idle" : "unavailable"
    }

    function abortAttempt() {
        authenticating = false
        attemptGeneration = -1
        if (facePam.active) facePam.abort()
    }

    function startAttempt() {
        if (!lockService || !compatible || !pamConfigured || !lockService.locked) return
        if (lockService.authenticatingPassword || authenticating || facePam.active) return

        attemptGeneration = lockGeneration
        authenticating = true
        status = "checking"

        if (!facePam.start()) {
            authenticating = false
            attemptGeneration = -1
            scheduleRetry()
        }
    }

    function scheduleRetry() {
        if (!lockService || !compatible || !pamConfigured || !lockService.locked) return
        if (lockService.authenticatingPassword) return
        status = "waiting"
        retryTimer.restart()
    }

    function handleAttemptFinished(result) {
        var completedGeneration = attemptGeneration
        authenticating = false
        attemptGeneration = -1

        if (completedGeneration !== lockGeneration) return
        if (!lockService || !compatible || !lockService.locked) return

        if (result === PamResult.Success) {
            status = "success"
            // The existing Omarchy lock remains the sole owner of the session
            // lock. Hold the verified state briefly so the user sees the
            // checkmark, then ask that existing service to finish unlocking.
            successUnlockTimer.expectedGeneration = completedGeneration
            successUnlockTimer.restart()
            return
        }

        scheduleRetry()
    }

    function ensureLayerRule() {
        if (!layerRuleProcess.running) layerRuleProcess.running = true
    }

    Component.onCompleted: {
        resolveTimer.start()
        ensureLayerRule()
    }

    onShellChanged: {
        findLockService()
        if (lockService && compatible && lockService.locked) beginLockGeneration()
    }

    onLockServiceChanged: {
        if (lockService && compatible && lockService.locked) beginLockGeneration()
        else status = "unavailable"
    }

    Connections {
        target: root.lockService
        enabled: root.compatible
        ignoreUnknownSignals: true

        function onLockedChanged() {
            if (root.lockService.locked) root.beginLockGeneration()
            else root.endLockGeneration()
        }

        function onAuthenticatingPasswordChanged() {
            if (!root.lockService || !root.lockService.locked) return

            if (root.lockService.authenticatingPassword) {
                startTimer.stop()
                retryTimer.stop()
                successUnlockTimer.stop()
                root.abortAttempt()
                root.status = "password"
            } else {
                root.scheduleRetry()
            }
        }
    }

    PamContext {
        id: facePam
        config: "omarchy-face-id-lock"
        user: root.userName

        onCompleted: function(result) { root.handleAttemptFinished(result) }
        onError: function(error) {
            root.authenticating = false
            root.attemptGeneration = -1
            root.scheduleRetry()
        }
    }

    FileView {
        path: "/etc/pam.d/omarchy-face-id-lock"
        watchChanges: true
        printErrors: false
        onLoaded: {
            root.pamConfigured = true
            if (root.lockService && root.compatible && root.lockService.locked)
                root.beginLockGeneration()
        }
        onLoadFailed: {
            root.pamConfigured = false
            root.abortAttempt()
            root.status = "unavailable"
        }
        onFileChanged: reload()
    }

    Timer {
        id: resolveTimer
        interval: 500
        repeat: true
        onTriggered: root.findLockService()
    }

    // Avoid authenticating before Omarchy's session-lock surface has had time
    // to become secure. Password input remains available throughout this wait.
    Timer {
        id: startTimer
        interval: 1500
        repeat: false
        onTriggered: root.startAttempt()
    }

    Timer {
        id: retryTimer
        interval: 1000
        repeat: false
        onTriggered: root.startAttempt()
    }

    Timer {
        id: successUnlockTimer
        property int expectedGeneration: -1
        interval: 650
        repeat: false
        onTriggered: {
            if (expectedGeneration !== root.lockGeneration) return
            if (!root.lockService || !root.compatible || !root.lockService.locked) return
            if (root.lockService.authenticatingPassword || root.status !== "success") return
            root.lockService.finishUnlock()
        }
    }

    Timer {
        id: previewTimer
        interval: 4000
        repeat: false
        onTriggered: root.overlayPreviewVisible = false
    }

    // Hyprland renders this namespace above the session lock but leaves it
    // non-interactive. Failure here affects only the visual; PAM and the
    // first-party password field continue independently.
    Process {
        id: layerRuleProcess
        command: ["hyprctl", "eval", root.aboveLockRule]
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property var modelData
            screen: modelData
            visible: root.overlayVisible
            anchors { top: true; right: true; bottom: true; left: true }
            color: "transparent"
            WlrLayershell.namespace: "omarchy-face-id-overlay"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            mask: Region {}

            Item {
                id: indicator
                width: 220
                height: 250
                anchors.horizontalCenter: parent.horizontalCenter
                y: Math.max(36, parent.height * 0.5 - height - 42)

                readonly property bool checking: root.overlayState === "checking"
                readonly property bool success: root.overlayState === "success"
                readonly property color activeColor: success ? "#65d1a7"
                    : checking ? "#f59e0b" : Color.accent
                property int sweepIndex: 0
                property int glanceIndex: 0
                property int glanceStep: 0
                property bool blinking: false

                Repeater {
                    model: 72

                    delegate: Item {
                        required property int index
                        x: 14
                        y: 4
                        width: 192
                        height: 192
                        rotation: index * 5

                        Rectangle {
                            anchors.top: parent.top
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 2
                            height: indicator.success ? 9 : 7
                            radius: 1
                            color: indicator.activeColor
                            opacity: {
                                if (indicator.success) return 0.8
                                if (!indicator.checking) return 0.2
                                const distance = (index - indicator.sweepIndex + 72) % 72
                                return distance < 10 ? 0.92 - distance * 0.075 : 0.13
                            }
                            Behavior on color { ColorAnimation { duration: 180 } }
                            Behavior on opacity { NumberAnimation { duration: 120 } }
                        }
                    }
                }

                Rectangle {
                    x: 28
                    y: 18
                    width: 164
                    height: 164
                    radius: 82
                    color: "transparent"
                    border.width: 1
                    border.color: indicator.activeColor
                    opacity: indicator.success ? 0 : 0.32
                    Behavior on opacity { NumberAnimation { duration: 180 } }
                    Behavior on border.color { ColorAnimation { duration: 180 } }
                }

                Item {
                    id: faceAvatar
                    width: 76
                    height: 76
                    x: 72 + indicator.glanceIndex * 3
                    y: 62
                    opacity: indicator.success ? 0 : 1
                    scale: indicator.checking ? 1.05 : 1

                    Behavior on x { NumberAnimation { duration: 420; easing.type: Easing.InOutCubic } }
                    Behavior on opacity { NumberAnimation { duration: 160 } }
                    Behavior on scale { NumberAnimation { duration: 360; easing.type: Easing.InOutSine } }

                    Shape {
                        anchors.fill: parent
                        antialiasing: true
                        preferredRendererType: Shape.CurveRenderer

                        ShapePath {
                            fillColor: "transparent"
                            strokeColor: indicator.activeColor
                            strokeWidth: 4
                            capStyle: ShapePath.RoundCap
                            joinStyle: ShapePath.RoundJoin
                            PathSvg {
                                path: "M22 5H14C9 5 5 9 5 14V22 M54 5H62C67 5 71 9 71 14V22 M71 54V62C71 67 67 71 62 71H54 M22 71H14C9 71 5 67 5 62V54"
                            }
                        }

                        ShapePath {
                            fillColor: "transparent"
                            strokeColor: indicator.activeColor
                            strokeWidth: 3.5
                            capStyle: ShapePath.RoundCap
                            PathSvg { path: "M25 48C31 55 45 55 51 48" }
                        }
                    }

                    Rectangle {
                        x: 23 + indicator.glanceIndex * 2
                        y: 28
                        width: 5
                        height: indicator.blinking ? 2 : 7
                        radius: 3
                        color: indicator.activeColor
                        Behavior on x { NumberAnimation { duration: 300 } }
                    }

                    Rectangle {
                        x: 48 + indicator.glanceIndex * 2
                        y: 28
                        width: 5
                        height: indicator.blinking ? 2 : 7
                        radius: 3
                        color: indicator.activeColor
                        Behavior on x { NumberAnimation { duration: 300 } }
                    }
                }

                Item {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 56
                    width: 86
                    height: 86
                    opacity: indicator.success ? 1 : 0
                    scale: indicator.success ? 1 : 0.72

                    Behavior on opacity { NumberAnimation { duration: 220 } }
                    Behavior on scale { NumberAnimation { duration: 420; easing.type: Easing.OutBack } }

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: Qt.rgba(0.40, 0.82, 0.65, 0.12)
                        border.width: 2
                        border.color: "#65d1a7"
                    }

                    Shape {
                        anchors.fill: parent
                        antialiasing: true
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            fillColor: "transparent"
                            strokeColor: "#65d1a7"
                            strokeWidth: 6
                            capStyle: ShapePath.RoundCap
                            joinStyle: ShapePath.RoundJoin
                            PathSvg { path: "M24 44L37 57L64 28" }
                        }
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 212
                    text: indicator.success ? "UNLOCKED"
                        : indicator.checking ? "VERIFYING" : "LOOK AT THE CAMERA"
                    color: indicator.success ? "#65d1a7" : Color.lock.text
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    font.letterSpacing: 1.8
                    opacity: 0.9
                }

                Timer {
                    interval: 46
                    running: indicator.visible && indicator.checking
                    repeat: true
                    onTriggered: indicator.sweepIndex = (indicator.sweepIndex + 1) % 72
                }

                Timer {
                    interval: 860
                    running: indicator.visible && !indicator.success
                    repeat: true
                    onTriggered: {
                        const sequence = [-1, 0, 1, 0]
                        indicator.glanceIndex = sequence[indicator.glanceStep]
                        indicator.glanceStep = (indicator.glanceStep + 1) % sequence.length
                    }
                }

                Timer {
                    id: blinkTimer
                    interval: 2800
                    running: indicator.visible && !indicator.success
                    repeat: true
                    onTriggered: {
                        indicator.blinking = true
                        blinkClose.restart()
                    }
                }

                Timer {
                    id: blinkClose
                    interval: 120
                    repeat: false
                    onTriggered: indicator.blinking = false
                }
            }
        }
    }

    IpcHandler {
        target: "face-id"

        function status(): string {
            return JSON.stringify({
                compatible: root.compatible,
                pamConfigured: root.pamConfigured,
                enrolledUser: root.userName,
                authenticating: root.authenticating,
                state: root.status
            })
        }

        function preview(state: string): string {
            if (root.lockService && root.compatible && root.lockService.locked) return "locked"
            if (state !== "waiting" && state !== "checking" && state !== "success")
                state = "checking"
            root.overlayPreviewState = state
            root.overlayPreviewVisible = true
            previewTimer.restart()
            return "ok"
        }

        function closePreview(): string {
            previewTimer.stop()
            root.overlayPreviewVisible = false
            return "ok"
        }
    }
}
