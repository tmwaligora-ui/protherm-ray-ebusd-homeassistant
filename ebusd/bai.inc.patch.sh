#!/bin/sh
# CZ: Úprava ebusd konfigurace pro Protherm Ray KE (6 KE, product 0010023670).
#     Spusť v adresáři s lokální kopií konfigurace ebusd (např. /addon_configs/xxx_ebusd/ebusd-configuration/vaillant/).
#     Soubory stáhni z https://github.com/eBUS/ebus.github.io/tree/main/en/vaillant
#     (08.bai.csv, scan.csv, bai.0010008045.inc + broadcast.csv, memory.csv o úroveň výš).
# EN: Patch of the ebusd configuration for Protherm Ray KE (6 KE, product 0010023670).
#     Run inside your local copy of the ebusd config (e.g. /addon_configs/xxx_ebusd/ebusd-configuration/vaillant/).
#     Get the files from https://github.com/eBUS/ebus.github.io/tree/main/en/vaillant
#     (08.bai.csv, scan.csv, bai.0010008045.inc + broadcast.csv, memory.csv one level up).
set -e

# 1) 08.bai.csv – CZ: Ray (0010023670) načítat definici bai.0010008045.inc.
#                 ebusd sám vybere bai.308523.inc (nový registrový formát), kterému Ray nerozumí
#                 (chyby „invalid position“, žádné hodnoty). Definice 0010008045 na Ray sedí.
#                 EN: make Ray (0010023670) load bai.0010008045.inc. ebusd auto-picks bai.308523.inc
#                 (new register layout) which Ray does not understand; 0010008045 works.
sed -i "s/^\[Scan_id_product='0010008045';'0010008863';'0010023648'\]!load,bai.0010008045.inc/[Scan_id_product='0010008045';'0010008863';'0010023648';'0010023670']!load,bai.0010008045.inc/" 08.bai.csv
grep -q "0010023670" 08.bai.csv || echo "WARN: 08.bai.csv load line not patched – check the file manually"

# 2) bai.0010008045.inc – CZ: priority pollování (r1 = nejčastěji, r5 = občas). Bez priority ebusd
#                          registr nikdy sám nečte a v HA je „unknown“.
#                          EN: poll priorities (r1 = most often, r5 = rarely). Without a priority
#                          ebusd never polls the register and HA shows "unknown".
F=bai.0010008045.inc
for n in FlowTemp Statenumber ModulationDesired HeatingDemand DCRoomthermostat ExtFlowTempDesiredMin; do
  sed -i "s/^r,,,$n,/r1,,,$n,/" $F
done
for n in ReturnTemp WP PartloadHcKW EBusHeatcontrol WaterPressure Currenterror; do
  sed -i "s/^r,,,$n,/r2,,,$n,/" $F
done
for n in HcHours HcStarts FlowsetHcMax HcPumpMode PowerValue Status01 Status02 Templimiter OutdoorstempSensor HwcTempMax WPPostrunTime AntiCondensValue; do
  sed -i "s/^r,,,$n,/r5,,,$n,/" $F
done

# 3) CZ: d.77 (výkon pro TV, registr 0xA9) – u Vaillant eloBLOCK (sesterský model Ray) tímto
#        registrem někteří řídí výkon; u Ray 6 KE v samostatném režimu stačí d.00. Přidáno jen pro čtení/ladění.
#    EN: d.77 (DHW partload, register 0xA9) – on Vaillant eloBLOCK (Ray's twin) some people control
#        power via this register; on Ray 6 KE in standalone mode d.00 is enough. Added for reading/debugging.
grep -q PartloadHwcKW $F || cat >> $F <<'EOF'
# --- eloBLOCK/Ray: d.77 DHW partload (register 0xA9) ---
r2,,,PartloadHwcKW,d.77 hot water partload,,,b509,0da900,value,,UCH,,kW,
w,,install,PartloadHwcKW,d.77 hot water partload,,,b509,0ea900,value,,UCH,,kW,
EOF

echo "done – restart ebusd"
