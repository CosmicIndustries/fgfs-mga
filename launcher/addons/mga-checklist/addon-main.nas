# mga-checklist: an in-flight checklist tied to each cockpit control.
#
# If checklists/<aircraft id>.xml exists in this add-on, it replaces /sim/checklists, so
# Help > Aircraft Checklists shows its lines green/amber too. Otherwise the aircraft's own
# checklist is used. An item's <condition> makes it tick itself when the control is set;
# its <now> shows the control's live state. Other items are ticked with a click.
# Ctrl-K or the Checklist menu shows and hides the window. GPL-2.0-or-later.

var W = 600;            # window size, px
var ROWS = 16;          # visible item rows
var ROW_H = 22;
var TOP = 58;           # first row baseline area
var H = TOP + ROWS * ROW_H + 34;
var FONT = "LiberationFonts/LiberationSans-Regular.ttf";
var FONT_B = "LiberationFonts/LiberationSans-Bold.ttf";

var GREEN = [0.35, 0.9, 0.35];
var AMBER = [1.0, 0.72, 0.2];
var WHITE = [0.92, 0.92, 0.92];
var GREY = [0.6, 0.6, 0.6];
var CYAN = [0.45, 0.85, 1.0];

var lists = [];         # [{group, title, items: [{name, value, action, cond, now}]}]
var cur = 0;            # current checklist
var ticks = {};         # "list:item" -> 1, hand ticks
var win = nil;
var ui = nil;           # canvas elements
var timer = nil;
var source = "aircraft";
var stateN = props.globals.getNode("/sim/mga-checklist", 1);

var note = func(t) { logprint(LOG_INFO, "mga-checklist: ", t); };

var loadOwn = func(base) {
    var id = getprop("/sim/aircraft") or "";
    var path = base ~ "/checklists/" ~ id ~ ".xml";
    if (id == "" or io.stat(path) == nil) return 0;
    var n = io.read_properties(path);
    if (n == nil) { logprint(LOG_ALERT, "mga-checklist: could not read ", path); return 0; }
    var dst = props.globals.getNode("/sim/checklists", 1);
    dst.removeAllChildren();
    props.copy(n, dst);
    note("using " ~ path);
    return 1;
};

var collect = func {
    lists = [];
    var root = props.globals.getNode("/sim/checklists");
    if (root == nil) return;
    var add = func(group, cl) {
        var pages = cl.getChildren("page");
        if (!size(pages)) pages = [cl];
        var items = [];
        foreach (var p; pages) {
            foreach (var it; p.getChildren("item")) {
                var name = it.getValue("name") or "";
                var vals = [];
                foreach (var v; it.getChildren("value")) {
                    var s = v.getValue();
                    if (s != nil and s != "") append(vals, s);
                }
                if (find("Continued on next page", name) == 0) continue;
                append(items, {name: name, value: string.join(" ", vals), action: size(vals) > 0,
                               cond: it.getNode("condition"), now: it.getNode("now"),
                               auto: condProps(it.getNode("condition"))});
            }
        }
        append(lists, {group: group, title: cl.getValue("title") or "?", items: items});
    };
    var groups = root.getChildren("group");
    if (size(groups)) {
        foreach (var g; groups)
            foreach (var cl; g.getChildren("checklist")) add(g.getValue("name") or "", cl);
    } else {
        foreach (var cl; root.getChildren("checklist")) add("", cl);
    }
};

var isDone = func(li, ii) {
    var it = lists[li].items[ii];
    if (!it.action) return 1;
    var k = li ~ ":" ~ ii;
    if (contains(ticks, k)) return 1;     # hand tick, or a tied line done in its turn
    if (it.cond != nil) return props.condition(it.cond);
    return 0;
};

# A tied line that goes green when it is the next one to do stays done, so a later line that
# sets the same control the other way (Master ON, then Master OFF) doesn't undo it.
var latch = func(li) {
    var items = lists[li].items;
    for (var i = 0; i < size(items); i += 1) {
        if (!items[i].action) continue;
        var k = li ~ ":" ~ i;
        if (contains(ticks, k)) continue;
        if (items[i].cond != nil and props.condition(items[i].cond)) { ticks[k] = 1; continue; }
        return;
    }
};

