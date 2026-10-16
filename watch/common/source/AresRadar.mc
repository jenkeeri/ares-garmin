import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;

//! Heading-up tactical radar: own position in the centre, team / objectives / contacts around
//! it, range rings with automatic scale. Also provides a compact one-line rendering for small
//! data-field slots.
class AresRadar {
    const C_FRIEND = 0x3399FF;
    const C_ENEMY = 0xFF3030;
    const C_MEDIC = 0xFF3030;
    const C_SUPPORT = 0xFFD000;
    const C_HIT = 0x555555;
    const C_NEUTRAL = 0xFFFFFF;
    const C_CONTESTED = 0xFF9900;
    const C_RING = 0x2A2A2A;
    const C_TEXT = 0xCCCCCC;
    const BANNER_MS = 15000;
    const STALE_S = 120;

    //! 0 = auto, otherwise fixed radius in meters.
    var fixedRange as Number = 0;
    var headingUp as Boolean = true;
    var showLabels as Boolean = true;
    var lastRange as Number = 200;

    private var _steps as Array<Number> = [50, 100, 150, 200, 300, 500, 750, 1000, 1500, 2000, 3000, 5000, 10000] as Array<Number>;

    function initialize() {
    }

    //! Cycle fixed range (auto -> 100 -> ... -> auto). Used by the watch app buttons.
    function zoom(dir as Number) as Void {
        var idx = _steps.indexOf(fixedRange == 0 ? lastRange : fixedRange);
        idx = (idx < 0 ? 3 : idx) + dir;
        if (idx < 0 || idx >= _steps.size()) {
            fixedRange = 0;
        } else {
            fixedRange = _steps[idx];
        }
    }

    function colorOf(en as Array, ageS as Number) as Number {
        var kind = en[AresProto.I_KIND];
        var st = en[AresProto.I_STATE];
        if (kind == AresProto.K_FRIEND) {
            if (st == AresProto.S_MEDIC) {
                return C_MEDIC;
            } else if (st == AresProto.S_SUPPORT) {
                return C_SUPPORT;
            } else if (st == AresProto.S_HIT || st == AresProto.S_STALE || ageS > STALE_S) {
                return C_HIT;
            }
            return C_FRIEND;
        }
        if (kind == AresProto.K_ENEMY) {
            return ageS > STALE_S ? C_HIT : C_ENEMY;
        }
        if (kind == AresProto.K_OBJECTIVE || kind == AresProto.K_BASE) {
            return st == 1 ? C_FRIEND : (st == 2 ? C_ENEMY : (st == 3 ? C_CONTESTED : C_NEUTRAL));
        }
        if (kind == AresProto.K_HAZARD) {
            return C_CONTESTED;
        }
        return 0xB070FF;
    }

