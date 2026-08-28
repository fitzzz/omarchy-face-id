import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam

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
        abortAttempt()

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
        abortAttempt()
        status = compatible && pamConfigured ? "idle" : "unavailable"
    }

    function abortAttempt() {
        authenticating = false
        attemptGeneration = -1
        if (facePam.active) facePam.abort()
    }

    function startAttempt() {
        if (!compatible || !pamConfigured || !lockService.locked) return
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
        if (!compatible || !pamConfigured || !lockService.locked) return
        if (lockService.authenticatingPassword) return
        status = "waiting"
        retryTimer.restart()
    }

    function handleAttemptFinished(result) {
        var completedGeneration = attemptGeneration
        authenticating = false
        attemptGeneration = -1

        if (completedGeneration !== lockGeneration) return
        if (!compatible || !lockService.locked) return

        if (result === PamResult.Success) {
            status = "success"
            // The existing Omarchy lock remains the sole owner of the session
            // lock. A successful, current PAM result is the only path here.
            lockService.finishUnlock()
            return
        }

        scheduleRetry()
    }

    Component.onCompleted: resolveTimer.start()

    onShellChanged: {
        findLockService()
        if (compatible && lockService.locked) beginLockGeneration()
    }

    onLockServiceChanged: {
        if (compatible && lockService.locked) beginLockGeneration()
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
            if (!root.lockService.locked) return

            if (root.lockService.authenticatingPassword) {
                root.startTimer.stop()
                root.retryTimer.stop()
                root.abortAttempt()
                root.status = "password"
            } else {
                root.scheduleRetry()
            }
        }
    }

    PamContext {
        id: facePam
        config: "omarchy-lock-face"
        user: root.userName

        onCompleted: function(result) { root.handleAttemptFinished(result) }
        onError: function(error) {
            root.authenticating = false
            root.attemptGeneration = -1
            root.scheduleRetry()
        }
    }

    FileView {
        path: "/etc/pam.d/omarchy-lock-face"
        watchChanges: true
        printErrors: false
        onLoaded: {
            root.pamConfigured = true
            if (root.compatible && root.lockService.locked) root.beginLockGeneration()
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

    IpcHandler {
        target: "face-unlock"

        function status(): string {
            return JSON.stringify({
                compatible: root.compatible,
                pamConfigured: root.pamConfigured,
                enrolledUser: root.userName,
                authenticating: root.authenticating,
                state: root.status
            })
        }
    }
}
