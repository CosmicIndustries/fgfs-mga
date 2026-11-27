# cosmic_modes.nas - formation modes for the Remora drones (Cosmic Ag docking demo)
#
# Ctrl-F (flying the mothership) steps through five formations. They apply to
# the drones that are out (released with Ctrl-K / Ctrl-Y); a drone out on its
# own takes its side's part:
#   0 Escort       both beside you (the docking script's own escort slot)
#   1 Port scouts ahead, starboard sprays behind
#   2 Starboard scouts ahead, port sprays behind
#   3 Both scout ahead
#   4 Both spray behind
# Scout (leading):  40 m ahead of its latch, 10 m outboard, 5 m above it; no
#                   spray, the sensor gimbal under the nose sweeps side to side.
# Spray (following): 22 m behind its latch, 16 m outboard, level with it (clear
#                   of the mothership's wingtip vortex); sprays once it is
#                   within 8 m of its slot.
# The drones top out near 82 kt, so a scout can only stay ahead of the
# mothership up to about 75 kt (you get a tip above that).
# Recall (Ctrl-K / Ctrl-Y) from a scout or spray slot first brings the drone
# back to the escort slot beside you, then the docking script takes it home
# as before.
#
# This file does not change Nasal/cosmic_formation.nas. It hooks in at run
# time: it wraps cosmic_formation.fly_free (swaps the escort aim for each
# drone's formation slot during that drone's call) and
# cosmic_formation.drone_toggle (the recall step above).
# Model side: Aircraft/Cosmic-AgParasite/Models/remora-modes.xml (spray
# particles and the scout gimbal), driven by these properties on each AI drone:
#   cosmic/spray     1 while spraying
#   cosmic/scouting  1 while scouting
#   cosmic/scan-deg  gimbal sweep angle
#   cosmic/blink     scout light
var AIMS = {                      # fwd, outboard, down (m) from the latch
    lead:   [40.0, 10.0, -5.0],
    follow: [-22.0, 16.0, 0.0],
};
var PRESETS = [
    { m: ["escort", "escort"], name: "Escort: both drones beside you" },
    { m: ["lead", "follow"],   name: "Port drone scouts ahead, starboard sprays behind" },
    { m: ["follow", "lead"],   name: "Starboard drone scouts ahead, port sprays behind" },
    { m: ["lead", "lead"],     name: "Both drones scout ahead" },
    { m: ["follow", "follow"], name: "Both drones spray behind" },
];
var SPRAY_NEAR_M = 8.0;           # sprays only once this close to its slot
var REJOIN_M = 6.0;               # back beside you: hand over to docking
var SCOUT_MAX_KT = 76;            # above this a scout falls behind
var SCAN_DEG = 35; var SCAN_HZ = 0.25;

var F = nil;                      # the cosmic_formation namespace
var preset = 0;
var rejoin = [0, 0];              # recalled from a scout/spray slot, flying back beside you
var flags = [[0, 0], [0, 0]];     # [spray, scout] per drone (also read by tests)
var orig = { fly_free: nil, drone_toggle: nil };
var escort0 = nil;
var hooked = 0; var warn_at = 0;

var mode_of = func(i) {
    if (F.demo_cycle or rejoin[i]) return "escort";
    return PRESETS[preset].m[i];
};
var aim_of = func(m) { return m == "escort" ? escort0 : AIMS[m]; };
var is_out = func(s) { return s.state == "drop" or s.state == "escort"; };

# drone position from its latch c: fwd, right, down (m)
var rel = func(i, c) {
    var s = F.S[i];
    var rn = (s.lat - c.lat()) * F.M_LAT;
    var re = (s.lon - c.lon()) * F.M_LON * math.cos(c.lat() * F.R);
    var ch = math.cos(F.L.hdg * F.R); var sh = math.sin(F.L.hdg * F.R);
    return [rn * ch + re * sh, -rn * sh + re * ch, c.alt() - s.alt];
};
var dist_to = func(i, r, a) {
    var side = F.DRONES[i].side > 0 ? 1 : -1;
    var e0 = r[0] - a[0]; var e1 = r[1] - side * a[1]; var e2 = r[2] - a[2];
    return math.sqrt(e0 * e0 + e1 * e1 + e2 * e2);
};

var set_flags = func(i, spray, scout, t) {
    flags[i] = [spray, scout];
    var n = F.nodes[F.DRONES[i].cs];
    if (n == nil or !F.ok(n)) return;
    if (n.getValue("cosmic/spray") != spray) n.setValue("cosmic/spray", spray);
    if (n.getValue("cosmic/scouting") != scout) n.setValue("cosmic/scouting", scout);
    n.setValue("cosmic/scan-deg", scout ? SCAN_DEG * math.sin(2 * math.pi * SCAN_HZ * t) : 0);
    n.setValue("cosmic/blink", scout and math.mod(t, 1.0) < 0.15 ? 1 : 0);
};

