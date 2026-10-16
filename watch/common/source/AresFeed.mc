import Toybox.Lang;
import Toybox.System;

//! Entity array layout (see docs/PROTOCOL.md): [id, kind, state, latE6, lonE6, ageS, label]
module AresProto {
    const I_ID = 0;
    const I_KIND = 1;
    const I_STATE = 2;
    const I_LAT = 3;
    const I_LON = 4;
    const I_AGE = 5;
    const I_LABEL = 6;

    const K_FRIEND = 0;
    const K_ENEMY = 1;
    const K_OBJECTIVE = 2;
    const K_WAYPOINT = 3;
    const K_BASE = 4;
    const K_HAZARD = 5;

    const S_OK = 0;
    const S_HIT = 1;
    const S_MEDIC = 2;
    const S_SUPPORT = 3;
    const S_STALE = 4;

    const ALERT_NONE = 0;
    const ALERT_ORDER = 1;
    const ALERT_URGENT = 2;
}

//! Latest picture received from the relay or phone. Holds the payload arrays as-is to keep
//! allocations minimal inside the 128 KB data-field budget.
class AresFeed {
    var entities as Array<Array> = [] as Array<Array>;
    var messages as Array<Array> = [] as Array<Array>;
    var seq as Number = 0;
    var pollHint as Number = 0;
    //! System.getTimer() when the last full update arrived (ages are relative to this).
    var receivedAt as Number = 0;
    //! System.getTimer() of the last successful exchange (full or unchanged).
    var lastOkAt as Number = 0;
    //! Newest message currently shown in the banner, and when it arrived.
    var bannerText as String? = null;
    var bannerPrio as Number = 0;
    var bannerAt as Number = 0;

    const MAX_ENTITIES = 40;
    const MAX_MESSAGES = 8;

    private var _knownMsgIds as Array<Number> = [] as Array<Number>;
    private var _medicIds as Array<Number> = [] as Array<Number>;

    function initialize() {
    }

    //! Applies a v1 payload. Returns an AresProto.ALERT_* level describing what changed.
    function apply(data as Dictionary) as Number {
        var now = System.getTimer();
        if (data.get("v") != 1) {
            return AresProto.ALERT_NONE;
        }
        lastOkAt = now;
        var p = data.get("p");
        if (p instanceof Number) {
            pollHint = p;
        }
        var q = data.get("q");
        if (q instanceof Number) {
            seq = q;
        }
        if (data.get("u") != 1) {
            return AresProto.ALERT_NONE;
        }
        var alert = AresProto.ALERT_NONE;
        entities = _cleanEntities(data.get("e"));
        receivedAt = now;
        alert = _checkMedics();

        messages = _cleanMessages(data.get("m"));
        var firstLoad = _knownMsgIds.size() == 0 && seq != 0 && bannerAt == 0;
        var ids = [] as Array<Number>;
        for (var i = messages.size() - 1; i >= 0; i--) {
            var msg = messages[i];
            var id = msg[0] as Number;
            ids.add(id);
            if (_knownMsgIds.indexOf(id) < 0) {
                var prio = msg[2] as Number;
                var ageS = msg[1] as Number;
                // Show new messages (and on first load only fresh ones).
                if (!firstLoad || ageS < 60) {
                    bannerText = msg[3] as String;
                    bannerPrio = prio;
                    bannerAt = now;
                    if (prio > alert) {
                        alert = prio;
                    }
                }
            }
        }
        _knownMsgIds = ids;
        return alert;
    }

