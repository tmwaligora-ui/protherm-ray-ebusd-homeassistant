# Protherm Ray KE + eBUS + Home Assistant – řízení elektrokotle přebytky z FVE

*[English version below](#english)*

Řízení elektrokotle **Protherm Ray 6 KE** (verze /14, výrobek 0010023670 – konstrukčně shodný s Vaillant eloBLOCK)
z Home Assistanta po **eBUS**, po 1 kW stupních podle přebytků fotovoltaiky. Bez cloudů, bez zásahu do kotle.

Vzniklo v září 2026 po dvou dnech ladění. Hlavní přínos repozitáře jsou **věci, které nikde nejsou napsané**
(sekce *Na co si dát pozor*) – například že eBUS povel `SetMode` přepne Ray do režimu, ve kterém topí **jen 1 kW**.

## Co je potřeba

| Část | Použito |
|---|---|
| Kotel | Protherm Ray 6 KE /14 EU (eBUS adresa 08, `MF=Vaillant;ID=BAI00;SW=0109;HW=7503`) |
| eBUS adaptér | [eBUS Adapter Shield C6](https://adapter.ebusd.eu/v5-c6/) (Wi‑Fi, firmware ≥ 20260917) |
| ebusd | add-on [LukasGrebe/ha-addons](https://github.com/LukasGrebe/ha-addons) (ebusd 26.1) + Mosquitto |
| Požadavek topení | Shelly 1 Gen3 (bezpotenciální kontakt) na svorce **RT24** kotle |
| FVE data | SolaX X3-Hybrid-G4 přes [homeassistant-solax-modbus](https://github.com/wills106/homeassistant-solax-modbus) – jde použít jakýkoli střídač, potřebuješ výrobu, spotřebu domu, výkon baterie, SoC, odběr/přetok |
| Předpověď | [Forecast.Solar](https://www.home-assistant.io/integrations/forecast_solar/) (volitelné) |

## Jak to funguje

```
 FVE / střídač ──► Home Assistant ──► automatizace (každé 2 min)
                                        │
                     ┌──────────────────┼──────────────────┐
                     ▼                  ▼                  ▼
              Shelly → RT24      MQTT → ebusd → eBUS   (d.71 max. teplota
              (požadavek topení)  d.00 = výkon 1–6 kW    jen při změně)
```

1. **Požadavek topení** dává Shelly sepnutím svorky RT24 (pokojový termostat). Shelly má nastaveno
   `auto_off = 600 s`; automatizace ho každé 2 minuty znovu sepne (heartbeat). Když spadne HA nebo Wi‑Fi,
   kotel do 10 minut sám přestane topit.
2. **Výkon** se zapisuje do registru **d.00** (`PartloadHcKW`, 1–6 kW). V samostatném režimu kotel topí
   *přesně* nastaveným výkonem – ověřeno měřením (d.00 = 1…6 → +1,0…6,0 kW, změna do 10 s).
3. **Teplota výstupu** se zapisuje do **d.71** (`FlowsetHcMax`) jen při změně slideru. Kotel topí na
   min(teplota na panelu, d.71).
4. Automatizace přidává 1 kW, když je přebytek ≥ 1 kW + rezerva (nebo když střídač škrtí na limitu přetoku,
   nebo když je baterie plná a přetok zakázaný – „sonda“), a ubírá 1 kW, když se bere ze sítě/baterie,
   klesá SoC nebo je dům přehřátý. Mezi stupni čeká 4 min (přebytek jistý dle předpovědi) / 10 min.

## Na co si dát pozor (to důležité)

- **Nikdy neposílej kotli `SetMode`** (`ebusd/bai/SetMode/set`). Ray se přepne do režimu „řízen regulátorem“
  (`EBusHeatcontrol = yes`) a v něm topí **pouze 1 kW** bez ohledu na d.00 – zřejmě čeká na povel k výkonu,
  který ebusd neumí poslat. Z tohoto režimu kotel **nevyleze jinak než vypnutím napájení jističem**
  (čekání bez povelu nepomůže). V samostatném režimu (RT24 + d.00) jede naplno.
- **Čerpadlo**: v eBUS režimu běželo jen při ohřevu + doběh, voda v kotli se za 2 min ohřála na 75 °C,
  kotel vypnul a 40 min chladl – dům nedostal nic. V samostatném režimu s d.18 = 1 (permanent) čerpadlo
  běží po celou dobu sepnutého RT24.
- **Svorka X17 (Limiter/GND)**: rozepnuto = kotel sníží výkon o D.153 kW. Pokud tam nic nemáš, dej propojku
  nebo D.152 = 0. (Není to příčina „1 kW“ problému – to je SetMode.)
- **ebusd vybere špatnou definici**: pro produkt 0010023670 zvolí `bai.308523.inc` (nový registrový formát) →
  chyby `invalid position`, žádné hodnoty. Použij lokální konfiguraci a namapuj Ray na `bai.0010008045.inc`
  (viz `ebusd/bai.inc.patch.sh`). Registry s 16bitovým ID (`0407`, `0449`…) Ray nezná.
- **Registry „unknown“ v HA**: ebusd bez priority (`r1`…`r9`) registr nepolluje. Priority viz patch.
- **MQTT filtr**: výchozí `filter-name` v `mqtt-hassio.cfg` odfiltruje `Statenumber`, `PartloadHcKW`,
  `WaterPressure`… – rozšiř ho (`ebusd/mqtt-hassio.cfg.patch.md`) a nastav `seed_mqtt_cfg: false`.
- **Zápis d.00 / d.71 vyžaduje `--accesslevel=*`** (registry úrovně *install*).
- **ebusd po startu 3–4 min „nevidí“ kotel** (chytá se rušivého zařízení na sběrnici, adresa 05).
  Řešení: `--scanconfig=08`, kotel se najde do 10 s.
- **`ModulationDesired` (%) se u Ray nikdy nemění** (stále 17 %) – nepoužívej ho jako ukazatel výkonu.
  Skutečný výkon = d.00, když je stav S.4 (viz `template_sensors.yaml`).
- **Přetok**: pokud střídač nesmí přetékat do sítě (limit 0 W), přebytek není vidět – povol malý přetok
  (u nás 1000 W) a automatizace pozná „škrcení“ (`capped`) jako signál, že výkon je.
- **d.00 a d.71 jsou v EEPROM kotle** – zapisuj je jen při změně (stupně se mění pár× za hodinu, to je OK),
  nikdy cyklicky.
- Elektrokotel v září dům rychle přehřeje → automatizace má strop „netopit, když je v domě víc než X °C“.
  Reálné využití přebytků kotlem je v topné sezóně; v létě je lepší cíl ohřev TV.

## Instalace (stručně)

1. Adaptér Shield C6 připoj k eBUS svorkám kotle, připoj na Wi‑Fi, na routeru mu rezervuj IP.
2. Nainstaluj Mosquitto a ebusd add-on. Do `/addon_configs/<slug>_ebusd/ebusd-configuration/` stáhni
   `broadcast.csv`, `memory.csv` a `vaillant/{scan.csv,08.bai.csv,bai.0010008045.inc}` z
   [eBUS/ebus.github.io](https://github.com/eBUS/ebus.github.io/tree/main/en) a spusť `ebusd/bai.inc.patch.sh`.
3. Nastav add-on podle `ebusd/addon-options.yaml`, uprav `mqtt-hassio.cfg` podle `ebusd/mqtt-hassio.cfg.patch.md`.
4. Shelly na RT24: `in_mode: detached`, `initial_state: off`, `auto_off: true`, `auto_off_delay: 600`.
5. V HA vytvoř pomocníky (`homeassistant/helpers.yaml`), template senzory, automatizace a dashboard.
6. Na kotli nastav d.18 = 1 (čerpadlo permanent), zkontroluj X17. Pokud jsi někdy poslal `SetMode`,
   kotel vypni a zapni jističem.

## Soubory

```
ebusd/addon-options.yaml          volby add-onu ebusd
ebusd/bai.inc.patch.sh            úprava konfigurace ebusd (definice pro Ray, priority, d.77)
ebusd/mqtt-hassio.cfg.patch.md    rozšíření MQTT filtru
homeassistant/helpers.yaml        pomocníci (input_*)
homeassistant/template_sensors.yaml  průměrná teplota, příkon kotle, topí / čerpadlo
homeassistant/automations/        řízení podle přebytků, zápis d.71
homeassistant/dashboards/         dashboard Elektrokotel
```

## Poděkování / zdroje

- [ebusd](https://github.com/john30/ebusd) a [ebusd-configuration](https://github.com/eBUS/ebus.github.io)
- [Vaillant eloBLOCK mit Home Assistant, ebusd und SMA SEMP](https://www.hensiek.com/blog/eloblock-smart) – registr d.77 u eloBLOCK
- Uživatel *impaler* z CZ fóra (Ray 24 KE + `bai.0010008045.inc`)
- Diagnostika a automatizace vznikly ve spolupráci s Claude (Anthropic)

Licence: MIT.

---

<a name="english"></a>
# Protherm Ray KE + eBUS + Home Assistant – electric boiler driven by PV surplus

Controlling a **Protherm Ray 6 KE** electric boiler (/14 series, product 0010023670 – same hardware as the
Vaillant eloBLOCK) from Home Assistant over **eBUS**, in 1 kW steps according to photovoltaic surplus.
No cloud, no modification of the boiler.

Built in September 2026 after two days of debugging. The main value of this repo is the list of
**things nobody wrote down** (*Pitfalls*) – e.g. that the eBUS `SetMode` command switches the Ray into a mode
where it heats with **1 kW only**.

## Hardware / software

| Part | Used |
|---|---|
| Boiler | Protherm Ray 6 KE /14 EU (eBUS address 08, `MF=Vaillant;ID=BAI00;SW=0109;HW=7503`) |
| eBUS adapter | [eBUS Adapter Shield C6](https://adapter.ebusd.eu/v5-c6/) (Wi‑Fi, firmware ≥ 20260917) |
| ebusd | [LukasGrebe/ha-addons](https://github.com/LukasGrebe/ha-addons) add-on (ebusd 26.1) + Mosquitto |
| Heat demand | Shelly 1 Gen3 (dry contact) on the boiler's **RT24** terminal |
| PV data | SolaX X3-Hybrid-G4 via [homeassistant-solax-modbus](https://github.com/wills106/homeassistant-solax-modbus) – any inverter works as long as you have PV power, house load, battery power, SoC, grid import/export |
| Forecast | [Forecast.Solar](https://www.home-assistant.io/integrations/forecast_solar/) (optional) |

## How it works

```
 PV / inverter ──► Home Assistant ──► automation (every 2 min)
                                        │
                     ┌──────────────────┼──────────────────┐
                     ▼                  ▼                  ▼
              Shelly → RT24      MQTT → ebusd → eBUS   (d.71 max flow temp,
              (heat demand)      d.00 = power 1–6 kW    on change only)
```

1. **Heat demand** = Shelly closing the RT24 (room thermostat) terminal. The Shelly has `auto_off = 600 s`;
   the automation re-closes it every 2 minutes (heartbeat). If HA or Wi‑Fi dies, the boiler stops within 10 min.
2. **Power** is written to register **d.00** (`PartloadHcKW`, 1–6 kW). In standalone mode the boiler runs
   *exactly* at that power – verified by measurement (d.00 = 1…6 → +1.0…6.0 kW, change within 10 s).
3. **Flow temperature** is written to **d.71** (`FlowsetHcMax`) only when the slider changes. The boiler heats
   to min(panel setpoint, d.71).
4. The automation adds 1 kW when surplus ≥ 1 kW + reserve (or the inverter is curtailing at the export limit,
   or the battery is full with export disabled – "probe"), and removes 1 kW when importing from grid/battery,
   SoC drops or the house is too warm. It waits 4 min (surplus confirmed by forecast) / 10 min between steps.

## Pitfalls (the important part)

- **Never send `SetMode`** (`ebusd/bai/SetMode/set`) to the boiler. The Ray switches to "controlled by an eBUS
  controller" mode (`EBusHeatcontrol = yes`) and then heats with **1 kW only**, regardless of d.00 – it seems to
  wait for a power command ebusd cannot send. The only way out is **power-cycling the boiler at the breaker**
  (waiting without commands does not help). In standalone mode (RT24 + d.00) it runs at full power.
- **Pump**: in eBUS mode it ran only while heating + overrun; the boiler's own water reached 75 °C in 2 minutes,
  the boiler stopped and cooled for 40 minutes – the house got nothing. In standalone mode with d.18 = 1
  (permanent) the pump runs as long as RT24 is closed.
- **Terminal X17 (Limiter/GND)**: open = the boiler reduces power by D.153 kW. If nothing is connected, bridge it
  or set D.152 = 0. (This is *not* the cause of the 1 kW problem – SetMode is.)
- **ebusd picks the wrong definition**: for product 0010023670 it selects `bai.308523.inc` (new register layout) →
  `invalid position` errors, no values. Use a local config and map the Ray to `bai.0010008045.inc`
  (see `ebusd/bai.inc.patch.sh`). Registers with 16‑bit IDs (`0407`, `0449`…) are unknown to the Ray.
- **"unknown" values in HA**: ebusd does not poll a register without a priority (`r1`…`r9`). See the patch.
- **MQTT filter**: the default `filter-name` in `mqtt-hassio.cfg` drops `Statenumber`, `PartloadHcKW`,
  `WaterPressure`… – extend it (`ebusd/mqtt-hassio.cfg.patch.md`) and set `seed_mqtt_cfg: false`.
- **Writing d.00 / d.71 needs `--accesslevel=*`** (install-level registers).
- **ebusd does not "see" the boiler for 3–4 min after start** (it latches onto a noise device at address 05).
  Fix: `--scanconfig=08` – the boiler is found within 10 s.
- **`ModulationDesired` (%) never changes on the Ray** (stuck at 17 %) – do not use it as a power indicator.
  Real power = d.00 while state is S.4 (see `template_sensors.yaml`).
- **Export**: if the inverter must not export (limit 0 W) the surplus is invisible – allow a small export
  (1000 W here); the automation treats "curtailing" (`capped`) as a sign that power is available.
- **d.00 and d.71 live in the boiler's EEPROM** – write them only on change (a few stage changes per hour is
  fine), never periodically.
- In September a 6 kW electric boiler overheats the house quickly → the automation has a "don't heat above X °C
  indoors" cap. The real use of PV surplus with the boiler is in the heating season; in summer a DHW tank is
  a better target.

## Installation (short)

1. Connect the Shield C6 adapter to the boiler's eBUS terminals, join it to Wi‑Fi, reserve its IP on the router.
2. Install Mosquitto and the ebusd add-on. Download `broadcast.csv`, `memory.csv` and
   `vaillant/{scan.csv,08.bai.csv,bai.0010008045.inc}` from
   [eBUS/ebus.github.io](https://github.com/eBUS/ebus.github.io/tree/main/en) into
   `/addon_configs/<slug>_ebusd/ebusd-configuration/` and run `ebusd/bai.inc.patch.sh`.
3. Configure the add-on per `ebusd/addon-options.yaml`, patch `mqtt-hassio.cfg` per `ebusd/mqtt-hassio.cfg.patch.md`.
4. Shelly on RT24: `in_mode: detached`, `initial_state: off`, `auto_off: true`, `auto_off_delay: 600`.
5. In HA create the helpers (`homeassistant/helpers.yaml`), template sensors, automations and the dashboard.
6. On the boiler set d.18 = 1 (pump permanent) and check X17. If you ever sent `SetMode`, power-cycle the boiler.

## Files

```
ebusd/addon-options.yaml          ebusd add-on options
ebusd/bai.inc.patch.sh            ebusd config patch (Ray definition mapping, poll priorities, d.77)
ebusd/mqtt-hassio.cfg.patch.md    MQTT filter extension
homeassistant/helpers.yaml        helpers (input_*)
homeassistant/template_sensors.yaml  average indoor temp, boiler power, heating / pump running
homeassistant/automations/        surplus control, d.71 write
homeassistant/dashboards/         "Elektrokotel" dashboard
```

## Credits / sources

- [ebusd](https://github.com/john30/ebusd) and [ebusd-configuration](https://github.com/eBUS/ebus.github.io)
- [Vaillant eloBLOCK mit Home Assistant, ebusd und SMA SEMP](https://www.hensiek.com/blog/eloblock-smart) – register d.77 on eloBLOCK
- User *impaler* from the Czech HA forum (Ray 24 KE + `bai.0010008045.inc`)
- Diagnostics and automation developed together with Claude (Anthropic)

License: MIT.
