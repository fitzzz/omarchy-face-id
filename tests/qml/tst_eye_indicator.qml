import "../../components"
import QtQuick
import QtTest

TestCase {
    id: testCase

    function test_knownStates() {
        var indicator = createTemporaryObject(indicatorComponent, testCase);
        verify(indicator !== null);
        var states = ["searching", "checking", "success", "unavailable"];
        for (var i = 0; i < states.length; i++) {
            indicator.state = states[i];
            compare(indicator.state, states[i]);
            verify(indicator.statusColor !== undefined);
        }
    }

    function test_reducedMotionCentersPupil() {
        var indicator = createTemporaryObject(indicatorComponent, testCase);
        verify(indicator !== null);
        indicator.state = "searching";
        indicator.glanceIndex = 1;
        indicator.resetMotion();
        compare(indicator.glanceIndex, 0);
        compare(indicator.blinking, false);
    }

    name: "EyeIndicator"

    Component {
        id: indicatorComponent

        EyeIndicator {
            reducedMotion: true
            iconSize: 56
        }

    }

}
