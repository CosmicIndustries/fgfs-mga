#!/usr/bin/env python3
"""Cosmic Industries fleet round 2026-11-26: build the Arrow, Seminole, Decathlon, Citabria,
AT-502B and AT-802 into STAGE, from the board's own PA28 and SenecaII packages plus the files
in this folder. Nothing in ~/.fgfs is touched here.
Usage: build_round.py PA28_DIR SENECA_DIR STAGE"""
import os, re, shutil, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
pa28, sen, stage = sys.argv[1:4]


def rd(p):
    return open(p, encoding="utf-8-sig").read()


def wr(p, s):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, "w").write(s)


def cp(name, dst):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copy(os.path.join(HERE, name), dst)


# ---------------- Arrow (new files inside the PA28 package)
A = os.path.join(stage, "PA28")
s = rd(os.path.join(pa28, "PA28-161-180.xml"))
s = s.replace('<description>PA28-161 Warrior II FDE</description>',
              '<description>PA-28R-201 Arrow III FDE (Cosmic Industries fleet round 2026-11-26, from the PA28 Warrior/Archer FDE by Josh Davidson)</description>')
s = s.replace('Systems/pa28-mass-balance-180', 'Systems/pa28r-mass-balance')
s = s.replace('engine file="lycoming-O-360-A4A"', 'engine file="lycoming-IO-360-C1C6"')
s = s.replace('thruster file="sensenich-76EM8S14-0-62"', 'thruster file="hartzell-HC-C2YK-1BF"')
s = s.replace('<capacity unit="LBS">168</capacity>', '<capacity unit="LBS">231</capacity>')
s = s.replace('<contents unit="LBS">119</contents>', '<contents unit="LBS">150</contents>')
s = s.replace('<system file="pa28-cockpit"/>', '<system file="pa28-cockpit"/>\n\t<system file="pa28r-gear"/>')
s = s.replace('Systems/pa28-aerodynamics.xml', 'Systems/pa28r-aerodynamics.xml')
for need in ["lycoming-IO-360-C1C6", "hartzell-HC-C2YK-1BF", "pa28r-gear", "pa28r-aerodynamics", "pa28r-mass-balance", "231"]:
    assert need in s, need
wr(os.path.join(A, "PA28R-201.xml"), s)
mb = rd(os.path.join(pa28, "Systems", "pa28-mass-balance-180.xml"))
mb2 = re.sub(r'<emptywt unit="LBS">\s*\d+\s*</emptywt>[^\n]*',
             '<emptywt unit="LBS">1640</emptywt> <!-- Arrow III typical basic empty weight -->', mb)
assert mb2 != mb
for a, b in [('1070', '1180'), ('1249', '1360'), ('2312', '2520')]:
    mb2 = mb2.replace('>%s<' % a, '>%s<' % b)
wr(os.path.join(A, "Systems", "pa28r-mass-balance.xml"), mb2)
ae = rd(os.path.join(pa28, "Systems", "pa28-aerodynamics.xml"))
add = '''
		<function name="aero/coefficient/CDgear">
			<description>Arrow III: gear drag. The Archer's CD0 already holds its faired fixed gear;
				gear up removes that, gear down adds a little more (no wheel fairings, open wells).
				Tuned offline so 71% power at 6000 ft and 2720 lb gives about 138 KTAS gear up.</description>
			<product>
				<property>aero/qbar-psf</property>
				<property>metrics/Sw-sqft</property>
				<sum>
					<value>-0.0042</value>
					<product>
						<property>gear/gear-pos-norm</property>
						<value>0.0060</value>
					</product>
				</sum>
			</product>
		</function>
'''
ae2 = ae.replace('\t</axis>\n\t\n\t<axis name="SIDE">', add + '\t</axis>\n\t\n\t<axis name="SIDE">', 1)
assert ae2 != ae
ae2 = ae2.replace('<!-- Piper PA28 Aerodynamics -->', '<!-- Piper PA28 Aerodynamics, Arrow III copy (Cosmic Industries fleet round 2026-11-26: adds CDgear) -->')
wr(os.path.join(A, "Systems", "pa28r-aerodynamics.xml"), ae2)
cp("pa28r-gear.xml", os.path.join(A, "Systems", "pa28r-gear.xml"))
cp("lycoming-IO-360-C1C6.xml", os.path.join(A, "Engines", "lycoming-IO-360-C1C6.xml"))
cp("hartzell-HC-C2YK-1BF.xml", os.path.join(A, "Engines", "hartzell-HC-C2YK-1BF.xml"))
cp("PA28R-201.xml", os.path.join(A, "Models", "PA28R-201.xml"))
cp("PA28R-201-set.xml", os.path.join(A, "PA28R-201-set.xml"))
subprocess.check_call([sys.executable, os.path.join(HERE, "gen_arrow.py"), os.path.join(A, "Models")])

# ---------------- Seminole (new files inside the SenecaII package)
S = os.path.join(stage, "SenecaII")
s = rd(os.path.join(sen, "SenecaII-jsbsim.xml"))
o = s
s = s.replace('name="SenecaII"\n', 'name="PA44-180"\n', 1)
s = s.replace('<description>Model for a PA34-200T Seneca II</description>',
              '<description>Piper PA-44-180 Seminole, Cosmic Industries fleet round 2026-11-26: the Seneca II model by Torsten Dreyer resized to the Seminole (wing, weights, two 180 hp O-360s, 74 in props)</description>')
