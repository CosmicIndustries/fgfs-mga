# MGA launcher extras: applies the launcher's fuel, payload, random-failure, seat-position and
# altimeter choices once the flight model is ready. Everything is read from /sim/mga-extras/;
# a value below 0 (or missing) means "leave the aircraft's own value".

var ROOT = "/sim/mga-extras/";
var getnum = func(name) {
    var v = getprop(ROOT ~ name);
    if (v == nil or v == "") return -1;
    var n = num(v);
    return n == nil ? -1 : n;
};

var report = [];
var note = func(text) { append(report, text); logprint(LOG_INFO, "mga-launcher-extras: ", text); };

var apply_fuel = func {
    var f = getnum("fuel-fraction");
    if (f < 0) return;
    var n = 0;
    foreach (var t; props.globals.getNode("/consumables/fuel", 1).getChildren("tank")) {
        var cap = t.getValue("capacity-gal_us");
        if (cap == nil or cap <= 0) continue;
        if (t.getValue("selected") == 0 and t.getValue("hidden")) continue;
        t.setValue("level-gal_us", cap * f);
        n += 1;
    }
    note(sprintf("fuel %d%% in %d tank(s)", f * 100, n));
};

var PAYLOAD = [
    ["pilot-lb",    "pilot|left front|front left|captain|seat 1|driver"],
    ["front-lb",    "copilot|co-pilot|right front|front right|front pass|passenger 1|instructor|seat 2"],
    ["rear-lb",     "rear|back|aft pass|passenger [23]|seat [34]"],
    ["baggage-lb",  "baggage|cargo|luggage"],
];
var apply_payload = func {
    var weights = props.globals.getNode("/payload", 1).getChildren("weight");
    foreach (var p; PAYLOAD) {
        var lb = getnum(p[0]);
        if (lb < 0) continue;
        var hits = [];
        foreach (var w; weights) {
            var name = string.lc(w.getValue("name") or "");
            if (regex_any(name, p[1])) append(hits, w);
        }
        if (!size(hits)) { note(p[0] ~ ": this aircraft has no matching seat or station"); continue; }
        foreach (var w; hits) {
            var each = lb / size(hits);
            var mx = w.getValue("max-lb");
            if (mx != nil and mx > 0 and each > mx) each = mx;
            w.setValue("weight-lb", each);
        }
        note(sprintf("%s %d lb on %d station(s)", p[0], lb, size(hits)));
    }
};
var regex_any = func(text, alternatives) {
    foreach (var a; split("|", alternatives)) {
        # tiny matcher: plain substring, with [..] character classes for one character
        if (glob_find(text, a)) return 1;
    }
    return 0;
};
var glob_find = func(text, pat) {
    var cls = find("[", pat);
    if (cls < 0) return find(pat, text) >= 0;
    var close = find("]", pat);
    var pre = substr(pat, 0, cls);
    var set = substr(pat, cls + 1, close - cls - 1);
    var post = substr(pat, close + 1);
    for (var i = 0; i < size(set); i += 1) {
        if (find(pre ~ chr(set[i]) ~ post, text) >= 0) return 1;
    }
    return 0;
};

var apply_failures = func {
    var mtbf = getnum("random-mtbf");
    if (mtbf > 0) {
        setprop("/sim/failure-manager/global-mtbf", mtbf);
        if (contains(globals, "compat_failure_modes"))
            compat_failure_modes.apply_global_mtbf(mtbf);
        note(sprintf("random failures, one every %d min on average", mtbf / 60));
    }
};

var apply_seat = func {
    if (getprop(ROOT ~ "eye-set") != 1) return;
    var up = num(getprop(ROOT ~ "eye-up-m") or 0) or 0;
    var fwd = num(getprop(ROOT ~ "eye-fwd-m") or 0) or 0;
    var cfg = props.globals.getNode("/sim/view[0]/config", 1);
    var y = cfg.getValue("y-offset-m") or 0;
    var z = cfg.getValue("z-offset-m") or 0;
    cfg.setValue("y-offset-m", y + up);
    cfg.setValue("z-offset-m", z - fwd);   # FlightGear's z points aft
    if ((getprop("/sim/current-view/view-number") or 0) == 0) {
        setprop("/sim/current-view/y-offset-m", y + up);
        setprop("/sim/current-view/z-offset-m", z - fwd);
    }
    note(sprintf("pilot eye %+.2f m up, %+.2f m forward", up, fwd));
};

var apply_altimeter = func {
    var inhg = getnum("altimeter-inhg");
    if (inhg < 25 or inhg > 33) return;
    foreach (var a; props.globals.getNode("/instrumentation", 1).getChildren("altimeter"))
        a.setValue("setting-inhg", inhg);
    note(sprintf("altimeter %.2f inHg", inhg));
};


