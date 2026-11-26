#!/usr/bin/env python3
"""Build the mga-checklist add-on's tied checklists from the aircraft's own checklists.

Keeps each aircraft's items, order and words, and ties each item it can to the cockpit
control or gauge it is about:
  <condition>  FlightGear condition, true when the item is done (green in flight,
               and in Help > Aircraft Checklists)
  <now>        the control's live state shown beside the item (one or more
               <property>, then <scale>, <format>, <label>s)
Items with no control (look outside, brief passengers ...) are ticked by hand in flight.
An item that already has a <condition> keeps it.

usage:
  make-checklist.py pa28   ~/.fgfs/Aircraft/PA28/PA28-Checklists.xml  checklists/PA28-161-160.xml
  make-checklist.py seneca ~/.fgfs/Aircraft/SenecaII/SenecaII-base.xml checklists/SenecaII.xml
"""
import os
import re
import sys
import xml.etree.ElementTree as ET


# ---- condition helpers (each returns FlightGear condition elements as XML text) ----
def eq(p, v):
    return f"<equals><property>{p}</property><value>{v}</value></equals>"


def on(p):
    return f"<property>{p}</property>"


def off(p):
    return f"<not><property>{p}</property></not>"


def lt(p, v):
    return f"<less-than><property>{p}</property><value>{v}</value></less-than>"


def gt(p, v):
    return f"<greater-than><property>{p}</property><value>{v}</value></greater-than>"


def between(p, lo, hi):
    return gt(p, lo) + lt(p, hi)


def all_of(*c):
    return "<and>" + "".join(c) + "</and>"


def each(fn, props, *args):
    """The same test on every engine's property."""
    return "".join(fn(p, *args) for p in props)


def now(p, fmt=None, scale=None, labels=None):
    return dict(props=p if isinstance(p, list) else [p], format=fmt, scale=scale, labels=labels)


ONOFF = {0: "OFF", 1: "ON"}
DOORL = {0: "CLOSED", 1: "OPEN"}
PCT = "%.0f%%"


# ======================= PA28-161 Warrior II (160 hp) =======================
# Properties checked on the PA28-161-160 on FlightGear 2024.1.7.
MAGS = "controls/engines/engine[0]/magnetos-switch"      # 0 OFF 1 R 2 L 3 BOTH 4 START
MIX = "controls/engines/engine[0]/mixture"               # 1 full rich, 0 idle cut-off
THR = "controls/engines/engine[0]/throttle"
CARB = "controls/anti-ice/engine[0]/carb-heat-cmd"       # bool
PRIMER = "controls/engines/engine[0]/primer-pump"        # bool, 0 = locked
BATT = "controls/electrical/switches/battery"
ALT = "controls/electrical/switches/alternator"
AVI = "controls/electrical/switches/avionics-master"
PUMP = "controls/fuel/switches/pump"
TANK = "controls/fuel/switches/selected-tank"            # 0 OFF 1 LEFT 2 RIGHT
PBRAKE = "controls/gear/brake-parking"
FLAPS = "controls/flight/flaps"                          # 0..1 = 0..40 deg
TRIM = "controls/flight/elevator-trim"
PITOT = "controls/switches/pitot-heat"
LAND = "controls/switches/landing-light"
STROBE = "controls/switches/strobe-lights"
NAV = "controls/switches/nav-lights-factor"
CABHEAT = "controls/switches/cabin-heat-cmd"
DOOR = "fdm/jsbsim/extra/door-main-norm"                 # 0 closed
BAGDOOR = "fdm/jsbsim/extra/door-baggage-norm"           # 0 closed
RPM = "engines/engine[0]/rpm"
OILP = "engines/engine[0]/oil-pressure-psi"
OILT = "engines/engine[0]/oil-temperature-degf"
FUELP = "systems/fuel/pressure-psi"
SUCTION = "systems/vacuum/suction-inhg"
IAS = "instrumentation/airspeed-indicator/indicated-speed-kt"
FUEL_L = "consumables/fuel/tank[0]/level-gal_us"
MAGL = {0: "OFF", 1: "R", 2: "L", 3: "BOTH", 4: "START"}
TANKL = {0: "OFF", 1: "LEFT", 2: "RIGHT"}
SWITCHES_OFF_EXCEPT_BEACON = all_of(off(AVI), off(PUMP), off(PITOT), off(LAND), off(STROBE), lt(NAV, 0.05))


