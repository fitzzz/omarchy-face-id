.pragma library

// Lock-screen state decisions live here so timer and child-process callbacks
// can be tested without opening a camera, starting PAM, or loading Omarchy.

function acceptsAttemptResult(completedGeneration, currentGeneration, locked) {
    return completedGeneration === currentGeneration && locked === true
}

function stateAfterAttempt(result, presenceMode) {
    if (result === "success") return "success"
    if (result === "failed" || result === "max_tries")
        return presenceMode === "continuous" ? "waiting" : "unauthorized"
    return "sleeping"
}

function canWake(status, locked, passwordActive) {
    return status === "sleeping" && locked === true && passwordActive !== true
}

function canStartPresence(status, presenceMode, locked, passwordActive) {
    return status === "sleeping" && presenceMode === "low_power"
        && locked === true && passwordActive !== true
}

function acceptsPresenceResult(status, presenceMode, watchedGeneration,
                               currentGeneration) {
    return status === "sleeping" && presenceMode === "low_power"
        && watchedGeneration === currentGeneration
}

function canFinishUnlock(expectedGeneration, currentGeneration, locked,
                         passwordActive, status) {
    return expectedGeneration === currentGeneration && locked === true
        && passwordActive !== true && status === "success"
}
