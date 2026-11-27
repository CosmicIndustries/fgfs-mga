# Offline test of cosmic_modes.nas with the real cosmic_formation.nas
# (Scripts/test_formation_modes.sh puts the stubs, the docking script and the
# modes module, wrapped as its own namespace, in front of this).
var NS = caller(0)[0];
if (!cosmic_modes.install(NS)) die("install failed");
var AGL_FT = 50; var BASE_FT = 3000;
var KS = [4, 4, 5, 4, 4, 3, 4, 5, 4, 8, 4, 4, 5, 4, 12, 4];
var run = func(kt, turn_dps, plan, recall_at, tmax) {
    # plan: [[t, preset, check_from, check_to], ...]
    GROUND_M = (BASE_FT - AGL_FT) * 0.3048;
    var V = kt * 0.514444; var nf = 0; var t = 0;
    L.lat = 32.2; L.lon = -83.1; L.alt = BASE_FT; L.hdg = 90; L.pitch = 2; L.roll = 0;
    L.agl = AGL_FT; L.tas = kt; L.gs = kt; L.trk = 90; L.vs = 0;
    cosmic_modes.preset = 0; cosmic_modes.rejoin = [0, 0];
    foreach (var i; [0, 1]) {
        var s = S[i];
        s.state = "docked"; s.door = 1; s.arm = 1; s.pc = nil; s.poff = nil; s.orate = nil; s.vslot = nil;
        s.arounds = 0; s.gnd = nil; s.gnd_at = 0; s.want_open = 1;
    }
    var released = 0; var recalled = 0; var latched = [nil, nil];
    var res = []; var cur = nil; var errmax = [0, 0]; var sprayf = [0, 0]; var scoutf = [0, 0]; var nchk = 0;
    var sepmin = 999; var bodymin = 999; var lowest = 999; var pi = 0;
    while (t < tmax) {
        var dt = KS[nf] / 120; nf += 1; if (nf >= size(KS)) nf = 0;
        t += dt; PROPS["/sim/time/elapsed-sec"] = t;
        L.roll = math.atan(V * turn_dps * R / 9.81) / R;
        L.hdg += turn_dps * dt; L.trk = L.hdg;
        L.lat += V * dt * math.cos(L.hdg * R) / 111132.95;
        L.lon += V * dt * math.sin(L.hdg * R) / (111319.49 * math.cos(L.lat * R));
        L.vn = V * math.cos(L.hdg * R); L.ve = V * math.sin(L.hdg * R); L.vd = 0;
        if (pi < size(plan) and t >= plan[pi][0]) {
            if (cur != nil) append(res, cur);
            cosmic_modes.preset = plan[pi][1] - 1; cosmic_modes.key_formation();
            cur = { p: plan[pi][1], a: plan[pi][2], b: plan[pi][3], err: [0, 0], spray: [0, 0], scout: [0, 0], n: 0 };
            pi += 1;
        }
        if (!recalled and t >= recall_at) { recalled = 1; drone_toggle(0); drone_toggle(1); }
        foreach (var i; [0, 1]) {
            var s = S[i]; var d = DRONES[i];
            var c = slot_coord(d, 0);
            var off = [(c.lat() - L.lat) * M_LAT, (c.lon() - L.lon) * M_LON * math.cos(c.lat() * R), L.alt * FT2M - c.alt()];
            var orate = [0, 0, 0];
            if (s.poff != nil) orate = [(off[0] - s.poff[0]) / dt, (off[1] - s.poff[1]) / dt, (off[2] - s.poff[2]) / dt];
            s.poff = off;
            s.orate = s.orate == nil ? orate : [s.orate[0] + (orate[0] - s.orate[0]) * 0.5,
                                                s.orate[1] + (orate[1] - s.orate[1]) * 0.5,
                                                s.orate[2] + (orate[2] - s.orate[2]) * 0.5];
            s.vslot = [L.vn + s.orate[0], L.ve + s.orate[1], L.vd + s.orate[2]];
            s.pc = c;
            if (!released) { phys_init(s, c, s.vslot, 0); s.state = "drop"; s.t = t; continue; }
            if (s.state == "docked") { if (latched[i] == nil and recalled) latched[i] = t - recall_at; continue; }
            fly_free(i, c, s.vslot, dt, t);
            if (s.state == "docked") continue;
            var r = cosmic_modes.rel(i, c);
            lowest = math.min(lowest, s.alt - GROUND_M);
            if (s.state == "escort" and t > 8) {   # out of the drop, clear of the latch
                # clearance from the mothership: drone in the mothership's frame
                var fo = r[0] + 0.21; var ro = r[1] + (d.side > 0 ? 5.0 : -5.0); var uo = -r[2] + 1.94;
                var dx = math.max(0, math.max(fo - 6.0, -6.5 - fo));
                var dy = math.max(0, math.abs(ro) - 9.5); var dz = math.max(0, math.max(uo - 5.0, -0.5 - uo));
                bodymin = math.min(bodymin, math.sqrt(dx*dx + dy*dy + dz*dz));
            }
            if (cur != nil and t >= cur.a and t <= cur.b) {
                var m = cosmic_modes.mode_of(i);
                cur.err[i] = math.max(cur.err[i], cosmic_modes.dist_to(i, r, cosmic_modes.aim_of(m)));
                cur.spray[i] += cosmic_modes.flags[i][0]; cur.scout[i] += cosmic_modes.flags[i][1];
                if (i == 1) cur.n += 1;
            }
        }
        if (!released) { released = 1; continue; }
        var a = S[0]; var b = S[1];
        if (a.state != "docked" and b.state != "docked") {
            var dn = (a.lat - b.lat) * M_LAT; var de = (a.lon - b.lon) * M_LON * math.cos(a.lat * R); var dd = a.alt - b.alt;
            sepmin = math.min(sepmin, math.sqrt(dn*dn + de*de + dd*dd));
        }
        if (latched[0] != nil and latched[1] != nil) break;
    }
    if (cur != nil) append(res, cur);
    foreach (var c; res)
        printf("  preset %d %-50s worst slot error port %5.1f m stbd %5.1f m | spray %3.0f%%/%3.0f%% scout %3.0f%%/%3.0f%%",
               c.p, cosmic_modes.PRESETS[c.p].name, c.err[0], c.err[1],
               100 * c.spray[0] / math.max(c.n, 1), 100 * c.spray[1] / math.max(c.n, 1),
               100 * c.scout[0] / math.max(c.n, 1), 100 * c.scout[1] / math.max(c.n, 1));
    printf("  closest drone to drone %.1f m, closest to the mothership (out of the bay) %.1f m, lowest %.1f m AGL",
           sepmin, bodymin, lowest);
    printf("  recall: port %s, starboard %s, retries %d/%d",
           latched[0] == nil ? "NOT LATCHED" : sprintf("latched %.0f s", latched[0]),
           latched[1] == nil ? "NOT LATCHED" : sprintf("latched %.0f s", latched[1]), S[0].arounds, S[1].arounds);
};
var PLAN = [[20, 1, 50, 60], [60, 2, 95, 105], [105, 3, 140, 150], [150, 4, 185, 195]];
foreach (var kt; [65, 70, 75])
    foreach (var turn; [0, -3, 3]) {
        printf("RUN %d kt, turn %+d deg/s", kt, turn);
        run(kt, turn, PLAN, 195, 420);
    }
printf("RUN 85 kt, both scout (expect the scouts to fall short, too slow)");
run(85, 0, [[20, 3, 50, 60]], 60, 300);
printf("RUN 70 kt, recall straight from scout and from spray");
run(70, 0, [[20, 1, 45, 55]], 55, 300);