def rpm_near(rpm_props):
    """'... 2000 RPM' -> RPM within 100; '800-1000 RPM' -> that range, widened by 50."""
    def make(value):
        m = re.search(r"(\d{3,4})\s*-\s*(\d{3,4})\s*RPM", value)
        lo, hi = (int(m.group(1)) - 50, int(m.group(2)) + 50) if m else (None, None)
        if not m:
            r = int(re.search(r"(\d{3,4})\s*RPM", value).group(1))
            lo, hi = r - 100, r + 100
        return each(between, rpm_props, lo, hi)
    return make


PA28 = [
    (r"^Avionics Master$", r"^OFF", off(AVI), now(AVI, labels=ONOFF)),
    (r"^Avionics Master$", r"^ON", on(AVI), now(AVI, labels=ONOFF)),
    (r"^Master Switch$", r"^OFF", off(BATT), now(BATT, labels=ONOFF)),
    (r"^Master Switch$", r"^ON", on(BATT), now(BATT, labels=ONOFF)),
    (r"^ALT Switch$", r"^OFF", off(ALT), now(ALT, labels=ONOFF)),
    (r"^(Magneto Switch|Magnetos|Ignition)$", r"^OFF", eq(MAGS, 0), now(MAGS, labels=MAGL)),
    (r"^(Magneto Switch|Magnetos)$", r".", None, now(MAGS, labels=MAGL)),
    (r"^Mixture$", r"idle cut ?off", lt(MIX, 0.05), now(MIX, PCT, 100)),
    (r"^Mixture$", r"^(full )?rich$", gt(MIX, 0.95), now(MIX, PCT, 100)),
    (r"^Mixture$", r"lean for taxi", between(MIX, 0.05, 0.95), now(MIX, PCT, 100)),
    (r"^Mixture$", r".", None, now(MIX, PCT, 100)),
    (r"^Carburetor( Heat)?$", r"^(full )?ON$", on(CARB), now(CARB, labels=ONOFF)),
    (r"^Carburetor( Heat)?$", r"^(full )?OFF$", off(CARB), now(CARB, labels=ONOFF)),
    (r"^Carburetor( Heat)?$", r".", None, now(CARB, labels=ONOFF)),
    (r"^Electric Fuel Pump$", r"^ON$", on(PUMP), now(PUMP, labels=ONOFF)),
    (r"^Electric Fuel Pump$", r"OFF", off(PUMP), now(PUMP, labels=ONOFF)),
    (r"^Fuel Selector$", r"^OFF$", eq(TANK, 0), now(TANK, labels=TANKL)),
    (r"^Fuel Selector$", r"desired tank|containing fuel|fullest", gt(TANK, 0.5), now(TANK, labels=TANKL)),
    (r"^Fuel Selector$", r".", None, now(TANK, labels=TANKL)),
    (r"^Fuel Quantity Gauges$", r".", None, now(FUEL_L, "left %.0f gal")),
    (r"^Parking Brake$", r"^set", gt(PBRAKE, 0.5), now(PBRAKE, labels={0: "OFF", 1: "SET"})),
    (r"^Flaps$", r"^(0 \(retracted\)|\(0\) retract)", lt(FLAPS, 0.05), now(FLAPS, "%.0f deg", 40)),
    (r"^Flaps$", r"^25", between(FLAPS, 0.55, 0.7), now(FLAPS, "%.0f deg", 40)),
    (r"^Flaps$", r".", None, now(FLAPS, "%.0f deg", 40)),
    (r"^Throttle$", r"1/4 inch open", between(THR, 0.05, 0.35), now(THR, PCT, 100)),
    (r"^Throttle$", r"1/2 inch open", between(THR, 0.15, 0.5), now(THR, PCT, 100)),
    (r"^Throttle$", r"^open( full)?$", gt(THR, 0.95), now(THR, PCT, 100)),
    (r"^Throttle$", r"^(closed|idle|check idle)$", lt(THR, 0.05), now(THR, PCT, 100)),
    (r"^Throttle$", r"\d{4} RPM", rpm_near([RPM]), now(RPM, "%.0f RPM")),
    (r"^Throttle$", r".", None, now(THR, PCT, 100)),
    (r"^Oil Pressure$", r"green", between(OILP, 50, 90), now(OILP, "%.0f psi")),
    (r"^Oil Temp$", r"green", between(OILT, 75, 245), now(OILT, "%.0f F")),
    (r"^Fuel Pressure$", r"green", between(FUELP, 0.5, 8), now(FUELP, "%.1f psi")),
    (r"^Vacuum$", r".", between(SUCTION, 4.9, 5.1), now(SUCTION, "%.1f inHg")),
    (r"^Engine Gauges$", r"green", all_of(between(OILP, 50, 90), between(OILT, 75, 245)), now(OILP, "oil %.0f psi")),
    (r"^Engine Gauges$", r".", None, now(OILP, "oil %.0f psi")),
    (r"^Primer$", r"(?i)locked", off(PRIMER), now(PRIMER, labels={0: "LOCKED", 1: "OUT"})),
    (r"^Pitot Heat$", r".", None, now(PITOT, labels=ONOFF)),
    (r"^(Cabin Heat|Heat)$", r"^OFF$", lt(CABHEAT, 0.05), now(CABHEAT, PCT, 100)),
    (r"^(Cabin Door|Doors and Windows)$", r".", lt(DOOR, 0.02), now(DOOR, labels=DOORL)),
    (r"^Baggage Door$", r".", lt(BAGDOOR, 0.02), now(BAGDOOR, labels=DOORL)),
    (r"^(All Switches|Electric Switches|External Lights and Electrical Equipment)$", r"OFF",
     SWITCHES_OFF_EXCEPT_BEACON, None),
    (r"^(Nav and Strobe Lights|Exterior Lights|External Lights)$", r".", None, now(STROBE, "strobe %s", labels=ONOFF)),
    (r"^(Trim|Trim Tab)$", r".", None, now(TRIM, "%+.2f")),
    (r"^(Airspeed|Enroute|Best Angle|Best Rate|Final Approach Speed|Accelerate)", r".", None, now(IAS, "%.0f KIAS")),
]