# The <property> paths inside an item's <condition> (at most 3, no repeats): shown as
# the live value when the item has no <now> of its own (aircraft checklists that
# already check themselves), so a line that checks two controls shows both.
var condProps = func(n) {
    var out = [];
    var walk = func(m) {
        foreach (var c; m.getChildren()) {
            if (size(out) >= 3) return;
            if (c.getName() == "property") {
                var p = c.getValue();
                if (p == nil or p == "") continue;
                var seen = 0;
                foreach (var q; out) if (q == p) seen = 1;
                if (!seen) append(out, p);
            } else {
                walk(c);
            }
        }
    };
    if (n != nil) walk(n);
    return size(out) ? out : nil;
};

var oneValue = func(n, path) {
    var v = getprop(path);
    if (v == nil) return nil;
    var fmt = n.getValue("format");
    var labels = n.getChildren("label");
    if (size(labels) and num(v) != nil) {
        foreach (var l; labels) {
            if (math.round(num(v)) == l.getValue("value")) {
                var t = l.getValue("text") or "";
                return (fmt != nil and find("%s", fmt) >= 0) ? sprintf(fmt, t) : t;
            }
        }
    }
    if (num(v) == nil) return (fmt != nil) ? sprintf(fmt, v) : v;
    var s = n.getValue("scale");
    if (s != nil) v = v * s;
    return sprintf(fmt != nil ? fmt : "%.2f", v);
};

var autoValue = func(path) {
    var node = props.globals.getNode(path);
    if (node == nil) return "";
    var v = node.getValue();
    if (v == nil) return "";
    if (node.getType() == "BOOL") return v ? "ON" : "OFF";
    if (num(v) == nil) return v;
    # 0..1 levers and positions read better as percent (throttle 25%, door 100%).
    var leaf = node.getName();
    if (leaf == "throttle" or leaf == "mixture" or leaf == "propeller-pitch" or leaf == "flaps"
        or find("-norm", leaf) >= 0)
        return sprintf("%d%%", math.round(v * 100));
    return (v == int(v)) ? sprintf("%d", v) : sprintf("%.2f", v);
};

var nowText = func(it) {
    var n = it.now;
    var out = [];
    if (n == nil) {
        if (it.auto == nil) return "";
        foreach (var p; it.auto) {
            var s = autoValue(p);
            if (s != "") append(out, s);
        }
        return string.join(" / ", out);
    }
    foreach (var p; n.getChildren("property")) {
        var s = oneValue(n, p.getValue() or "");
        if (s != nil) append(out, s);
    }
    return string.join(" / ", out);
};

var clip = func(s, n) { return size(s) > n ? substr(s, 0, n - 1) ~ "..." : s; };

var setColor = func(el, c) { el.setColor(c[0], c[1], c[2]); };

var build = func {
    var x = getprop("/sim/startup/xsize") or 1280;
    win = canvas.Window.new([W, H], "dialog").set("title", "Checklist (Ctrl-K hides)");
    win.setPosition(x - W - 20, 60);
    win.del = func { call(canvas.Window.del, [], me); win = nil; ui = nil; stateN.setBoolValue("visible", 0); };
    var c = win.createCanvas().set("background", "#1a1c21e6");
    var g = c.createGroup();
    var text = func(x, y, size, align, font = nil) {
        return g.createChild("text").setFont(font or FONT).setFontSize(size).setAlignment(align).setTranslation(x, y);
    };
    ui = {rows: []};
    ui.bar = g.createChild("path").rect(0, 0, W, ROW_H).setColorFill(0.22, 0.34, 0.55, 0.85).hide();
    ui.prev = text(14, 26, 20, "left-baseline", FONT_B).setText("<");
    ui.next = text(W - 14, 26, 20, "right-baseline", FONT_B).setText(">");
    ui.title = text(W / 2, 24, 17, "center-baseline", FONT_B);
    ui.sub = text(W / 2, 44, 12, "center-baseline");
    for (var r = 0; r < ROWS; r += 1) {
        var y = TOP + r * ROW_H + 16;
        append(ui.rows, {
            mark: text(10, y, 14, "left-baseline", FONT_B),
            name: text(34, y, 14, "left-baseline"),
            now: text(W - 10, y, 13, "right-baseline"),
        });
    }
    ui.foot = text(W / 2, H - 12, 12, "center-baseline");
    setColor(ui.foot, GREY);
    setColor(ui.sub, GREY);
    foreach (var e; [ui.prev, ui.next, ui.title]) setColor(e, WHITE);

    c.addEventListener("click", func(e) {
        var x = e.localX; var y = e.localY;
        if (y < TOP) {
            if (x < 60) step(-1);
            elsif (x > W - 60) step(1);
            return;
        }
        var r = int((y - TOP) / ROW_H);
        if (r < 0 or r >= ROWS or ui.first + r >= size(lists[cur].items)) return;
        var ii = ui.first + r;
        var it = lists[cur].items[ii];
        if (!it.action) return;
        var k = cur ~ ":" ~ ii;
        if (contains(ticks, k)) delete(ticks, k); else ticks[k] = 1;
        update();
    });
    stateN.setBoolValue("visible", 1);
};

