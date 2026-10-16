import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Position;
import Toybox.System;
import Toybox.WatchUi;

//! Garmin map (with own track) showing every feed entity as a coloured dot + label.
//! START toggles browse mode (pan/zoom with the map controls), BACK returns to preview/radar.
class AresMapPage extends WatchUi.MapTrackView {
    private var _seq as Number = -1;
    private var _areaRange as Number = 0;
    private var _areaSet as Boolean = false;
    private var _icons as Dictionary<Number, Graphics.BufferedBitmapReference> = {} as Dictionary<Number, Graphics.BufferedBitmapReference>;

    function initialize() {
        MapTrackView.initialize();
        setMapMode(WatchUi.MAP_MODE_PREVIEW);
        var ds = System.getDeviceSettings();
        setScreenVisibleArea(0, 0, ds.screenWidth, ds.screenHeight);
        var p = aresState().pos;
        _setArea(p != null ? p : [0, 0] as Array<Number>, 500);
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var s = aresState();
        if (s.feed.receivedAt != _seq) {
            _seq = s.feed.receivedAt;
            _setMarkers(s);
        }
        var range = s.radar.fixedRange != 0 ? s.radar.fixedRange : s.radar.lastRange;
        if (s.pos != null && getMapMode() == WatchUi.MAP_MODE_PREVIEW && (!_areaSet || range != _areaRange)) {
            _setArea(s.pos as Array<Number>, range);
            _areaRange = range;
            _areaSet = true;
        }
        MapTrackView.onUpdate(dc);
        var st = s.pos == null ? "NO GPS" : s.link.statusText();
        if (st.length() > 0) {
            dc.setColor(0xFFD000, Graphics.COLOR_BLACK);
            dc.drawText(dc.getWidth() / 2, dc.getHeight() / 8, Graphics.FONT_XTINY, st, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    function recenter() as Void {
        _areaSet = false;
        setMapMode(WatchUi.MAP_MODE_PREVIEW);
        WatchUi.requestUpdate();
    }

    private function _setArea(pos as Array<Number>, rangeM as Number) as Void {
        var dLatE6 = (rangeM / AresGeo.M_PER_E6).toNumber();
        var dLonE6 = (dLatE6 / AresGeo.cosLatOf(pos[0])).toNumber();
        setMapVisibleArea(_loc(pos[0] + dLatE6, pos[1] - dLonE6), _loc(pos[0] - dLatE6, pos[1] + dLonE6));
    }

    private function _setMarkers(s as AresState) as Void {
        var markers = [] as Array<WatchUi.MapMarker>;
        var ents = s.feed.entities;
        for (var i = 0; i < ents.size(); i++) {
            var en = ents[i];
            var m = new WatchUi.MapMarker(_loc(en[AresProto.I_LAT] as Number, en[AresProto.I_LON] as Number));
            m.setIcon(_icon(s.radar.colorOf(en, s.feed.ageOf(en))), 7, 7);
            m.setLabel(en[AresProto.I_LABEL] as String);
            markers.add(m);
        }
        if (markers.size() > 0) {
            setMapMarker(markers);
        } else {
            clear();
        }
    }

    private function _icon(color as Number) as Graphics.BufferedBitmapReference {
        var bmp = _icons.get(color);
        if (bmp == null) {
            bmp = Graphics.createBufferedBitmap({ :width => 14, :height => 14 });
            var dc = (bmp.get() as Graphics.BufferedBitmap).getDc();
            dc.setColor(Graphics.COLOR_TRANSPARENT, Graphics.COLOR_TRANSPARENT);
            dc.clear();
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(7, 7, 7);
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(7, 7, 5);
            _icons.put(color, bmp);
        }
        return bmp;
    }

    private function _loc(latE6 as Number, lonE6 as Number) as Position.Location {
        return new Position.Location({ :latitude => latE6 / 1000000.0d, :longitude => lonE6 / 1000000.0d, :format => :degrees });
    }
}

class AresMapDelegate extends WatchUi.BehaviorDelegate {
    private var _view as AresMapPage;

    function initialize(view as AresMapPage) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onSelect() as Boolean {
        _view.setMapMode(WatchUi.MAP_MODE_BROWSE);
        return true;
    }

    function onBack() as Boolean {
        if (_view.getMapMode() == WatchUi.MAP_MODE_BROWSE) {
            _view.recenter();
        } else {
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        }
        return true;
    }
}