# ======================= PA-34-200T Seneca II =======================
# Properties from the SenecaII model, panel and Nasal (FlightGear 2024.1.7). Both engines
# must match for a line to go green; the live state shows left / right.
ENG = ["controls/engines/engine[0]", "controls/engines/engine[1]"]
S_MAGS = [f"{e}/magneto[{m}]" for e in ENG for m in (0, 1)]          # bools, four switches
S_MIX = [f"{e}/mixture" for e in ENG]
S_THR = [f"{e}/throttle" for e in ENG]
S_PROP = [f"{e}/propeller-pitch" for e in ENG]                      # 1 = high RPM
S_COWL = [f"{e}/cowl-flaps-norm" for e in ENG]                      # 1 = open
S_PRIMER = [f"{e}/primer" for e in ENG]
S_RPM = ["engines/engine[0]/rpm", "engines/engine[1]/rpm"]
S_OILP = ["engines/engine[0]/oil-pressure-psi", "engines/engine[1]/oil-pressure-psi"]
S_GEN = ["controls/electric/engine[0]/generator", "controls/electric/engine[1]/generator"]
S_SEL = ["controls/fuel/tank[0]/fuel_selector-position",
         "controls/fuel/tank[1]/fuel_selector-position"]             # 1 ON, 0 OFF, -1 X-FEED
S_BATT = "controls/electric/battery-switch"
S_AVI = "controls/electric/avionic-switch"
S_PBRAKE = "controls/gear/brake-parking"
S_GEAR = "controls/gear/gear-down"
S_GEARPOS = [f"gear/gear[{i}]/position-norm" for i in (0, 1, 2)]
S_FLAPS = "controls/flight/flaps"                                    # 0..1 = 0..40 deg
S_TRIM = "controls/flight/elevator-trim"
S_PITOT = "controls/anti-ice/pitot-heat"
S_LAND = "controls/lighting/landing-lights"
S_STROBE = "controls/lighting/strobe"
S_BEACON = "controls/lighting/beacon"
S_NAV = "controls/lighting/nav-lights"
S_DOORS = ["sim/model/door-positions/right-door/position-norm", "sim/model/door-positions/pax-door/position-norm"]
S_SUCTION = "instrumentation/vacuum/suction-inhg"
SELL = {1: "ON", 0: "OFF", -1: "X-FEED"}
UPDN = {0: "UP", 1: "DOWN"}
S_ALL_OFF = all_of(off(S_BATT), off(S_AVI), off(S_PITOT), off(S_LAND), off(S_STROBE), off(S_BEACON), off(S_NAV),
                   each(off, S_MAGS), each(off, S_GEN))

