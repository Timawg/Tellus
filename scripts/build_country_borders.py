#!/usr/bin/env python3
"""Builds Tellus/Resources/country-borders.geojson, the country outlines drawn
when a country is selected.

Source: Natural Earth 1:50m Admin 0 - Countries (public domain),
https://www.naturalearthdata.com. Download ne_50m_admin_0_countries.geojson
from https://github.com/nvkelso/natural-earth-vector/tree/master/geojson and
the app's country list from
https://cdn.jsdelivr.net/gh/mledoze/countries@master/countries.json, then:

    python3 scripts/build_country_borders.py ne_50m_admin_0_countries.geojson countries.json

Each feature gets one property, "cca3", the code the app's country list uses.
Coordinates are rounded to 3 decimals (about 100 m), which is plenty at
country zoom and keeps the file small.
"""

import json
import sys

# Natural Earth codes that differ from the app's country list.
CODE_OVERRIDES = {
    "KOS": "UNK",  # Kosovo
    # Shown as part of these countries in the app's country data.
    "SOL": "SOM",  # Somaliland
    "CYN": "CYP",  # Northern Cyprus
}
# Disputed areas left out rather than given to either side.
SKIPPED = {"KAS"}  # Siachen Glacier

# Territories Natural Earth draws as part of another country. Their pieces are
# copied out by location, and also stay in the parent's outline.
TERRITORY_PARENTS = {
    "GUF": "FRA", "GLP": "FRA", "MTQ": "FRA", "MYT": "FRA", "REU": "FRA",
    "SJM": "NOR", "BES": "NLD",
    "CXR": "AUS", "CCK": "AUS",
}
# How far from the territory's centre a piece may be, in degrees.
TERRITORY_RADIUS = {"GUF": 4}
DEFAULT_TERRITORY_RADIUS = 1.5
# Spread-out territories are picked by box instead:
# (min latitude, max latitude, min longitude, max longitude).
TERRITORY_BOUNDS = {"SJM": (74, 82, 5, 35)}  # Svalbard


def round_ring(ring):
    rounded = [[round(x, 3), round(y, 3)] for x, y in ring]
    # Drop points that rounding made identical.
    deduped = [rounded[0]]
    for point in rounded[1:]:
        if point != deduped[-1]:
            deduped.append(point)
    return deduped


def polygons(geometry):
    if geometry["type"] == "Polygon":
        return [geometry["coordinates"]]
    if geometry["type"] == "MultiPolygon":
        return geometry["coordinates"]
    return []


def centre(polygon):
    ring = polygon[0]
    xs = [p[0] for p in ring]
    ys = [p[1] for p in ring]
    return (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2


def main(natural_earth_path, countries_path):
    features = json.load(open(natural_earth_path))["features"]
    countries = {c["cca3"]: c for c in json.load(open(countries_path))}

    by_code = {}
    for feature in features:
        p = feature["properties"]
        if p["ADM0_A3"] in SKIPPED:
            continue
        code = CODE_OVERRIDES.get(p["ADM0_A3"])
        if code is None:
            code = p["ISO_A3_EH"] if p["ISO_A3_EH"] in countries else p["ADM0_A3"]
        if code not in countries:
            print(f"skipping {p['NAME']} ({p['ADM0_A3']}): not in the country list", file=sys.stderr)
            continue
        by_code.setdefault(code, []).extend(polygons(feature["geometry"]))

    for code, parent in TERRITORY_PARENTS.items():
        if code in by_code or code not in countries:
            continue
        latitude, longitude = countries[code]["latlng"]
        radius = TERRITORY_RADIUS.get(code, DEFAULT_TERRITORY_RADIUS)
        bounds = TERRITORY_BOUNDS.get(code, (
            latitude - radius, latitude + radius, longitude - radius, longitude + radius
        ))

        def inside(polygon):
            x, y = centre(polygon)
            return bounds[0] <= y <= bounds[1] and bounds[2] <= x <= bounds[3]

        pieces = [polygon for polygon in by_code.get(parent, []) if inside(polygon)]
        if pieces:
            by_code[code] = pieces
        else:
            print(f"no pieces of {parent} found for {code}", file=sys.stderr)

    output = {
        "type": "FeatureCollection",
        "features": [
            {
                "type": "Feature",
                "properties": {"cca3": code},
                "geometry": {
                    "type": "MultiPolygon",
                    "coordinates": [[round_ring(ring) for ring in polygon] for polygon in by_code[code]],
                },
            }
            for code in sorted(by_code)
        ],
    }
    missing = sorted(set(countries) - set(by_code))
    print(f"{len(by_code)} countries with borders; none for {', '.join(missing)}", file=sys.stderr)
    json.dump(output, open("Tellus/Resources/country-borders.geojson", "w"), separators=(",", ":"))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