s = s.replace('<wingarea unit="FT2"> 208.7000 </wingarea>', '<wingarea unit="FT2"> 183.8000 </wingarea> <!-- Seminole; Seneca II 208.7 -->')
s = s.replace('<wingspan unit="FT"> 38.9060 </wingspan>', '<wingspan unit="FT"> 38.6000 </wingspan>')
s = s.replace('<chord unit="FT"> 5.1800 </chord>', '<chord unit="FT"> 4.7600 </chord>')
s = s.replace('<emptywt unit="LBS"> 2850 </emptywt>', '<emptywt unit="LBS"> 2450 </emptywt> <!-- Seminole typical; Seneca II 2850 -->')
for a, b in [('5596', '4480'), ('5334', '4270'), ('11945', '9560')]:
    s = s.replace('> %s <' % a, '> %s <' % b)
s = re.sub(r'(<pointmass name="Pilot">\s*<weight unit="LBS">)\s*180.0\s*(</weight>)', r'\1 170.0 \2', s)
s = re.sub(r'(<pointmass name="Co Pilot">\s*<weight unit="LBS">)\s*200.0\s*(</weight>)', r'\1 170.0 \2', s)
for n in ['Middle Left Pax', 'Middle Right Pax', 'Rear Left Pax', 'Rear Right Pax', 'Nose Baggage', 'Aft Baggage']:
    s = re.sub(r'(<pointmass name="%s">\s*<weight unit="LBS">)\s*[0-9.]+\s*(</weight>)' % n, r'\1 0.0 \2', s)
s = s.replace('engine file="tsio360eb"', 'engine file="lycoming-O-360-A1H6"')
s = s.replace('thruster file="bhc-c2yf-2"', 'thruster file="hartzell-HC-C2YL-2"')
s = s.replace('<capacity unit="LBS">384</capacity>', '<capacity unit="LBS">330</capacity> <!-- 55 gal per side -->')
s = s.replace('<contents unit="LBS">180.5</contents>', '<contents unit="LBS">200</contents>')
s = s.replace('<capacity unit="LBS">90</capacity>', '<capacity unit="LBS">0.1</capacity> <!-- the Seminole has no aux tanks -->')
s = s.replace('<system file="prop-governor"/>', '<system file="pa44-prop-governor"/>')
for need in ['PA44-180', '183.8000', '2450', 'lycoming-O-360-A1H6', 'hartzell-HC-C2YL-2', 'pa44-prop-governor', '330']:
    assert need in s, need
wr(os.path.join(S, "PA44-180-jsbsim.xml"), s)
g = rd(os.path.join(sen, "Systems", "prop-governor.xml"))
g2 = g.replace('<value>1875</value> <!-- max.rpm minus min.rpm -->', '<value>2000</value> <!-- max.rpm minus min.rpm (Seminole 2700 rpm) -->')
assert g2.count('2000') >= 2
g2 = g2.replace('<system name="PropGovernor">', '<!-- Cosmic Industries fleet round 2026-11-26: Seminole copy, 700 to 2700 rpm. -->\n<system name="PropGovernor">')
wr(os.path.join(S, "Systems", "pa44-prop-governor.xml"), g2)
p = rd(os.path.join(sen, "Engines", "bhc-c2yf-2.xml"))
p = p.replace('<propeller name="BHC2-C2YF-2">', '<!-- Cosmic Industries fleet round 2026-11-26: Seminole Hartzell HC-C2YL-2 class, 74 in, from the Seneca II prop. -->\n<propeller name="HC-C2YL-2">')
p = re.sub(r'<diameter unit="IN">[^<]*</diameter>', '<diameter unit="IN">74.0</diameter>', p)
p = re.sub(r'<maxrpm>[^<]*</maxrpm>', '<maxrpm>          2700   </maxrpm>', p)
wr(os.path.join(S, "Engines", "hartzell-HC-C2YL-2.xml"), p)
e = rd(os.path.join(pa28, "Engines", "lycoming-O-360-A4A.xml"))
e = e.replace('<piston_engine name="lycoming-O-360-A4A">', '<!-- Cosmic Industries fleet round 2026-11-26: Seminole O-360-A1H6 / LO-360-A1H6, 180 hp at 2700 rpm,\n     from the PA28 Archer engine file (Josh Davidson, tuned by the Nov 22 engine audit). -->\n<piston_engine name="lycoming-O-360-A1H6">')
wr(os.path.join(S, "Engines", "lycoming-O-360-A1H6.xml"), e)
cp("PA44-180.xml", os.path.join(S, "Models", "PA44-180.xml"))
cp("seminole-ttail.xml", os.path.join(S, "Models", "seminole-ttail.xml"))
cp("PA44-180-set.xml", os.path.join(S, "PA44-180-set.xml"))
subprocess.check_call([sys.executable, os.path.join(HERE, "gen_seminole.py"), os.path.join(S, "Models")])

# ---------------- the four new planes
subprocess.check_call([sys.executable, os.path.join(HERE, "gen_fleet.py"), stage])
print("staged in", stage)