    //! Full radar into the circle (cx, cy, r). `pos` = [latE6, lonE6] or null; heading in degrees or null.
    function draw(dc as Graphics.Dc, cx as Number, cy as Number, r as Number, feed as AresFeed, link as AresLink,
                  pos as Array<Number>?, heading as Float?) as Void {
        var big = r > 150;
        var rot = (headingUp && heading != null) ? heading : 0.0f;
        var ents = feed.entities;
        var n = ents.size();

        // Project everything once: [east, north, dist, bearing] per entity.
        var proj = new [n];
        var cosLat = pos != null ? AresGeo.cosLatOf(pos[0]) : 1.0f;
        var need = 0.0f;
        var nearestObj = -1;
        var nearestObjD = 1.0e9f;
        for (var i = 0; i < n; i++) {
            var en = ents[i];
            if (pos == null) {
                continue;
            }
            var en2 = AresGeo.enu(pos[0], pos[1], en[AresProto.I_LAT] as Number, en[AresProto.I_LON] as Number, cosLat);
            var d = AresGeo.dist(en2[0], en2[1]);
            proj[i] = [en2[0], en2[1], d];
            var kind = en[AresProto.I_KIND];
            if (kind == AresProto.K_FRIEND && d < 2000.0f && d > need) {
                need = d;
            }
            if (kind == AresProto.K_OBJECTIVE && d < nearestObjD) {
                nearestObjD = d;
                nearestObj = i;
            }
        }
        if (nearestObj >= 0 && nearestObjD > need && nearestObjD < 5000.0f) {
            need = nearestObjD;
        }
        var range = fixedRange;
        if (range == 0) {
            range = _steps[_steps.size() - 1];
            for (var s = 0; s < _steps.size(); s++) {
                if (_steps[s] >= need * 1.08f) {
                    range = _steps[s];
                    break;
                }
            }
        }
        lastRange = range;

        // Rings
        dc.setPenWidth(big ? 2 : 1);
        dc.setColor(C_RING, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(cx, cy, r);
        dc.drawCircle(cx, cy, r / 2);
        dc.setColor(0x777777, Graphics.COLOR_TRANSPARENT);
        if (big) {
            dc.drawText(cx + r / 2 * 7 / 10 + 4, cy - r / 2 * 7 / 10 - 4, Graphics.FONT_XTINY, AresGeo.fmtDist(range / 2.0f), Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        }
        // North tick
        if (headingUp && heading != null) {
            var a = Math.toRadians(-rot);
            var nx = cx + (r - (big ? 14 : 8)) * Math.sin(a);
            var ny = cy - (r - (big ? 14 : 8)) * Math.cos(a);
            dc.setColor(C_ENEMY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(nx, ny, big ? Graphics.FONT_XTINY : Graphics.FONT_XTINY, "N", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        var blink = (System.getTimer() / 500) % 2 == 0;
        var scale = r.toFloat() / range;
        var rr = (r - (big ? 10 : 5)).toFloat();
        var dot = big ? 9 : 5;
        // Draw lower-priority kinds first so friendlies end up on top.
        var order = [AresProto.K_HAZARD, AresProto.K_WAYPOINT, AresProto.K_BASE, AresProto.K_OBJECTIVE, AresProto.K_ENEMY, AresProto.K_FRIEND];
        var labels = [] as Array<Array>;
        if (pos != null) {
            var sinR = Math.sin(Math.toRadians(rot)).toFloat();
            var cosR = Math.cos(Math.toRadians(rot)).toFloat();
            for (var o = 0; o < order.size(); o++) {
                for (var i = n - 1; i >= 0; i--) {
                    var en = ents[i];
                    if (en[AresProto.I_KIND] != order[o]) {
                        continue;
                    }
                    var p = proj[i] as Array<Float>;
                    // Rotate world -> screen (heading-up), y grows downward.
                    var sx = (p[0] * cosR - p[1] * sinR) * scale;
                    var sy = -(p[0] * sinR + p[1] * cosR) * scale;
                    var clamped = false;
                    var len = Math.sqrt(sx * sx + sy * sy);
                    if (len > rr) {
                        sx = sx * rr / len;
                        sy = sy * rr / len;
                        clamped = true;
                    }
                    var age = feed.ageOf(en);
                    var col = colorOf(en, age);
                    var st = en[AresProto.I_STATE];
                    if (en[AresProto.I_KIND] == AresProto.K_FRIEND && st == AresProto.S_MEDIC && !blink) {
                        col = 0x660000;
                    }
                    _symbol(dc, cx + sx.toNumber(), cy + sy.toNumber(), dot, en, col, clamped);
                    if (big && showLabels && !clamped) {
                        labels.add([cx + sx.toNumber(), cy + sy.toNumber() + dot + 1, _shortLabel(en), col == C_HIT ? 0x777777 : C_TEXT]);
                    }
                }
            }
            _drawLabels(dc, labels);
        }

        // Own position marker
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var sz = big ? 12 : 7;
        dc.fillPolygon([[cx, cy - sz], [cx + sz * 2 / 3, cy + sz * 2 / 3], [cx, cy + sz / 3], [cx - sz * 2 / 3, cy + sz * 2 / 3]]);

        if (big) {
            _header(dc, cx, cy, r, feed, link, pos, nearestObj, proj);
            _footer(dc, cx, cy, r, feed, range);
            var banner = feed.activeBanner(BANNER_MS);
            if (banner != null) {
                _banner(dc, cx, cy, r, banner, feed.bannerPrio);
            }
        } else if (pos == null || link.statusText().length() > 0) {
            dc.setColor(C_SUPPORT, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy + r / 3, Graphics.FONT_XTINY, pos == null ? "NO GPS" : link.statusText(), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    //! Labels were collected lowest priority first; place them in reverse so friendlies win,
    //! and drop any label that would overlap one already drawn.
    private function _drawLabels(dc as Graphics.Dc, labels as Array<Array>) as Void {
        var h = dc.getFontHeight(Graphics.FONT_XTINY);
        var placed = [] as Array<Number>;
        for (var i = labels.size() - 1; i >= 0; i--) {
            var lb = labels[i];
            var x = lb[0] as Number;
            var y = lb[1] as Number;
            var txt = lb[2] as String;
            var hw = dc.getTextWidthInPixels(txt, Graphics.FONT_XTINY) / 2 + 1;
            var hit = false;
            for (var j = 0; j < placed.size(); j += 4) {
                if (x - hw < placed[j + 2] && x + hw > placed[j] && y < placed[j + 3] && y + h > placed[j + 1]) {
                    hit = true;
                    break;
                }
            }
            if (hit) {
                continue;
            }
            placed.addAll([x - hw, y, x + hw, y + h]);
            dc.setColor(lb[3] as Number, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, y, Graphics.FONT_XTINY, txt, Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    private function _shortLabel(en as Array) as String {
        var l = en[AresProto.I_LABEL] as String;
        if (en[AresProto.I_KIND] == AresProto.K_OBJECTIVE && l.find("OBJ ") == 0 && l.length() > 4) {
            return l.substring(4, l.length()) as String;
        }
        return l.length() > 6 ? l.substring(0, 6) as String : l;
    }

    private function _symbol(dc as Graphics.Dc, x as Number, y as Number, s as Number, en as Array, col as Number, clamped as Boolean) as Void {
        var kind = en[AresProto.I_KIND];
        dc.setColor(col, Graphics.COLOR_TRANSPARENT);
        if (clamped) {
            s = s * 2 / 3;
        }
        if (kind == AresProto.K_FRIEND) {
            if (clamped) {
                dc.drawCircle(x, y, s);
            } else {
                dc.fillCircle(x, y, s);
                if (en[AresProto.I_STATE] == AresProto.S_HIT) {
                    dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
                    dc.drawLine(x - s / 2, y - s / 2, x + s / 2, y + s / 2);
                    dc.drawLine(x - s / 2, y + s / 2, x + s / 2, y - s / 2);
                }
            }
        } else if (kind == AresProto.K_ENEMY) {
            var pts = [[x, y - s], [x + s, y + s * 3 / 4], [x - s, y + s * 3 / 4]];
            if (clamped) {
                dc.drawLine(x, y - s, x + s, y + s * 3 / 4);
                dc.drawLine(x + s, y + s * 3 / 4, x - s, y + s * 3 / 4);
                dc.drawLine(x - s, y + s * 3 / 4, x, y - s);
            } else {
                dc.fillPolygon(pts);
            }
        } else if (kind == AresProto.K_OBJECTIVE) {
            var t = s + 3;
            var pts = [[x, y - t], [x + t, y], [x, y + t], [x - t, y]];
            if (clamped) {
                dc.drawLine(x, y - t, x + t, y);
                dc.drawLine(x + t, y, x, y + t);
                dc.drawLine(x, y + t, x - t, y);
                dc.drawLine(x - t, y, x, y - t);
            } else {
                dc.fillPolygon(pts);
            }
        } else if (kind == AresProto.K_BASE) {
            dc.drawRectangle(x - s, y - s, s * 2, s * 2);
            dc.drawRectangle(x - s + 2, y - s + 2, s * 2 - 4, s * 2 - 4);
        } else if (kind == AresProto.K_HAZARD) {
            dc.drawLine(x, y - s, x + s, y + s);
            dc.drawLine(x + s, y + s, x - s, y + s);
            dc.drawLine(x - s, y + s, x, y - s);
        } else {
            dc.drawLine(x - s, y - s, x + s, y + s);
            dc.drawLine(x - s, y + s, x + s, y - s);
        }
    }

    private function _header(dc as Graphics.Dc, cx as Number, cy as Number, r as Number, feed as AresFeed, link as AresLink,
                             pos as Array<Number>?, nearestObj as Number, proj as Array) as Void {
        var y = cy - r + r / 7;
        var status = pos == null ? "NO GPS" : link.statusText();
        if (status.length() > 0) {
            dc.setColor(C_SUPPORT, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, y, Graphics.FONT_XTINY, status, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }
        if (nearestObj >= 0) {
            var en = feed.entities[nearestObj];
            var p = proj[nearestObj] as Array<Float>;
            var b = AresGeo.bearingDeg(p[0], p[1]);
            dc.setColor(colorOf(en, 0), Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, y, Graphics.FONT_XTINY,
                (en[AresProto.I_LABEL] as String) + " " + AresGeo.fmtDist(p[2]) + " " + AresGeo.cardinal(b),
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    private function _footer(dc as Graphics.Dc, cx as Number, cy as Number, r as Number, feed as AresFeed, range as Number) as Void {
        var ok = 0;
        var med = 0;
        var down = 0;
        var ents = feed.entities;
        for (var i = 0; i < ents.size(); i++) {
            var en = ents[i];
            if (en[AresProto.I_KIND] != AresProto.K_FRIEND) {
                continue;
            }
            var st = en[AresProto.I_STATE];
            if (st == AresProto.S_MEDIC) {
                med++;
            } else if (st == AresProto.S_HIT || st == AresProto.S_STALE) {
                down++;
            } else {
                ok++;
            }
        }
        var y = cy + r - r / 6;
        var x = cx;
        dc.setColor(C_FRIEND, Graphics.COLOR_TRANSPARENT);
        var txt = ok.toString();
        if (med > 0) {
            txt += "  +" + med;
        }
        if (down > 0) {
            txt += "  x" + down;
        }
        dc.drawText(x, y, Graphics.FONT_XTINY, txt, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(0x777777, Graphics.COLOR_TRANSPARENT);
        var linkAge = feed.linkAge();
        dc.drawText(x, y + r / 9, Graphics.FONT_XTINY,
            (fixedRange == 0 ? "A " : "") + AresGeo.fmtDist(range.toFloat()) + (linkAge > 15 ? "  " + AresGeo.fmtAge(linkAge) : ""),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function _banner(dc as Graphics.Dc, cx as Number, cy as Number, r as Number, text as String, prio as Number) as Void {
        var w = r * 3 / 2;
        var h = r / 2;
        var top = cy - r + r / 4;
        dc.setColor(prio >= AresProto.ALERT_URGENT ? 0x8B0000 : 0x0B3D91, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(cx - w / 2, top, w, h, 10);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        text = Graphics.fitTextToArea(text, Graphics.FONT_SMALL, w - 16, h - 8, true);
        dc.drawText(cx, top + h / 2, Graphics.FONT_SMALL, text, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! Small-slot rendering: arrow to the nearest objective plus distance and team status.
    function drawCompact(dc as Graphics.Dc, x as Number, y as Number, w as Number, h as Number, feed as AresFeed, link as AresLink,
                         pos as Array<Number>?, heading as Float?) as Void {
        var cy = y + h / 2;
        var status = pos == null ? "NO GPS" : link.statusText();
        var banner = feed.activeBanner(BANNER_MS);
        if (banner != null) {
            dc.setColor(feed.bannerPrio >= AresProto.ALERT_URGENT ? C_MEDIC : C_SUPPORT, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x + w / 2, cy, Graphics.FONT_XTINY, Graphics.fitTextToArea(banner, Graphics.FONT_XTINY, w - 4, h, true), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }
        if (status.length() > 0 || pos == null) {
            dc.setColor(C_SUPPORT, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x + w / 2, cy, Graphics.FONT_XTINY, status, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }
        var cosLat = AresGeo.cosLatOf(pos[0]);
        var best = -1;
        var bestD = 1.0e9f;
        var bestB = 0.0f;
        var ents = feed.entities;
        for (var i = 0; i < ents.size(); i++) {
            var en = ents[i];
            if (en[AresProto.I_KIND] != AresProto.K_OBJECTIVE) {
                continue;
            }
            var p = AresGeo.enu(pos[0], pos[1], en[AresProto.I_LAT] as Number, en[AresProto.I_LON] as Number, cosLat);
            var d = AresGeo.dist(p[0], p[1]);
            if (d < bestD) {
                bestD = d;
                best = i;
                bestB = AresGeo.bearingDeg(p[0], p[1]);
            }
        }
        if (best < 0) {
            dc.setColor(C_TEXT, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x + w / 2, cy, Graphics.FONT_XTINY, "NO OBJ", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }
        var en = ents[best];
        var col = colorOf(en, 0);
        var rel = bestB - (heading != null ? heading : 0.0f);
        var a = h < w ? h * 2 / 5 : w * 2 / 5;
        if (a > 30) {
            a = 30;
        }
        drawArrow(dc, x + a + 4, cy, a, rel, col);
        var font = h > 70 ? Graphics.FONT_MEDIUM : Graphics.FONT_SMALL;
        dc.setColor(col, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + 2 * a + 10, cy, font, _shortLabel(en) + " " + AresGeo.fmtDist(bestD), Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    function drawArrow(dc as Graphics.Dc, cx as Number, cy as Number, s as Number, deg as Float, col as Number) as Void {
        var a = Math.toRadians(deg);
        var sn = Math.sin(a);
        var cs = Math.cos(a);
        var pts = [[0, -s], [s * 2 / 3, s * 2 / 3], [0, s / 3], [-s * 2 / 3, s * 2 / 3]];
        var out = [];
        for (var i = 0; i < pts.size(); i++) {
            var px = pts[i][0];
            var py = pts[i][1];
            out.add([cx + (px * cs - py * sn).toNumber(), cy + (px * sn + py * cs).toNumber()]);
        }
        dc.setColor(col, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(out);
    }
}