SENECA = [
    (r"^All Switches$", r"(?i)^off", S_ALL_OFF, None),
    (r"^Alternators$", r"(?i)^off", each(off, S_GEN), now(S_GEN, labels=ONOFF)),
    (r"^Battery Master$", r"(?i)^on", on(S_BATT), now(S_BATT, labels=ONOFF)),
    (r"^Battery Master$", r"(?i)^off", off(S_BATT), now(S_BATT, labels=ONOFF)),
    (r"^Radios$", r"(?i)^on", on(S_AVI), now(S_AVI, labels=ONOFF)),
    (r"^Radios$", r"(?i)^off", off(S_AVI), now(S_AVI, labels=ONOFF)),
    (r"^Beacon$", r"(?i)^on", on(S_BEACON), now(S_BEACON, labels=ONOFF)),
    (r"^Strobe Lights$", r"(?i)^off", off(S_STROBE), now(S_STROBE, labels=ONOFF)),
    (r"^Landing Lights$", r"(?i)^on", on(S_LAND), now(S_LAND, labels=ONOFF)),
    (r"^Landing Lights$", r"(?i)^off", off(S_LAND), now(S_LAND, labels=ONOFF)),
    (r"^Pitot Heat$", r"(?i)^off", off(S_PITOT), now(S_PITOT, labels=ONOFF)),
    (r"^Pitot Heat$", r".", None, now(S_PITOT, labels=ONOFF)),
    (r"^Cabin Doors$", r".", each(lt, S_DOORS, 0.02), now(S_DOORS, labels=DOORL)),
    (r"^Parking Brake$", r"(?i)^set", on(S_PBRAKE), now(S_PBRAKE, labels={0: "OFF", 1: "SET"})),
    (r"^Gear Lever$", r"(?i)^down", on(S_GEAR), now(S_GEAR, labels=UPDN)),
    (r"^Gear$", r"(?i)down", all_of(on(S_GEAR), each(gt, S_GEARPOS, 0.99)), now(S_GEARPOS, "%.0f%%", 100)),
    (r"^Gear / Flaps$", r"(?i)^up", all_of(off(S_GEAR), lt(S_FLAPS, 0.05)), now(S_GEAR, labels=UPDN)),
    (r"^Flaps$", r"(?i)^up", lt(S_FLAPS, 0.05), now(S_FLAPS, "%.0f deg", 40)),
    (r"^Flaps$", r".", None, now(S_FLAPS, "%.0f deg", 40)),
    (r"^Cowl Flaps$", r"(?i)^open", each(gt, S_COWL, 0.95), now(S_COWL, PCT, 100)),
    (r"^Cowl Flaps$", r"(?i)^closed", each(lt, S_COWL, 0.05), now(S_COWL, PCT, 100)),
    (r"^Fuel Selector$", r"(?i)^on", each(eq, S_SEL, 1), now(S_SEL, labels=SELL)),
    (r"^X-Feed$", r".", None, now(S_SEL, labels=SELL)),
    (r"^Fuel Prime$", r".", None, now(S_PRIMER, labels=ONOFF)),
    (r"^Magnetos$", r"(?i)both on", each(on, S_MAGS), now(S_MAGS, labels=ONOFF)),
    (r"^Magnetos$", r".", None, now(S_RPM, "%.0f RPM")),
    (r"^Mixture$", r"(?i)^rich", each(gt, S_MIX, 0.95), now(S_MIX, PCT, 100)),
    (r"^Mixture$", r"(?i)cutoff", each(lt, S_MIX, 0.05), now(S_MIX, PCT, 100)),
    (r"^Mixture$", r".", None, now(S_MIX, PCT, 100)),
    (r"^Propeller$", r"(?i)high rpm", each(gt, S_PROP, 0.95), now(S_PROP, PCT, 100)),
    (r"^Propeller (Feather|Governor)$", r".", None, now(S_RPM, "%.0f RPM")),
    (r"^Throttle$", r"(?i)^idle", each(lt, S_THR, 0.05), now(S_THR, PCT, 100)),
    (r"^Throttle$", r"(?i)^full", each(gt, S_THR, 0.95), now(S_THR, PCT, 100)),
    (r"^Throttle$", r"\d{3,4}\s*RPM", rpm_near(S_RPM), now(S_RPM, "%.0f RPM")),
    (r"^Engine Starter$", r".", None, now(S_RPM, "%.0f RPM")),
    (r"^Oil Pressure$", r"(?i)green", each(between, S_OILP, 25, 90), now(S_OILP, "%.0f psi")),
    (r"^Engine Instruments$", r"(?i)green", each(between, S_OILP, 25, 90), now(S_OILP, "oil %.0f psi")),
    (r"^Gyro Pressure$", r".", between(S_SUCTION, 4.5, 5.5), now(S_SUCTION, "%.1f inHg")),
    (r"^Trim$", r".", None, now(S_TRIM, "%+.2f")),
    (r"^Power$", r".", None, now(S_RPM, "%.0f RPM")),
]

