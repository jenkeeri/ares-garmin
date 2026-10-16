import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;

//! Fetches the feed either from the HTTPS relay (makeWebRequest, proxied by Garmin Connect
//! Mobile) or from the Ares Bridge iPhone app (BLE phone-app messages). Driven by tick().
class AresLink {
    const TRANSPORT_RELAY = 0;
    const TRANSPORT_PHONE = 1;
    const TIMEOUT_MS = 20000;

    var feed as AresFeed;
    //! Last error code (Communications error / HTTP status), 0 = none.
    var lastError as Number = 0;
    var transport as Number = TRANSPORT_RELAY;

    private var _url as String = "";
    private var _key as String = "";
    private var _pollMs as Number = 5000;
    private var _maxEntities as Number = 24;
    private var _inFlightSince as Number = 0;
    private var _lastReqAt as Number = 0;
    private var _failures as Number = 0;
    private var _onAlert as Method? = null;
    private var _phoneListener as AresPhoneListener;

    //! `onAlert` receives (level as Number) when a payload produced an alert.
    function initialize(f as AresFeed, maxEntities as Number, onAlert as Method?) {
        feed = f;
        _maxEntities = maxEntities;
        _onAlert = onAlert;
        _phoneListener = new AresPhoneListener(self);
        reloadSettings();
        if (Communications has :registerForPhoneAppMessages) {
            Communications.registerForPhoneAppMessages(method(:onPhoneMessage));
        }
    }

    function reloadSettings() as Void {
        _url = AresSettings.str("relayUrl", AresBuild.RELAY_URL);
        // Tolerate a trailing slash in the configured URL.
        if (_url.length() > 0 && _url.toCharArray()[_url.length() - 1] == '/') {
            _url = _url.substring(0, _url.length() - 1) as String;
        }
        _key = AresSettings.str("relayKey", AresBuild.RELAY_KEY);
        transport = AresSettings.num("transport", -1);
        if (transport < 0) {
            transport = AresBuild.TRANSPORT;
        }
        var poll = AresSettings.num("pollSeconds", 0);
        if (poll <= 0) {
            poll = AresBuild.POLL_SECONDS;
        }
        _pollMs = (poll < 2 ? 2 : poll) * 1000;
        _lastReqAt = 0;
        AresDebug.log("settings url=" + _url + " transport=" + transport + " pollMs=" + _pollMs);
    }

    function isConfigured() as Boolean {
        return transport == TRANSPORT_PHONE || _url.length() > 0;
    }

    //! Call about once per second with the watch position in micro-degrees (or null).
    function tick(latE6 as Number?, lonE6 as Number?) as Void {
        var now = System.getTimer();
        if (_inFlightSince != 0) {
            if (now - _inFlightSince < TIMEOUT_MS) {
                return;
            }
            _inFlightSince = 0;
            _fail(-300);
        }
        var interval = _pollMs;
        if (feed.pollHint > 0 && feed.pollHint * 1000 > interval) {
            interval = feed.pollHint * 1000;
        }
        if (_failures > 0) {
            var backoff = _failures * 5000;
            interval += backoff > 30000 ? 30000 : backoff;
        }
        if (_lastReqAt != 0 && now - _lastReqAt < interval) {
            return;
        }
        if (!isConfigured()) {
            lastError = -1;
            return;
        }
        _lastReqAt = now;
        _inFlightSince = now;
        AresDebug.log("request transport=" + transport + " q=" + feed.seq + " pos=" + (latE6 != null));
        if (transport == TRANSPORT_PHONE) {
            var msg = { "c" => "poll", "q" => feed.seq, "n" => _maxEntities } as Dictionary<Communications.TransmitKeyType, Communications.TransmitType>;
            if (latE6 != null && lonE6 != null) {
                msg.put("lat", latE6);
                msg.put("lon", lonE6);
            }
            Communications.transmit(msg, null, _phoneListener);
        } else {
            var params = { "q" => feed.seq, "n" => _maxEntities } as Dictionary<Object, Object>;
            if (latE6 != null && lonE6 != null) {
                params.put("lat", latE6);
                params.put("lon", lonE6);
            }
            if (_key.length() > 0) {
                params.put("k", _key);
            }
            Communications.makeWebRequest(_url + "/v1/feed", params, {
                :method => Communications.HTTP_REQUEST_METHOD_GET,
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            }, method(:onWebResponse));
        }
    }

    function onWebResponse(code as Number, data as Dictionary or String or Null) as Void {
        _inFlightSince = 0;
        AresDebug.log("response code=" + code);
        if (code == 200 && data instanceof Dictionary) {
            _ok(data);
        } else {
            _fail(code);
        }
    }

    function onPhoneMessage(msg as Communications.PhoneAppMessage) as Void {
        var data = msg.data;
        if (data instanceof Dictionary) {
            _inFlightSince = 0;
            _ok(data);
        }
    }

    //! Phone transmit failed (watch could not reach the phone app).
    function onTransmitError() as Void {
        _inFlightSince = 0;
        _fail(-104);
    }

    private function _ok(data as Dictionary) as Void {
        _failures = 0;
        lastError = 0;
        var alert = feed.apply(data);
        if (alert > 0 && _onAlert != null) {
            _onAlert.invoke(alert);
        }
    }

    private function _fail(code as Number) as Void {
        lastError = code;
        // Response too large / out of memory: ask for fewer entities next time.
        if ((code == -402 || code == -403) && _maxEntities > 8) {
            _maxEntities = _maxEntities * 2 / 3;
        }
        if (_failures < 10) {
            _failures++;
        }
    }

    //! Short human readable link status for the UI.
    function statusText() as String {
        if (!isConfigured()) {
            return "NO RELAY URL";
        }
        if (lastError == 0) {
            var age = feed.linkAge();
            return age < 0 ? "CONNECTING" : "";
        }
        var c = lastError;
        var t = "ERR";
        if (c == -104 || c == -2 || c == -3 || c == -4) {
            t = "NO PHONE";
        } else if (c == -300) {
            t = "TIMEOUT";
        } else if (c == 401 || c == 403) {
            t = "BAD KEY";
        } else if (c == -1001) {
            t = "NEED HTTPS";
        } else if (c == -402 || c == -403) {
            t = "TOO BIG";
        } else if (c == -400 || c == -1002) {
            // Non-JSON reply; with a quick tunnel this usually means the tunnel/relay is down.
            t = "RELAY ERR";
        } else if (c == 404 || c == 502 || c == 503 || c == 530 || c == 1033) {
            t = "RELAY DOWN";
        } else if (c == -101) {
            t = "BUSY";
        }
        return t + " " + c;
    }
}

class AresPhoneListener extends Communications.ConnectionListener {
    private var _link as WeakReference;

    function initialize(link as AresLink) {
        ConnectionListener.initialize();
        _link = link.weak();
    }

    function onComplete() as Void {
    }

    function onError() as Void {
        var l = _link.get();
        if (l != null) {
            (l as AresLink).onTransmitError();
        }
    }
}
