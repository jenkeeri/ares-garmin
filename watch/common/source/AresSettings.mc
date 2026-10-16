import Toybox.Application;
import Toybox.Lang;

//! Defensive property access (properties can be missing after an upgrade or mistyped by
//! the Garmin Connect settings UI).
module AresSettings {
    function get(key as String) as Application.Properties.ValueType? {
        try {
            return Application.Properties.getValue(key);
        } catch (e) {
            return null;
        }
    }

    function bool(key as String, dflt as Boolean) as Boolean {
        var v = get(key);
        return v instanceof Boolean ? v : dflt;
    }

    function num(key as String, dflt as Number) as Number {
        var v = get(key);
        return v instanceof Number ? v : dflt;
    }

    //! String setting; empty/missing falls back to dflt.
    function str(key as String, dflt as String) as String {
        var v = get(key);
        return (v instanceof String && v.length() > 0) ? v : dflt;
    }

    function set(key as String, value as Application.Properties.ValueType) as Void {
        try {
            Application.Properties.setValue(key, value);
        } catch (e) {
        }
    }
}
