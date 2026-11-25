#!/usr/bin/env python3
"""Build the mga-checklist add-on's Warrior checklist from the PA28's own checklist.

Reads the aircraft's PA28-Checklists.xml (same items, same order, same words) and ties
each item it can to the cockpit control or gauge it is about:
  <condition>  FlightGear condition, true when the item is done (green in flight,
               and in Help > Aircraft Checklists)
  <now>        the control's live state shown beside the item (property, scale,
               format, labels)
Items with no control (look outside, brief passengers ...) are ticked by hand in flight.

usage: make-pa28-checklist.py PA28-Checklists.xml OUT.xml
"""
import re
import sys
import xml.etree.ElementTree as ET

# Properties, checked on the PA28-161-160 on FlightGear 2024.1.7.
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

ONOFF = {0: "OFF", 1: "ON"}
MAGL = {0: "OFF", 1: "R", 2: "L", 3: "BOTH", 4: "START"}
TANKL = {0: "OFF", 1: "LEFT", 2: "RIGHT"}
DOORL = {0: "CLOSED", 1: "OPEN"}


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


def now(p, fmt=None, scale=None, labels=None):
    return dict(property=p, format=fmt, scale=scale, labels=labels)


SWITCHES_OFF_EXCEPT_BEACON = all_of(off(AVI), off(PUMP), off(PITOT), off(LAND), off(STROBE), lt(NAV, 0.05))
PCT = "%.0f%%"

# (item name regex, value regex, condition or None, now or None). First match wins.
RULES = [
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
    (r"^Throttle$", r"\d{4} RPM", "RPM", now(RPM, "%.0f RPM")),
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


def add(parent, tag, text=None):
    e = ET.SubElement(parent, tag)
    if text is not None:
        e.text = str(text)
    return e


def tie(item):
    """Add <condition>/<now> to one item. True if it got a condition."""
    name = (item.findtext("name") or "").strip()
    value = " ".join((v.text or "").strip() for v in item.findall("value")).strip()
    if not value:
        return False
    for nrx, vrx, cond, nw in RULES:
        if not (re.search(nrx, name) and re.search(vrx, value)):
            continue
        if cond == "RPM":
            r = int(re.search(r"(\d{4}) RPM", value).group(1))
            cond = between(RPM, r - 100, r + 100)
        if cond:
            item.append(ET.fromstring("<condition>" + cond + "</condition>"))
        if nw:
            n = add(item, "now")
            add(n, "property", nw["property"])
            if nw["scale"] is not None:
                add(n, "scale", nw["scale"])
            if nw["format"]:
                add(n, "format", nw["format"])
            for k, txt in (nw["labels"] or {}).items():
                lab = add(n, "label")
                add(lab, "value", k)
                add(lab, "text", txt)
        return bool(cond)
    return False


def main(src, out):
    tree = ET.parse(src)
    root = tree.getroot()
    actions = tied = shown = 0
    for item in root.iter("item"):
        has_value = any((v.text or "").strip() for v in item.findall("value"))
        if tie(item):
            tied += 1
        if item.find("now") is not None:
            shown += 1
        actions += has_value
    ET.indent(tree, space="\t")
    head = ("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
            "<!-- Generated by mga-checklist/tools/make-pa28-checklist.py from the PA28's own checklist\n"
            "     (Copyright (c) 2022 Josh Davidson (Octal450), GPL). Items keep their words and order;\n"
            "     <condition> and <now> tie them to the cockpit controls. -->\n")
    with open(out, "w", encoding="utf-8") as f:
        f.write(head + ET.tostring(root, encoding="unicode") + "\n")
    print(f"{actions} action items: {tied} check themselves, {shown} show the control's state -> {out}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