    //! Payload values are used directly by the drawing code, where a wrong type is a fatal
    //! (uncatchable) error, so anything malformed is dropped or defaulted here.
    private function _cleanEntities(raw as Object?) as Array<Array> {
        var out = [] as Array<Array>;
        if (!(raw instanceof Array)) {
            return out;
        }
        for (var i = 0; i < raw.size() && out.size() < MAX_ENTITIES; i++) {
            var en = raw[i];
            if (!(en instanceof Array) || en.size() < 6) {
                continue;
            }
            en = en as Array<Object?>;
            var id = AresFeed.toNum(en[AresProto.I_ID], null);
            var lat = AresFeed.toNum(en[AresProto.I_LAT], null);
            var lon = AresFeed.toNum(en[AresProto.I_LON], null);
            if (id == null || lat == null || lon == null || lat > 90000000 || lat < -90000000 || lon > 180000000 || lon < -180000000) {
                continue;
            }
            var label = en.size() > AresProto.I_LABEL ? en[AresProto.I_LABEL] : null;
            out.add([id, AresFeed.toNum(en[AresProto.I_KIND], AresProto.K_WAYPOINT) as Number, AresFeed.toNum(en[AresProto.I_STATE], 0) as Number, lat, lon,
                     _clamp(AresFeed.toNum(en[AresProto.I_AGE], 0) as Number, 0, 864000), AresFeed.toStr(label, 12)]);
        }
        return out;
    }

    private function _cleanMessages(raw as Object?) as Array<Array> {
        var out = [] as Array<Array>;
        if (!(raw instanceof Array)) {
            return out;
        }
        for (var i = 0; i < raw.size() && out.size() < MAX_MESSAGES; i++) {
            var m = raw[i];
            if (!(m instanceof Array) || m.size() < 4) {
                continue;
            }
            m = m as Array<Object?>;
            var id = AresFeed.toNum(m[0], null);
            if (id == null || m[3] == null) {
                continue;
            }
            out.add([id, _clamp(AresFeed.toNum(m[1], 0) as Number, 0, 864000), _clamp(AresFeed.toNum(m[2], 0) as Number, 0, AresProto.ALERT_URGENT),
                     AresFeed.toStr(m[3], 120)]);
        }
        return out;
    }

    private function _clamp(v as Number, lo as Number, hi as Number) as Number {
        return v < lo ? lo : (v > hi ? hi : v);
    }

    //! Number from a JSON value (Long/Float/Double are truncated), else `dflt`.
    static function toNum(v as Object?, dflt as Number?) as Number? {
        if (v instanceof Number) {
            return v;
        }
        if (v instanceof Long || v instanceof Float || v instanceof Double) {
            return (v as Long or Float or Double).toNumber();
        }
        return dflt;
    }

    static function toStr(v as Object?, maxLen as Number) as String {
        var s = (v instanceof String ? v : (v == null ? "" : v.toString())) as String;
        return s.length() > maxLen ? s.substring(0, maxLen) as String : s;
    }

    //! Alert when a friendly newly requests a medic.
    private function _checkMedics() as Number {
        var alert = AresProto.ALERT_NONE;
        var ids = [] as Array<Number>;
        for (var i = 0; i < entities.size(); i++) {
            var en = entities[i];
            if (en[AresProto.I_KIND] == AresProto.K_FRIEND && en[AresProto.I_STATE] == AresProto.S_MEDIC) {
                var id = en[AresProto.I_ID] as Number;
                ids.add(id);
                if (_medicIds.indexOf(id) < 0) {
                    alert = AresProto.ALERT_URGENT;
                    bannerText = "MEDIC: " + (en[AresProto.I_LABEL] as String);
                    bannerPrio = AresProto.ALERT_URGENT;
                    bannerAt = System.getTimer();
                }
            }
        }
        _medicIds = ids;
        return alert;
    }

    //! Age of an entity position in seconds, including time since reception.
    function ageOf(en as Array) as Number {
        return (en[AresProto.I_AGE] as Number) + (System.getTimer() - receivedAt) / 1000;
    }

    //! Seconds since the last successful exchange, or -1 if never.
    function linkAge() as Number {
        return lastOkAt == 0 ? -1 : (System.getTimer() - lastOkAt) / 1000;
    }

    //! Banner text if a message arrived within `holdMs`, else null.
    function activeBanner(holdMs as Number) as String? {
        if (bannerText != null && System.getTimer() - bannerAt < holdMs) {
            return bannerText;
        }
        return null;
    }

    function clearBanner() as Void {
        bannerAt = 0;
    }
}
