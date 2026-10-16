import Toybox.Activity;
import Toybox.Application;
import Toybox.Attention;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.WatchUi;

class AresFieldApp extends Application.AppBase {
    private var _view as AresFieldView?;

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        _view = new AresFieldView();
        return [_view];
    }

    function onSettingsChanged() as Void {
        if (_view != null) {
            _view.reloadSettings();
        }
        WatchUi.requestUpdate();
    }
}

//! Data field for any native activity (Hike, Run, Tactical, ...). In a 1-field layout it
//! renders the full radar; in smaller slots a mini radar or a pointer to the nearest objective.
class AresFieldView extends WatchUi.DataField {
    private var _feed as AresFeed;
    private var _link as AresLink;
    private var _radar as AresRadar;
    private var _me as Array<Number>? = null;
    private var _heading as Float? = null;
    private var _vibrate as Boolean = true;

    function initialize() {
        DataField.initialize();
        _feed = new AresFeed();
        _radar = new AresRadar();
        _link = new AresLink(_feed, 24, method(:onAlert));
        reloadSettings();
    }

    function reloadSettings() as Void {
        _link.reloadSettings();
        _radar.headingUp = AresSettings.bool("headingUp", true);
        _radar.fixedRange = AresSettings.num("fixedRange", 0);
        _vibrate = AresSettings.bool("vibrate", true);
    }

    function compute(info as Activity.Info) as Void {
        var loc = info.currentLocation;
        var acc = info.currentLocationAccuracy;
        if (loc != null && acc != null && acc >= Position.QUALITY_POOR) {
            var d = loc.toDegrees();
            _me = [(d[0] * 1000000).toNumber(), (d[1] * 1000000).toNumber()];
        }
        if (_me == null) {
            _me = simPosition();
        }
        var h = info.currentHeading;
        _heading = h != null ? Math.toDegrees(h).toFloat() : null;
        if (_me != null) {
            _link.tick(_me[0], _me[1]);
        } else {
            _link.tick(null, null);
        }
    }

    (:debug)
    private function simPosition() as Array<Number>? {
        if (AresBuild.SIM_LAT_E6 == 0 && AresBuild.SIM_LON_E6 == 0) {
            return null;
        }
        return [AresBuild.SIM_LAT_E6, AresBuild.SIM_LON_E6];
    }

    (:release)
    private function simPosition() as Array<Number>? {
        return null;
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

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        var m = w < h ? w : h;
        if (m >= 120) {
            _radar.draw(dc, w / 2, h / 2, m / 2 - 2, _feed, _link, _me, _heading);
        } else {
            _radar.drawCompact(dc, 0, 0, w, h, _feed, _link, _me, _heading);
        }
    }
}
