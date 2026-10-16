import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

module AresMenus {
    function pushMain() as Void {
        var s = aresState();
        var menu = new WatchUi.Menu2({ :title => Rez.Strings.MenuTitle });
        menu.addItem(new WatchUi.MenuItem(Rez.Strings.MenuMap, null, :map, null));
        menu.addItem(new WatchUi.MenuItem(Rez.Strings.MenuMessages, s.feed.messages.size().toString(), :messages, null));
        var rec = s.session == null ? Rez.Strings.MenuRecordStart : (s.isRecording() ? Rez.Strings.MenuRecordPause : Rez.Strings.MenuRecordResume);
        menu.addItem(new WatchUi.MenuItem(rec, null, :record, null));
        menu.addItem(new WatchUi.ToggleMenuItem(Rez.Strings.MenuHeadingUp, null, :headingUp, s.radar.headingUp, null));
        menu.addItem(new WatchUi.MenuItem(Rez.Strings.MenuRangeAuto, null, :rangeAuto, null));
        WatchUi.pushView(menu, new AresMainMenuDelegate(), WatchUi.SLIDE_UP);
    }

    function pushExit() as Void {
        var menu = new WatchUi.Menu2({ :title => Rez.Strings.ExitTitle });
        menu.addItem(new WatchUi.MenuItem(Rez.Strings.ExitResume, null, :resume, null));
        menu.addItem(new WatchUi.MenuItem(Rez.Strings.ExitSave, null, :save, null));
        menu.addItem(new WatchUi.MenuItem(Rez.Strings.ExitDiscard, null, :discard, null));
        WatchUi.pushView(menu, new AresExitMenuDelegate(), WatchUi.SLIDE_UP);
    }
}

class AresMainMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var s = aresState();
        var id = item.getId();
        if (id == :map) {
            var v = new AresMapPage();
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
            WatchUi.pushView(v, new AresMapDelegate(v), WatchUi.SLIDE_LEFT);
        } else if (id == :messages) {
            var mv = new AresMessagesView();
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
            WatchUi.pushView(mv, new AresMessagesDelegate(mv), WatchUi.SLIDE_LEFT);
        } else if (id == :record) {
            s.toggleRecording();
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        } else if (id == :headingUp) {
            s.radar.headingUp = (item as WatchUi.ToggleMenuItem).isEnabled();
            AresSettings.set("headingUp", s.radar.headingUp);
        } else if (id == :rangeAuto) {
            s.radar.fixedRange = 0;
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        }
    }
}

class AresExitMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :resume) {
            var s = aresState();
            if (!s.isRecording()) {
                s.toggleRecording();
            }
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            return;
        }
        aresState().finishRecording(id == :save);
        System.exit();
    }
}
