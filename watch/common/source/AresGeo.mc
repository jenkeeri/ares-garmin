import Toybox.Lang;
import Toybox.Math;

//! Local flat-earth math in integer micro-degrees. Accurate to well under 1% within 10 km,
//! which covers any airsoft/milsim field, and avoids Float precision loss on raw lat/lon.
module AresGeo {
    const M_PER_E6 = 0.1111949f;

    //! Meters east/north of (lat0, lon0) for a point at (lat, lon); all in micro-degrees.
    //! `cosLat` is cos(latitude of the observer).
    function enu(lat0 as Number, lon0 as Number, lat as Number, lon as Number, cosLat as Float) as [Float, Float] {
        var dLon = lon - lon0;
        if (dLon > 180000000) {
            dLon -= 360000000;
        } else if (dLon < -180000000) {
            dLon += 360000000;
        }
        return [dLon * M_PER_E6 * cosLat, (lat - lat0) * M_PER_E6];
    }

    function cosLatOf(latE6 as Number) as Float {
        return Math.cos(Math.toRadians(latE6 / 1000000.0f)).toFloat();
    }

    //! Bearing in degrees 0..360 from an east/north offset.
    function bearingDeg(east as Float, north as Float) as Float {
        var b = Math.toDegrees(Math.atan2(east, north)).toFloat();
        return b < 0 ? b + 360.0f : b;
    }

    function dist(east as Float, north as Float) as Float {
        return Math.sqrt(east * east + north * north).toFloat();
    }

    //! "85m", "850m", "1.2k", "12k"
    function fmtDist(m as Float) as String {
        if (m < 1000.0f) {
            return m.toNumber().toString() + "m";
        }
        if (m < 10000.0f) {
            return (m / 1000.0f).format("%.1f") + "k";
        }
        return (m / 1000.0f).toNumber().toString() + "k";
    }

    //! 8-point compass name for a bearing.
    function cardinal(b as Float) as String {
        var names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"];
        return names[((b + 22.5f) / 45.0f).toNumber() % 8];
    }

    function fmtAge(s as Number) as String {
        if (s < 60) {
            return s.toString() + "s";
        }
        if (s < 3600) {
            return (s / 60).toString() + "m";
        }
        return (s / 3600).toString() + "h";
    }
}
