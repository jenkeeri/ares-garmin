import Toybox.Graphics;
import Toybox.Lang;
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

    function onSelect() as Boolean {
        aresState().toggleRecording();
        WatchUi.requestUpdate();
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