PROFILES = {
    "pa28": dict(rules=PA28, credit="the PA28's own checklist (Copyright (c) 2022 Josh Davidson (Octal450), GPL)"),
    "seneca": dict(rules=SENECA, credit="the SenecaII's own checklists (FGAddon, GPL)"),
}


def add(parent, tag, text=None):
    e = ET.SubElement(parent, tag)
    if text is not None:
        e.text = str(text)
    return e


def tie(item, rules):
    """Add <condition>/<now> to one item. True if it got a condition."""
    name = (item.findtext("name") or "").strip()
    value = " ".join((v.text or "").strip() for v in item.findall("value")).strip()
    if not value:
        return False
    for nrx, vrx, cond, nw in rules:
        if not (re.search(nrx, name) and re.search(vrx, value)):
            continue
        if callable(cond):
            cond = cond(value)
        if cond and item.find("condition") is None:
            item.append(ET.fromstring("<condition>" + cond + "</condition>"))
        if nw and item.find("now") is None:
            n = add(item, "now")
            for p in nw["props"]:
                add(n, "property", p)
            if nw["scale"] is not None:
                add(n, "scale", nw["scale"])
            if nw["format"]:
                add(n, "format", nw["format"])
            for k, txt in (nw["labels"] or {}).items():
                lab = add(n, "label")
                add(lab, "value", k)
                add(lab, "text", txt)
        return item.find("condition") is not None
    return item.find("condition") is not None


def load(src):
    """The aircraft's checklists as one PropertyList. A -set/-base file's
    <checklists><checklist include="..."/> list is followed, in order."""
    root = ET.parse(src).getroot()
    cls = root.find("sim/checklists")
    if cls is None:
        return root
    out = ET.Element("PropertyList")
    base = os.path.dirname(src)
    for c in cls.findall("checklist"):
        inc = c.get("include")
        out.append(ET.parse(os.path.join(base, inc)).getroot() if inc else c)
    for c in out.findall("PropertyList"):
        c.tag = "checklist"
    return out


def main(profile, src, out):
    prof = PROFILES[profile]
    root = load(src)
    actions = tied = shown = 0
    for item in root.iter("item"):
        has_value = any((v.text or "").strip() for v in item.findall("value"))
        if tie(item, prof["rules"]):
            tied += 1
        if item.find("now") is not None:
            shown += 1
        actions += has_value
    tree = ET.ElementTree(root)
    ET.indent(tree, space="\t")
    head = ("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
            f"<!-- Generated by mga-checklist/tools/make-checklist.py {profile} from\n"
            f"     {prof['credit']}.\n"
            "     Items keep their words and order; <condition> and <now> tie them to the cockpit controls. -->\n")
    with open(out, "w", encoding="utf-8") as f:
        f.write(head + ET.tostring(root, encoding="unicode") + "\n")
    print(f"{actions} action items: {tied} check themselves, {shown} show the control's state -> {out}")


if __name__ == "__main__":
    if len(sys.argv) != 4 or sys.argv[1] not in PROFILES:
        sys.exit(__doc__)
    main(*sys.argv[1:])
