import Toybox.Lang;
import Toybox.System;

//! Simulator helpers; compiled out of release (-r) builds.
module AresDebug {
    (:debug)
    function log(msg as String) as Void {
        System.println(System.getTimer() + " " + msg);
    }

    (:release)
    function log(msg as String) as Void {
    }

    //! Fixed [latE6, lonE6] from SIM_POS (scripts/build.sh), used when there is no GPS fix.
    (:debug)
    function simPosition() as Array<Number>? {
        if (AresBuild.SIM_LAT_E6 == 0 && AresBuild.SIM_LON_E6 == 0) {
            return null;
        }
        return [AresBuild.SIM_LAT_E6, AresBuild.SIM_LON_E6];
    }

    (:release)
    function simPosition() as Array<Number>? {
        return null;
    }
}
