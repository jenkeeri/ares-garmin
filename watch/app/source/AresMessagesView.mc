import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

//! Recent orders/messages from the feed, newest first. UP/DOWN scroll, BACK returns.
class AresMessagesView extends WatchUi.View {
    var top as Number = 0;

    function initialize() {
        View.initialize();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var s = aresState();
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        var msgs = s.feed.messages;
        if (top >= msgs.size()) {
            top = msgs.size() > 0 ? msgs.size() - 1 : 0;
        }
        if (msgs.size() == 0) {
            dc.setColor(0x777777, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h / 2, Graphics.FONT_SMALL, WatchUi.loadResource(Rez.Strings.NoMessages) as String, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }
        var since = (System.getTimer() - s.feed.receivedAt) / 1000;
        var fh = dc.getFontHeight(Graphics.FONT_SMALL);
        var bw = w * 3 / 4;
        var y = h / 6;
        for (var i = top; i < msgs.size() && y < h * 5 / 6; i++) {
            var m = msgs[i];
            var prio = m[2] as Number;
            dc.setColor(prio >= AresProto.ALERT_URGENT ? 0xFF3030 : (prio == AresProto.ALERT_ORDER ? 0xFFD000 : 0x777777), Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, y, Graphics.FONT_XTINY, AresGeo.fmtAge((m[1] as Number) + since) + " ago", Graphics.TEXT_JUSTIFY_CENTER);
            y += dc.getFontHeight(Graphics.FONT_XTINY);
            var txt = Graphics.fitTextToArea(m[3] as String, Graphics.FONT_SMALL, bw, fh * 3, true);
            if (txt == null) {
                txt = "";
            }
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, y, Graphics.FONT_SMALL, txt, Graphics.TEXT_JUSTIFY_CENTER);
            y += dc.getTextDimensions(txt, Graphics.FONT_SMALL)[1] + fh / 2;
        }
    }
}

class AresMessagesDelegate extends WatchUi.BehaviorDelegate {
    private var _view as AresMessagesView;

    function initialize(view as AresMessagesView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onNextPage() as Boolean {
        _view.top++;
        WatchUi.requestUpdate();
        return true;
    }

    function onPreviousPage() as Boolean {
        if (_view.top > 0) {
            _view.top--;
        }
        WatchUi.requestUpdate();
        return true;
    }

    function onBack() as Boolean {
        aresState().feed.clearBanner();
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
