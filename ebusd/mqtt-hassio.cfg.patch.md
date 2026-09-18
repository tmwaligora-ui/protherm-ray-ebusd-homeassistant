# mqtt-hassio.cfg

CZ: Add-on ebusd vytvoří `/addon_configs/<slug>_ebusd/mqtt-hassio.cfg` (při prvním startu se `seed_mqtt_cfg: true`).
Výchozí filtr `filter-name` propouští do Home Assistanta jen zprávy, jejichž název obsahuje vybraná slova –
registry jako `Statenumber`, `PartloadHcKW`, `WaterPressure` nebo `DCRoomthermostat` ve výchozím nastavení
**neprojdou** a v HA se neobjeví. Rozšiř řádek `filter-name` a poté nastav `seed_mqtt_cfg: false`, aby ho add-on nepřepsal.

EN: The ebusd add-on creates `/addon_configs/<slug>_ebusd/mqtt-hassio.cfg` (on first start with `seed_mqtt_cfg: true`).
The default `filter-name` only passes messages whose name contains selected words – registers such as
`Statenumber`, `PartloadHcKW`, `WaterPressure` or `DCRoomthermostat` are **filtered out** and never appear in HA.
Extend the `filter-name` line and then set `seed_mqtt_cfg: false` so the add-on does not overwrite it.

```
filter-name = status|temp|humidity|yield|count|energy|power|runtime|hours|starts|mode|curve|^load$|^party$|sensor|time|statenumber|modulation|demand|partload|^wp$|ebusheatcontrol|roomthermostat|pressure|flowtempdesired|error|flame|^ionis
```

CZ: Po změně restartuj add-on. Pokud se hodnoty v HA ukazují jako „unknown“, počkej na další poll
(viz priority v `bai.inc.patch.sh`) nebo je vynuť přes HTTP API: `http://HA_IP:8889/data/bai/Statenumber?maxage=1`.

EN: Restart the add-on afterwards. If values show as "unknown" in HA, wait for the next poll
(see priorities in `bai.inc.patch.sh`) or force a read via the HTTP API: `http://HA_IP:8889/data/bai/Statenumber?maxage=1`.