var update = func {
    if (win == nil or ui == nil or !size(lists)) return;
    latch(cur);
    var L = lists[cur];
    var n = size(L.items);
    var todo = -1; var done = 0; var actions = 0;
    for (var i = 0; i < n; i += 1) {
        if (!L.items[i].action) continue;
        actions += 1;
        if (isDone(cur, i)) done += 1;
        elsif (todo < 0) todo = i;
    }
    ui.title.setText(clip(L.title, 44));
    ui.sub.setText(sprintf("%s%s  %d of %d  -  %d/%d done", L.group, L.group != "" ? ":" : "", cur + 1, size(lists), done, actions));
    var first = (todo < 0) ? 0 : todo - 3;
    if (first > n - ROWS) first = n - ROWS;
    if (first < 0) first = 0;
    ui.first = first;
    ui.bar.hide();
    for (var r = 0; r < ROWS; r += 1) {
        var row = ui.rows[r];
        var i = first + r;
        if (i >= n) { row.mark.setText(""); row.name.setText(""); row.now.setText(""); continue; }
        var it = L.items[i];
        if (!it.action) {
            row.mark.setText("");
            row.name.setText(clip(it.name, 78));
            setColor(row.name, GREY);
            row.now.setText("");
            continue;
        }
        var ok = isDone(cur, i);
        row.mark.setText(ok ? "v" : (i == todo ? ">" : "o"));
        var col = ok ? GREEN : (it.cond != nil ? AMBER : WHITE);
        setColor(row.mark, col);
        setColor(row.name, col);
        var nt = nowText(it);
        row.name.setText(clip(it.name ~ "  ....  " ~ it.value, nt == "" ? 70 : 56));
        row.now.setText(nt);
        setColor(row.now, CYAN);
        if (i == todo) ui.bar.setTranslation(0, TOP + r * ROW_H + 1).show();
    }
    if (todo < 0)
        ui.foot.setText(cur + 1 < size(lists) ? "All done. Next: " ~ clip(lists[cur + 1].title, 40) ~ "  (click >)" : "All done.");
    else
        ui.foot.setText("Amber lines go green when you set the control. Click a line to tick it.");
};

var step = func(d) {
    if (!size(lists)) return;
    cur = math.mod(cur + d + size(lists), size(lists));
    stateN.setIntValue("index", cur);
    if (win == nil) show(); else update();
};

var show = func {
    if (!size(lists)) collect();
    if (!size(lists)) {
        gui.popupTip("This aircraft has no checklist.", 3);
        return;
    }
    if (win == nil) {
        var err = [];
        call(build, [], nil, nil, err);
        if (size(err)) {
            logprint(LOG_ALERT, "mga-checklist: could not open the window: ", err[0], " at line ", err[2] or "?");
            if (win != nil) win.del();
            return;
        }
    }
    update();
    if (timer == nil) timer = maketimer(0.4, update);
    timer.start();
};

var hide = func {
    if (timer != nil) timer.stop();
    if (win != nil) win.del();
};

var toggle = func { if (win == nil) show(); else hide(); };

var clearTicks = func { ticks = {}; update(); };

var main = func(addon) {
    if (loadOwn(addon.basePath)) source = "add-on";
    collect();
    stateN.setValue("source", source);
    stateN.setIntValue("checklists", size(lists));
    cur = 0;
    globals["mgaChecklist"] = {toggle: toggle, show: show, hide: hide, step: step, clearTicks: clearTicks};
    # Writing these from outside (instructor panel, httpd) works like the menu.
    setlistener(stateN.getNode("toggle", 1), func toggle(), 0, 1);
    setlistener(stateN.getNode("step", 1), func(n) { var d = n.getValue(); if (d) step(d > 0 ? 1 : -1); }, 0, 1);
    note(sprintf("%d checklists from the %s file; Ctrl-K shows them", size(lists), source));
};
