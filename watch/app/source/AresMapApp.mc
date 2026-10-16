import Toybox.Activity;
import Toybox.ActivityRecording;
import Toybox.Application;
import Toybox.Attention;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.Sensor;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

//! Full watch app: radar, Garmin map with team markers, message list and optional activity
//! recording. Shares the feed / link / radar core with the AresRadar data field.
class AresMapApp extends Application.AppBase {
    var state as AresState?;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(st as Dictionary?) as Void {
        state = new AresState();
        state.start();
    }

    function onStop(st as Dictionary?) as Void {
        if (state != null) {
            state.stop();
        }
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        return [new AresRadarView(), new AresRadarDelegate()];
    }

    function onSettingsChanged() as Void {
        if (state != null) {
            state.reloadSettings();
        }
        WatchUi.requestUpdate();
    }
}

function aresState() as AresState {
    return (Application.getApp() as AresMapApp).state as AresState;
}

//! App-wide state: feed, link, radar settings, own position/heading and the optional
//! recording session. A 1 s timer drives polling and redraws.
class AresState {
    var feed as AresFeed;
    var link as AresLink;
    var radar as AresRadar;
    //! [latE6, lonE6] or null without a fix.
    var pos as Array<Number>? = null;
    //! Degrees, or null when unknown.
    var heading as Float? = null;
    var session as ActivityRecording.Session? = null;

    private var _timer as Timer.Timer;
    private var _vibrate as Boolean = true;
    private var _gps as Boolean = false;
    //! GPS course over ground (degrees) while moving; fallback when there is no compass.
    private var _course as Float? = null;

    function initialize() {
        feed = new AresFeed();
        radar = new AresRadar();
        link = new AresLink(feed, 32, method(:onAlert));
        _timer = new Timer.Timer();
        reloadSettings();
    }

    function reloadSettings() as Void {
        link.reloadSettings();
        radar.headingUp = AresSettings.bool("headingUp", true);
        radar.fixedRange = AresSettings.num("fixedRange", 0);
        _vibrate = AresSettings.bool("vibrate", true);
    }

    function start() as Void {
        Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
        _timer.start(method(:onTick), 1000, true);
        onTick();
    }

    function stop() as Void {
        _timer.stop();
        Position.enableLocationEvents(Position.LOCATION_DISABLE, method(:onPosition));
        // Never lose a recorded activity when the app is closed by the system.
        if (session != null) {
            if (session.isRecording()) {
                session.stop();
            }
            session.save();
            session = null;
        }
    }

    function onPosition(info as Position.Info) as Void {
        var loc = info.position;
        if (loc != null && info.accuracy >= Position.QUALITY_POOR) {
            var d = loc.toDegrees();
            pos = [(d[0] * 1000000).toNumber(), (d[1] * 1000000).toNumber()];
            _gps = true;
        }
        var hd = info.heading;
        var sp = info.speed;
        if (hd != null && sp != null && sp > 1.0f) {
            _course = Math.toDegrees(hd).toFloat();
        }
    }

    function onTick() as Void {
        var si = Sensor.getInfo();
        var sh = si.heading;
        heading = sh != null ? Math.toDegrees(sh).toFloat() : _course;
        if (!_gps) {
            pos = AresDebug.simPosition();
        }
        if (pos != null) {
            link.tick(pos[0], pos[1]);
        } else {
            link.tick(null, null);
        }
        WatchUi.requestUpdate();
    }

    function onAlert(level as Number) as Void {
        if (!_vibrate || !(Attention has :vibrate)) {
            return;
        }
        if (level >= AresProto.ALERT_URGENT) {
            Attention.vibrate([new Attention.VibeProfile(100, 400), new Attention.VibeProfile(0, 200), new Attention.VibeProfile(100, 400)]);
        } else {
            Attention.vibrate([new Attention.VibeProfile(70, 250)]);
        }
    }

    function isRecording() as Boolean {
        return session != null && session.isRecording();
    }

    //! Start, pause or resume the activity recording.
    function toggleRecording() as Void {
        if (session == null) {
            session = ActivityRecording.createSession({
                :name => "Ares",
                :sport => Activity.SPORT_GENERIC,
                :subSport => Activity.SUB_SPORT_GENERIC
            });
        }
        var s = session as ActivityRecording.Session;
        if (s.isRecording()) {
            s.stop();
        } else {
            s.start();
        }
        if (Attention has :vibrate) {
            Attention.vibrate([new Attention.VibeProfile(60, 150)]);
        }
    }

    //! Ends the recording; `keep` saves it, otherwise it is discarded.
    function finishRecording(keep as Boolean) as Void {
        if (session == null) {
            return;
        }
        var s = session as ActivityRecording.Session;
        if (s.isRecording()) {
            s.stop();
        }
        if (keep) {
            s.save();
        } else {
            s.discard();
        }
        session = null;
    }
}
