import QtQuick
import Quickshell
import Quickshell.Io

// Inert compatibility service. It never starts PAM, opens a camera, or calls
// the lock IPC target. The first-party lock must own those actions once a
// supported biometric-provider API exists.
Item {
    id: root

    property var shell: null
    property var manifest: null
    property string omarchyPath: ""
    readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "fitzzz.face-unlock"
    readonly property string pluginDir: manifest && manifest.__sourceDir ? String(manifest.__sourceDir) : ""
    property bool ready: false
    property bool providerApiAvailable: false
    property bool cameraAvailable: false
    property bool gazeInstalled: false
    property string summary: "Compatibility has not been checked"
    property string reportJson: "{}"

    function refreshCompatibility() {
        ready = false;
        if (!pluginDir) {
            summary = "Plugin source directory is unavailable";
            reportJson = JSON.stringify({
                "schemaVersion": 1,
                "ready": false,
                "blockers": [summary]
            });
            return false;
        }
        if (doctor.running)
            return true;

        doctor.command = [pluginDir + "/bin/doctor", "--json"];
        doctor.running = true;
        return true;
    }

    function applyReport(raw) {
        var parsed = null;
        try {
            parsed = JSON.parse(String(raw || ""));
        } catch (e) {
        }
        if (!parsed || parsed.schemaVersion !== 1) {
            ready = false;
            summary = "Compatibility report was invalid";
            reportJson = JSON.stringify({
                "schemaVersion": 1,
                "ready": false,
                "blockers": [summary]
            });
            return ;
        }
        reportJson = JSON.stringify(parsed);
        ready = parsed.ready === true;
        providerApiAvailable = !!(parsed.omarchy && parsed.omarchy.providerApi);
        cameraAvailable = !!(parsed.camera && parsed.camera.available);
        gazeInstalled = !!(parsed.gaze && parsed.gaze.installed);
        if (ready)
            summary = "Face unlock prerequisites are ready";
        else if (parsed.blockers && parsed.blockers.length > 0)
            summary = String(parsed.blockers[0]);
        else
            summary = "Face unlock remains safely disabled";
    }

    Component.onCompleted: Qt.callLater(refreshCompatibility)
    onPluginDirChanged: {
        if (pluginDir)
            Qt.callLater(refreshCompatibility);

    }

    Process {
        id: doctor

        onExited: function(exitCode) {
            root.applyReport(doctorOutput.text);
            if (exitCode !== 0)
                root.ready = false;

        }

        stdout: StdioCollector {
            id: doctorOutput

            waitForEnd: true
        }

    }

    IpcHandler {
        function status() : string {
            return root.reportJson;
        }

        function refresh() : string {
            return root.refreshCompatibility() ? "ok" : "unavailable";
        }

        function preview() : string {
            if (!root.shell || typeof root.shell.summon !== "function")
                return "unavailable";

            root.shell.summon(root.pluginId, JSON.stringify({
                "mode": "auto"
            }));
            return "ok";
        }

        target: "face-unlock"
    }

}
