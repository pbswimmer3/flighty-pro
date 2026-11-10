#!/usr/bin/env python3
"""Regenerate FlightDeck/Resources/airports-world.json.

The curated `airports.json` (~110 airports with terminal notes and minimum
connection times) is what the Airports tab lists. This file is the fallback
behind it: every IATA-coded airport in the world, with just enough to put it
on a map and tell the time there. Without it, any flight touching an airport
outside the curated 110 — John Wayne (SNA), say — lost its route map, its
mileage, and anchored the traffic map on the wrong field.

Source: https://github.com/mwgg/Airports (MIT licence), `airports.json`.
Country codes are expanded with `pycountry` so they read the same way the
curated file writes them ("United States", not "US") — the Passport counts
countries by that string, so the two files must agree.

Usage:
    pip install pycountry
    curl -sSLo /tmp/mwgg.json https://raw.githubusercontent.com/mwgg/Airports/master/airports.json
    python3 scripts/build_world_airports.py /tmp/mwgg.json FlightDeck/Resources/airports-world.json
"""
import json
import re
import sys

import pycountry

# Where pycountry's name differs from what people say — and from what the
# curated file already uses.
COUNTRY_OVERRIDES = {
    "XK": "Kosovo",
    "KS": "Kosovo",          # the source's own code for Pristina
    "CC": "Cocos Islands",
    "MF": "Saint Martin",
    "SX": "Sint Maarten",
    "RU": "Russia",
    "VN": "Vietnam",
    "TW": "Taiwan",
    "HK": "Hong Kong",
    "MO": "Macao",
    "KR": "South Korea",
    "KP": "North Korea",
    "CD": "DR Congo",
    "CG": "Congo",
    "FM": "Micronesia",
    "VG": "British Virgin Islands",
    "VI": "US Virgin Islands",
    "PS": "Palestine",
    "BQ": "Caribbean Netherlands",
    "SH": "Saint Helena",
    "FK": "Falkland Islands",
    "IR": "Iran",
    "SY": "Syria",
    "LA": "Laos",
    "BO": "Bolivia",
    "VE": "Venezuela",
    "TZ": "Tanzania",
    "MD": "Moldova",
    "BN": "Brunei",
    "CV": "Cape Verde",
    "SZ": "Eswatini",
    "TR": "Türkiye",
    "CZ": "Czechia",
}


def country_name(code: str) -> str:
    code = (code or "").upper()
    if code in COUNTRY_OVERRIDES:
        return COUNTRY_OVERRIDES[code]
    country = pycountry.countries.get(alpha_2=code)
    if country is None:
        return code
    return getattr(country, "common_name", None) or country.name


def main(source: str, destination: str) -> None:
    with open(source, encoding="utf-8") as fh:
        raw = json.load(fh)

    rows = {}
    for entry in raw.values():
        iata = (entry.get("iata") or "").strip().upper()
        tz = (entry.get("tz") or "").strip()
        if not re.fullmatch(r"[A-Z]{3}", iata) or not tz:
            continue
        name = (entry.get("name") or iata).strip()
        city = (entry.get("city") or entry.get("state") or name).strip()
        row = [
            iata,
            (entry.get("icao") or "").strip().upper(),
            name,
            city,
            country_name(entry.get("country")),
            round(float(entry["lat"]), 4),
            round(float(entry["lon"]), 4),
            tz,
        ]
        # A handful of codes appear twice (a closed field and its
        # replacement). Keep the one with an ICAO code, which is the one still
        # in use far more often than not.
        if iata in rows and rows[iata][1] and not row[1]:
            continue
        rows[iata] = row

    ordered = [rows[k] for k in sorted(rows)]
    with open(destination, "w", encoding="utf-8") as fh:
        fh.write("[\n")
        fh.write(",\n".join(json.dumps(r, ensure_ascii=False, separators=(",", ":")) for r in ordered))
        fh.write("\n]\n")
    print(f"wrote {len(ordered)} airports to {destination}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