# wraps cosmic_formation.fly_free: the drone flies to its formation slot
var fly_free = func(i, c, vs, dt, t) {
    var m = mode_of(i);
    F.AIM_ESCORT = aim_of(m);
    var err = [];
    call(orig.fly_free, [i, c, vs, dt, t], nil, nil, err);
    F.AIM_ESCORT = escort0;
    if (size(err)) die(err[0]);
    var s = F.S[i];
    if (rejoin[i]) {
        if (!is_out(s)) rejoin[i] = 0;
        elsif (s.state == "escort" and dist_to(i, rel(i, c), escort0) < REJOIN_M) {
            rejoin[i] = 0;
            orig.drone_toggle(i);          # beside you: the docking script takes over
        }
    }
    var spray = 0; var scout = 0;
    if (s.state == "escort" and !rejoin[i]) {
        spray = (m == "follow" and dist_to(i, rel(i, c), AIMS.follow) < SPRAY_NEAR_M) ? 1 : 0;
        scout = (m == "lead") ? 1 : 0;
    }
    set_flags(i, spray, scout, t);
};

# wraps cosmic_formation.drone_toggle: recall from a formation slot goes via the escort slot
var drone_toggle = func(i) {
    var s = F.S[i]; var name = F.DRONES[i].name;
    if (is_out(s) and rejoin[i]) { F.tip(name ~ " drone is already on its way back"); return; }
    if (is_out(s) and mode_of(i) != "escort") {
        rejoin[i] = 1; s.want_open = 1;
        if (contains(F.L, "tas") and F.L.tas > 78)
            F.tip(name ~ " drone coming back alongside: slow to about 70 kt with 15 flaps so it can catch you");
        else F.tip(name ~ " drone coming back alongside, then into the bay");
        return;
    }
    orig.drone_toggle(i);
};

var key_formation = func {
    if (!hooked) { gui.popupTip("Drone formations are not ready yet", 3); return; }
    preset += 1; if (preset >= size(PRESETS)) preset = 0;
    var msg = PRESETS[preset].name;
    if (!is_out(F.S[0]) and !is_out(F.S[1])) msg ~= " (release a drone with Ctrl-K or Ctrl-Y)";
    elsif ((PRESETS[preset].m[0] == "lead" or PRESETS[preset].m[1] == "lead")
           and contains(F.L, "tas") and F.L.tas > SCOUT_MAX_KT)
        msg ~= ". Slow to about 70 kt so the scouts can stay ahead";
    F.tip(msg);
};

# 4 times a second: flags off for docked drones, speed tip for scouts
var housekeeping = func {
    if (!hooked) return;
    var t = F.now();
    foreach (var i; [0, 1]) {
        var s = F.S[i];
        if (!is_out(s) and (flags[i][0] or flags[i][1])) set_flags(i, 0, 0, t);
        if (!is_out(s)) rejoin[i] = 0;
    }
    var scouting = flags[0][1] or flags[1][1];
    if (scouting and contains(F.L, "tas") and F.L.tas > SCOUT_MAX_KT and t >= warn_at) {
        warn_at = t + 20;
        F.tip(sprintf("%.0f kt is faster than a scout can stay ahead; slow to about 70 kt", F.L.tas));
    }
};

# one log line per drone (sim tests: cosmic_modes.report())
var report = func {
    if (!hooked) { print("[COSMIC] modes: not hooked"); return; }
    foreach (var i; [0, 1]) {
        var s = F.S[i]; var n = F.nodes[F.DRONES[i].cs];
        var np = func(p) { return (n != nil and F.ok(n)) ? (n.getValue(p) or 0) : -1; };
        printf("[COSMIC] modes: %s %s%s | %s | spray %d scout %d (model %d/%d) | mothership %.0f kt",
               F.DRONES[i].name, mode_of(i), rejoin[i] ? " (coming back)" : "",
               contains(s, "dbg") ? s.dbg : s.state, flags[i][0], flags[i][1],
               np("cosmic/spray"), np("cosmic/scouting"), contains(F.L, "tas") ? F.L.tas : 0);
    }
};

# ns: the cosmic_formation namespace (tests pass their own)
var install = func(ns = nil) {
    if (hooked) return 1;
    if (ns == nil) {
        if (!contains(globals, "cosmic_formation")) return 0;
        ns = globals.cosmic_formation;
    }
    foreach (var k; ["fly_free", "drone_toggle", "AIM_ESCORT", "S", "DRONES", "L", "nodes", "tip",
                     "ok", "now", "M_LAT", "M_LON", "R", "demo_cycle"])
        if (!contains(ns, k)) { print("[COSMIC] formation modes not hooked: cosmic_formation has no ", k); return 0; }
    F = ns;
    orig.fly_free = F.fly_free; orig.drone_toggle = F.drone_toggle;
    escort0 = [F.AIM_ESCORT[0], F.AIM_ESCORT[1], F.AIM_ESCORT[2]];
    F.fly_free = fly_free; F.drone_toggle = drone_toggle;
    hooked = 1;
    print("[COSMIC] formation modes ready: Ctrl-F cycles escort / scout / spray");
    return 1;
};

var hk_timer = nil;
setlistener("/sim/signals/fdm-initialized", func(n) {
    if (!n.getBoolValue() or hooked) return;
    settimer(func {
        if (!install()) return;
        hk_timer = maketimer(0.25, housekeeping); hk_timer.start();
    }, 1);
}, 1, 0);
