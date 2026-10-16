import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

//! Main page: full-screen radar plus a recording indicator.
class AresRadarView extends WatchUi.View {
    function initialize() {
        View.initialize();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var s = aresState();
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        var r = (w < h ? w : h) / 2 - 2;
        s.radar.draw(dc, w / 2, h / 2, r, s.feed, s.link, s.pos, s.heading);
        if (s.session != null) {
            // Red dot = recording, yellow = paused.
            dc.setColor(s.isRecording() ? 0xFF3030 : 0xFFD000, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(w / 2 - r * 3 / 5, h / 2 - r * 3 / 5, 7);
        }
    }
}

//! START = start/pause recording, UP/DOWN = zoom, MENU (hold UP) = menu,
//! BACK = exit (asks to save/discard if an activity was started).
class AresRadarDelegate extends WatchUi.BehaviorDelegate {
    function initialize() {
        BehaviorDelegate.initialize();
    }

    private var _enterAt as Number = -100000;

    //! Remember physical START presses; a screen tap never produces one.
    function onKeyPressed(evt as WatchUi.KeyEvent) as Boolean {
        if (evt.getKey() == WatchUi.KEY_ENTER) {
            _enterAt = System.getTimer();
        }
        return false;
    }

    //! Both START and screen taps arrive here; only toggle recording when START was just pressed.
    function onSelect() as Boolean {
        var now = System.getTimer();
        if (now - _enterAt < 1500) {
            _enterAt = -100000;
            aresState().toggleRecording();
            WatchUi.requestUpdate();
        }
        return true;
    }

    function onPreviousPage() as Boolean {
        aresState().radar.zoom(-1);
        WatchUi.requestUpdate();
        return true;
    }

    function onNextPage() as Boolean {
        aresState().radar.zoom(1);
        WatchUi.requestUpdate();
        return true;
    }

    function onMenu() as Boolean {
        AresMenus.pushMain();
        return true;
    }

    function onBack() as Boolean {
        if (aresState().session != null) {
            AresMenus.pushExit();
            return true;
        }
        return false;
    }
}
