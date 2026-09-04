import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Wayland
import qs.Commons
import "LockState.js" as LockState

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
    property int verifyingWordIndex: -1
    property string verifyingWord: "EXTRAPOLATING"
    property real verifyingWordOpacity: 0.9
    property string diagnosticSessionId: createDiagnosticSessionId()
    property string presenceMode: "low_power"
    property string motionSensitivity: "medium"
    property int configuredStartDelayMs: 3000
    property int configuredRejectionHoldMs: 2500
    property bool sleepingIndicator: true
    property bool inputWakeArmed: false
    property int presenceGeneration: -1
    property bool waitingForPresenceExit: false

    readonly property var verifyingWords: [
        "EXTRAPOLATING",
        "SYNTHESIZING",
        "DISAMBIGUATING",
        "ITERATING",
        "SIFTING",
        "HALLUCINATING",
        "DRIFTING",
        "DISTILLING",
        "RECONCILING",
        "CORRELATING",
        "CALIBRATING",
        "AGGREGATING",
        "CONDENSING",
        "PARAPHRASING",
        "MODULATING",
        "CONTEXTUALIZING",
        "ANCHORING",
        "MIRRORING",
        "ECHOING",
        "PRUNING",
        "SCORING",
        "REFINING",
        "CONVERGING"
    ]

    readonly property string overlayState: overlayPreviewVisible ? overlayPreviewState : status
    readonly property bool overlayVisible: overlayPreviewVisible || (lockService
        && compatible
        && lockService.locked
        && (status === "waiting" || status === "waking" || status === "checking"
            || status === "unauthorized" || status === "success"
            || (status === "sleeping" && sleepingIndicator)))
    readonly property string aboveLockRule: 'hl.layer_rule({ name = "omarchy-face-id-above-lock", match = { namespace = "omarchy-face-id-overlay" }, above_lock = 1 })'

    readonly property string userName: Quickshell.env("USER") || Quickshell.env("LOGNAME")
    readonly property string dingPath: decodeURIComponent(
        Qt.resolvedUrl("ding.mp3").toString().replace("file://", ""))
    readonly property string diagnosticLoggerPath: decodeURIComponent(
        Qt.resolvedUrl("log-event.sh").toString().replace("file://", ""))
    readonly property string presenceHelperPath: decodeURIComponent(
        Qt.resolvedUrl("presence-watcher").toString().replace("file://", ""))
    readonly property string configRoot: Quickshell.env("XDG_CONFIG_HOME")
        || ((Quickshell.env("HOME") || "/tmp") + "/.config")
    readonly property string userConfigPath: configRoot
        + "/omarchy-face-id/config.toml"
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

    function chooseVerifyingWord() {
        if (verifyingWords.length === 0) return

        var nextIndex = Math.floor(Math.random() * verifyingWords.length)
        if (nextIndex === verifyingWordIndex && verifyingWords.length > 1)
            nextIndex = (nextIndex + 1) % verifyingWords.length

        verifyingWordIndex = nextIndex
        verifyingWord = verifyingWords[nextIndex]
    }

    function playDing() {
        if (!dingProcess.running) dingProcess.running = true
    }

    function randomHex(length) {
        var value = ""
        for (var index = 0; index < length; index++)
            value += Math.floor(Math.random() * 16).toString(16)
        return value
    }

    function createDiagnosticSessionId() {
        return randomHex(8) + "-" + randomHex(4) + "-" + randomHex(4)
            + "-" + randomHex(4) + "-" + randomHex(12)
    }

    function logDiagnostic(event, level, attributes) {
        var args = [diagnosticLoggerPath, event, level || "info", diagnosticSessionId]
        var values = attributes || {}
        for (var key in values) args.push(key + "=" + String(values[key]))
        Quickshell.execDetached(args)
    }

    function pamResultName(result) {
        if (result === PamResult.Success) return "success"
        if (result === PamResult.Failed) return "failed"
        if (result === PamResult.MaxTries) return "max_tries"
        return "other"
    }

    function boundedInteger(value, fallback, minimum, maximum) {
        var parsed = Number(value)
        if (!Number.isFinite(parsed)) return fallback
        return Math.max(minimum, Math.min(maximum, Math.round(parsed)))
    }

    function loadUserConfig(raw) {
        var nextMode = "low_power"
        var nextSensitivity = "medium"
        var nextStartDelay = 3000
        var nextRejectionHold = 2500
        var nextSleepingIndicator = true
        var section = ""
        var lines = String(raw || "").split(/\r?\n/)

        for (var index = 0; index < lines.length; index++) {
            var line = lines[index].trim()
            if (!line || line[0] === "#") continue
            var sectionMatch = line.match(/^\[([a-z_]+)\]$/)
            if (sectionMatch) {
                section = sectionMatch[1]
                continue
            }
            if (section !== "lock_screen") continue

            var valueMatch = line.match(/^([a-z_]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s#]+))/)
            if (!valueMatch) continue
            var key = valueMatch[1]
            var value = valueMatch[2] !== undefined ? valueMatch[2]
                : valueMatch[3] !== undefined ? valueMatch[3] : valueMatch[4]
            if (key === "presence_mode"
                && (value === "low_power" || value === "on_activity"
                    || value === "continuous")) nextMode = value
            else if (key === "motion_sensitivity"
                     && (value === "low" || value === "medium" || value === "high"))
                nextSensitivity = value
            else if (key === "start_delay_ms")
                nextStartDelay = boundedInteger(value, 3000, 0, 30000)
            else if (key === "rejection_hold_ms")
                nextRejectionHold = boundedInteger(value, 2500, 500, 10000)
            else if (key === "sleeping_indicator")
                nextSleepingIndicator = value === "true" ? true
                    : value === "false" ? false : true
        }

        var modeChanged = presenceMode !== nextMode
        presenceMode = nextMode
        motionSensitivity = nextSensitivity
        configuredStartDelayMs = nextStartDelay
        configuredRejectionHoldMs = nextRejectionHold
        sleepingIndicator = nextSleepingIndicator
        logDiagnostic("config_loaded", "info", {
            presence_mode: presenceMode,
            motion_sensitivity: motionSensitivity,
            start_delay_ms: configuredStartDelayMs,
            rejection_hold_ms: configuredRejectionHoldMs,
            sleeping_indicator: sleepingIndicator
        })

        if (modeChanged && lockService && compatible && lockService.locked
            && status === "sleeping") enterSleeping("configuration_changed")
    }

    onOverlayStateChanged: {
        verifyingWordTransition.stop()
        verifyingWordOpacity = 0.9
        if (overlayState === "checking") chooseVerifyingWord()
    }

    function beginLockGeneration() {
        lockGeneration += 1
        logDiagnostic("lock_started", "info", {
            generation: lockGeneration,
            compatible: compatible,
            pam_configured: pamConfigured,
            grace_ms: configuredStartDelayMs,
            presence_mode: presenceMode
        })
        retryTimer.stop()
        startTimer.stop()
        rejectionHoldTimer.stop()
        presenceStartTimer.stop()
        presenceReleaseTimer.stop()
        successUnlockTimer.stop()
        postUnlockWakeTimer.stop()
        inputWakeArmed = false
        stopPresenceWatcher()
        abortAttempt()
        ensureLayerRule()

        if (!compatible || !pamConfigured) {
            status = "unavailable"
            return
        }

        // Give the user time to leave the desk before the camera opens. The
        // overlay stays hidden until authentication actually begins.
        status = "grace"
        startTimer.restart()
    }

    function endLockGeneration() {
        logDiagnostic("lock_ended", "info", {
            generation: lockGeneration,
            final_status: status
        })
        lockGeneration += 1
        retryTimer.stop()
        startTimer.stop()
        rejectionHoldTimer.stop()
        presenceStartTimer.stop()
        presenceReleaseTimer.stop()
        successUnlockTimer.stop()
        inputWakeArmed = false
        stopPresenceWatcher()
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

        presenceStartTimer.stop()
        stopPresenceWatcher()
        attemptGeneration = lockGeneration
        authenticating = true
        status = "checking"
        logDiagnostic("attempt_started", "info", {
            generation: attemptGeneration
        })

        if (!facePam.start()) {
            logDiagnostic("attempt_start_failed", "error", {
                generation: attemptGeneration
            })
            authenticating = false
            attemptGeneration = -1
            enterSleeping("pam_start_failed")
        }
    }

    function stopPresenceWatcher() {
        waitingForPresenceExit = false
        presenceGeneration = -1
        if (presenceProcess.running) presenceProcess.running = false
    }

    function enterSleeping(reason) {
        if (!lockService || !compatible || !pamConfigured || !lockService.locked) return
        if (lockService.authenticatingPassword) return
        retryTimer.stop()
        rejectionHoldTimer.stop()
        presenceStartTimer.stop()
        inputWakeArmed = false
        stopPresenceWatcher()

        if (presenceMode === "continuous") {
            status = "waiting"
            logDiagnostic("retry_scheduled", "warning", {
                generation: lockGeneration,
                reason: reason || "unspecified",
                delay_ms: configuredRejectionHoldMs
            })
            retryTimer.restart()
            return
        }

        status = "sleeping"
        logDiagnostic("sleeping_entered", "info", {
            generation: lockGeneration,
            reason: reason || "unspecified",
            presence_mode: presenceMode
        })
        if (presenceMode === "low_power") presenceStartTimer.restart()
    }

    function wakeFromPresence(source) {
        if (!lockService || !compatible || !pamConfigured) return
        if (!LockState.canWake(status, lockService.locked,
                               lockService.authenticatingPassword)) return
        status = "waking"
        inputWakeArmed = false
        presenceStartTimer.stop()
        logDiagnostic("sleeping_wake_requested", "info", {
            generation: lockGeneration,
            source: source
        })
        presenceGeneration = -1
        if (presenceProcess.running) {
            waitingForPresenceExit = true
            presenceProcess.running = false
        } else {
            presenceReleaseTimer.restart()
        }
    }

    function handleAttemptFinished(result) {
        var completedGeneration = attemptGeneration
        authenticating = false
        attemptGeneration = -1

        if (!lockService || !compatible) return
        if (!LockState.acceptsAttemptResult(completedGeneration, lockGeneration,
                                            lockService.locked)) return

        logDiagnostic("attempt_finished", result === PamResult.Success ? "info" : "warning", {
            generation: completedGeneration,
            result: pamResultName(result)
        })

        const nextState = LockState.stateAfterAttempt(pamResultName(result), presenceMode)
        if (nextState === "success") {
            status = "success"
            root.playDing()
            // The existing Omarchy lock remains the sole owner of the session
            // lock. Hold the verified state briefly so the user sees the
            // checkmark, then ask that existing service to finish unlocking.
            successUnlockTimer.expectedGeneration = completedGeneration
            successUnlockTimer.restart()
            return
        }

        if (nextState === "unauthorized" || nextState === "waiting") {
            status = "unauthorized"
            if (nextState === "waiting") {
                logDiagnostic("retry_scheduled", "warning", {
                    generation: lockGeneration,
                    reason: "face_rejected",
                    delay_ms: configuredRejectionHoldMs
                })
                retryTimer.restart()
            } else {
                rejectionHoldTimer.restart()
            }
        } else {
            enterSleeping("pam_result_unavailable")
        }
    }

    function ensureLayerRule() {
        if (!layerRuleProcess.running) layerRuleProcess.running = true
    }

    function keepDisplaysAwake() {
        if (!lockService || !lockService.locked) return
        if (typeof lockService.runWake === "function") lockService.runWake()
    }

    Component.onCompleted: {
        logDiagnostic("subscriber_started", "info", {})
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
            else {
                root.endLockGeneration()
                postUnlockWakeTimer.restart()
            }
        }

        function onAuthenticatingPasswordChanged() {
            if (!root.lockService || !root.lockService.locked) return

            if (root.lockService.authenticatingPassword) {
                root.logDiagnostic("password_fallback_started", "info", {
                    generation: root.lockGeneration
                })
                startTimer.stop()
                retryTimer.stop()
                rejectionHoldTimer.stop()
                presenceStartTimer.stop()
                presenceReleaseTimer.stop()
                successUnlockTimer.stop()
                root.stopPresenceWatcher()
                root.abortAttempt()
                root.status = "password"
            } else {
                root.enterSleeping("password_finished")
            }
        }
    }

    PamContext {
        id: facePam
        config: "omarchy-face-id-lock"
        user: root.userName

        onCompleted: function(result) { root.handleAttemptFinished(result) }
        onError: function(error) {
            var completedGeneration = root.attemptGeneration
            root.logDiagnostic("attempt_error", "error", {
                generation: completedGeneration,
                category: "no_face_or_unavailable"
            })
            root.authenticating = false
            root.attemptGeneration = -1
            if (completedGeneration === root.lockGeneration)
                root.enterSleeping("no_face_or_unavailable")
        }
    }

    FileView {
        id: userConfigFile
        path: root.userConfigPath
        watchChanges: true
        printErrors: false
        onLoaded: root.loadUserConfig(text())
        onLoadFailed: root.loadUserConfig("")
        onFileChanged: reload()
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

    // Let the user leave the desk before opening the camera. Password input
    // remains available throughout this grace period.
    Timer {
        id: startTimer
        interval: root.configuredStartDelayMs
        repeat: false
        onTriggered: root.startAttempt()
    }

    // Omarchy's first-party lock blanks displays after five seconds. Re-arm
    // that timer through its public wake method while Face ID is subscribed,
    // preventing a blank/wake race during face authentication.
    Timer {
        id: keepAwakeTimer
        interval: 3000
        repeat: true
        running: root.lockService && root.compatible && root.pamConfigured
            && root.lockService.locked
        onTriggered: root.keepDisplaysAwake()
    }

    Timer {
        id: retryTimer
        interval: root.configuredRejectionHoldMs
        repeat: false
        onTriggered: root.startAttempt()
    }

    Timer {
        id: rejectionHoldTimer
        interval: root.configuredRejectionHoldMs
        repeat: false
        onTriggered: root.enterSleeping("face_rejected")
    }

    // Let PAM fully release the camera before the low-rate watcher opens it.
    Timer {
        id: presenceStartTimer
        interval: 300
        repeat: false
        onTriggered: {
            if (!root.lockService || !LockState.canStartPresence(
                    root.status, root.presenceMode, root.lockService.locked,
                    root.lockService.authenticatingPassword)) return
            root.presenceGeneration = root.lockGeneration
            if (!presenceProcess.running) presenceProcess.running = true
        }
    }

    // The watcher exits only after dropping its GStreamer pipeline. This short
    // handoff keeps Gaze from racing it for the same camera.
    Timer {
        id: presenceReleaseTimer
        interval: 250
        repeat: false
        onTriggered: root.startAttempt()
    }

    IdleMonitor {
        id: inputActivityMonitor
        enabled: root.lockService && root.compatible && root.pamConfigured
            && root.lockService.locked && root.status === "sleeping"
        timeout: 1
        respectInhibitors: false
        onIsIdleChanged: {
            if (!enabled) return
            if (isIdle) {
                root.inputWakeArmed = true
            } else if (root.inputWakeArmed) {
                root.wakeFromPresence("input_activity")
            }
        }
    }

    Timer {
        id: successUnlockTimer
        property int expectedGeneration: -1
        interval: 650
        repeat: false
        onTriggered: {
            if (!root.lockService || !root.compatible) return
            if (!LockState.canFinishUnlock(expectedGeneration, root.lockGeneration,
                                           root.lockService.locked,
                                           root.lockService.authenticatingPassword,
                                           root.status)) return
            root.logDiagnostic("unlock_handoff_requested", "info", {
                generation: expectedGeneration
            })
            root.lockService.finishUnlock()
        }
    }

    // The stock lock starts blank and wake commands asynchronously. Ensure the
    // final display transition after either unlock path is always "on".
    Timer {
        id: postUnlockWakeTimer
        interval: 350
        repeat: false
        onTriggered: {
            if (!postUnlockWakeProcess.running) postUnlockWakeProcess.running = true
        }
    }

    Timer {
        id: previewTimer
        interval: 4000
        repeat: false
        onTriggered: root.overlayPreviewVisible = false
    }

    Timer {
        id: verifyingWordTimer
        interval: 2000
        repeat: true
        running: root.overlayVisible && root.overlayState === "checking"
        onTriggered: verifyingWordTransition.restart()
    }

    SequentialAnimation {
        id: verifyingWordTransition

        NumberAnimation {
            target: root
            property: "verifyingWordOpacity"
            to: 0
            duration: 220
            easing.type: Easing.InOutCubic
        }
        ScriptAction { script: root.chooseVerifyingWord() }
        NumberAnimation {
            target: root
            property: "verifyingWordOpacity"
            to: 0.9
            duration: 280
            easing.type: Easing.OutCubic
        }
    }

    // Hyprland renders this namespace above the session lock but leaves it
    // non-interactive. Failure here affects only the visual; PAM and the
    // first-party password field continue independently.
    Process {
        id: layerRuleProcess
        command: ["hyprctl", "eval", root.aboveLockRule]
    }

    Process {
        id: postUnlockWakeProcess
        command: ["omarchy-system-wake"]
    }

    Process {
        id: dingProcess
        command: ["/usr/bin/pw-play", root.dingPath]
    }

    Process {
        id: presenceProcess
        command: [root.presenceHelperPath, "--config", root.userConfigPath]
        onStarted: root.logDiagnostic("presence_watcher_started", "info", {
            generation: root.presenceGeneration,
            motion_sensitivity: root.motionSensitivity
        })
        onExited: function(exitCode, exitStatus) {
            var watchedGeneration = root.presenceGeneration
            root.presenceGeneration = -1
            if (root.waitingForPresenceExit && root.status === "waking") {
                root.waitingForPresenceExit = false
                presenceReleaseTimer.restart()
                return
            }
            if (!LockState.acceptsPresenceResult(root.status, root.presenceMode,
                                                 watchedGeneration,
                                                 root.lockGeneration)) return
            if (exitCode === 0 || exitCode === 10) {
                root.logDiagnostic("presence_motion_detected", "info", {
                    generation: watchedGeneration,
                    used_fallback_camera: exitCode === 10
                })
                root.wakeFromPresence("camera_motion")
            } else {
                root.logDiagnostic("presence_watcher_unavailable", "warning", {
                    generation: watchedGeneration,
                    exit_code: exitCode
                })
            }
        }
    }

    Component {
        id: faceIdIndicatorComponent

        FaceIdIndicator {
            verifyingWord: root.verifyingWord
            verifyingWordOpacity: root.verifyingWordOpacity
        }
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

            Loader {
                id: lockIndicatorLoader
                width: 220
                height: 250
                anchors.horizontalCenter: parent.horizontalCenter
                y: Math.max(36, parent.height * 0.5 - height - 74)
                sourceComponent: faceIdIndicatorComponent
                Binding {
                    target: lockIndicatorLoader.item
                    property: "displayState"
                    value: root.overlayState
                    when: lockIndicatorLoader.item !== null
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
                presenceMode: root.presenceMode,
                state: root.status
            })
        }

        function preview(state: string): string {
            if (root.lockService && root.compatible && root.lockService.locked) return "locked"
            if (state !== "waiting" && state !== "waking" && state !== "sleeping"
                && state !== "checking" && state !== "unauthorized"
                && state !== "success")
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