# engine running at start: battery, alternator, avionics, fuel pump, mixture rich, mags BOTH, crank
var start_timer = nil;
var apply_start = func {
    if (getprop(ROOT ~ "start-running") != 1) return;
    if (getprop("/engines/engine[0]/running")) { note("engine already running"); return; }
    foreach (var p; ["/controls/electrical/switches/battery", "/controls/electrical/battery",
                     "/controls/electrical/switches/alternator", "/controls/electrical/alternator",
                     "/controls/electrical/switches/avionics-master", "/controls/electrical/avionics-master",
                     "/controls/engines/engine[0]/fuel-pump", "/controls/fuel/switches/pump"])
        if (getprop(p) != nil) setprop(p, 1);
    setprop("/controls/engines/engine[0]/mixture", 1);
    setprop("/controls/engines/engine[0]/throttle", 0.12);
    # aircraft with a key switch (PA28: 0 off .. 3 both, 4 start) crank through the key, others through the starter
    var key = getprop("/controls/engines/engine[0]/magnetos-switch") != nil;
    setprop("/controls/engines/engine[0]/magnetos", 3);
    if (key) setprop("/controls/engines/engine[0]/magnetos-switch", 4);
    else setprop("/controls/engines/engine[0]/starter", 1);
    var tries = 0;
    start_timer = maketimer(0.5, func {
        tries += 1;
        if (getprop("/engines/engine[0]/running") or tries > 16) {
            if (key) setprop("/controls/engines/engine[0]/magnetos-switch", 3);
            else setprop("/controls/engines/engine[0]/starter", 0);
            if (getprop("/controls/fuel/switches/pump") != nil) setprop("/controls/fuel/switches/pump", 0);
            setprop("/controls/engines/engine[0]/throttle", 0.08);
            start_timer.stop();
            setprop(ROOT ~ "start-result", getprop("/engines/engine[0]/running") ? "running" : "did not start");
        }
    });
    start_timer.start();
    note("engine start sequence");
};

# reset the flight after a crash or structural damage
var crash_pending = 0;
var crash_timer = nil;
var crash_check = func(n) {
    if (!n.getBoolValue() or crash_pending or getprop(ROOT ~ "crash-reset") != 1) return;
    crash_pending = 1;
    screen.log.write("Crash: resetting the flight in 3 seconds");
    crash_timer = maketimer(3, func { crash_pending = 0; fgcommand("reset"); });
    crash_timer.singleShot = 1;
    crash_timer.start();
};
var crash_watching = 0;
var watch_crashes = func {
    if (getprop(ROOT ~ "crash-reset") != 1 or crash_watching) return;
    crash_watching = 1;
    setlistener("/sim/crashed", crash_check, 0, 0);
    foreach (var part; ["nose", "lwing", "rwing", "htail", "vtail"])
        setlistener("/fdm/jsbsim/crash-stress/" ~ part ~ "-damaged", crash_check, 0, 0);
    note("crash reset on");
};

# auto mixture: full rich up to 3,000 ft density altitude, then leaned about 4 % per 1,000 ft
var mix_timer = nil;
var watch_mixture = func {
    if (getprop(ROOT ~ "auto-mixture") != 1 or mix_timer != nil) return;
    mix_timer = maketimer(1, func {
        if (!getprop("/engines/engine[0]/running")) return;
        var da = getprop("/environment/density-altitude-ft");
        if (da == nil) da = getprop("/position/altitude-ft") or 0;
        var m = 1.0 - math.max(0, da - 3000) / 1000 * 0.04;
        setprop("/controls/engines/engine[0]/mixture", math.max(0.6, math.min(1.0, m)));
    });
    mix_timer.start();
    note("auto mixture on");
};

var timer = nil;   # kept here so the timer is not garbage-collected

var main = func(addon) {
    setlistener("/sim/signals/fdm-initialized", func(n) {
        if (!n.getBoolValue()) return;   # runs again after a reset, so the choices come back
        report = [];
        # give the aircraft's own start-up scripts two seconds first, so these choices win
        timer = maketimer(2, func {
            foreach (var f; [apply_fuel, apply_payload, apply_failures, apply_seat, apply_altimeter, apply_start, watch_crashes, watch_mixture]) {
                var err = [];
                call(f, [], nil, nil, err);
                if (size(err)) logprint(LOG_ALERT, "mga-launcher-extras: ", err[0], " at line ", err[2] or "?");
            }
            if (size(report)) {
                var text = report[0];
                for (var i = 1; i < size(report); i += 1) text = text ~ "; " ~ report[i];
                setprop(ROOT ~ "applied", text);
            }
        });
        timer.singleShot = 1;
        timer.start();
    }, 1, 0);
};
