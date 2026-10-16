import Toybox.Lang;
import Toybox.System;

//! Console tracing for simulator debugging; compiled out of release (-r) builds.
module AresLog {
    (:debug)
    function log(msg as String) as Void {
        System.println(System.getTimer() + " " + msg);
    }

    (:release)
    function log(msg as String) as Void {
    }
}
