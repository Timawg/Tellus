#!/usr/bin/env python3
"""Validate the country boundaries and V-Dem extract bundled with Tellus."""

import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
COUNTRY_CODE = re.compile(r"[A-Z]{3}")


def require(condition, message):
    if not condition:
        raise ValueError(message)


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, f"duplicate JSON key {key!r}")
        result[key] = value
    return result


def reject_constant(value):
    raise ValueError(f"{value} is not a valid JSON number")


def in_range(value, lower, upper):
    return type(value) in (int, float) and lower <= value <= upper


def validate_ring(ring, label):
    require(isinstance(ring, list) and len(ring) >= 4, f"{label} needs at least four positions")
    for position in ring:
        require(
            isinstance(position, list) and len(position) == 2
            and in_range(position[0], -180, 180) and in_range(position[1], -90, 90),
            f"{label} has an invalid longitude/latitude position: {position!r}",
        )
    require(ring[0] == ring[-1], f"{label} is not closed")
    require(len({tuple(position) for position in ring}) >= 3, f"{label} needs three distinct positions")


def validate_boundaries(data):
    require(
        isinstance(data, dict) and data.get("type") == "FeatureCollection",
        "expected a GeoJSON FeatureCollection",
    )
    features = data.get("features")
    require(isinstance(features, list) and features, "expected a non-empty features array")

    codes = set()
    for index, feature in enumerate(features):
        require(
            isinstance(feature, dict) and feature.get("type") == "Feature",
            f"feature {index} must be a GeoJSON Feature",
        )
        properties = feature.get("properties")
        code = properties.get("cca3") if isinstance(properties, dict) else None
        require(isinstance(code, str) and COUNTRY_CODE.fullmatch(code), f"feature {index} has an invalid cca3")
        require(code not in codes, f"duplicate boundary for {code}")
        codes.add(code)

        geometry = feature.get("geometry")
        require(isinstance(geometry, dict), f"{code} is missing a geometry object")
        geometry_type = geometry.get("type")
        require(geometry_type in ("Polygon", "MultiPolygon"), f"{code} has unsupported geometry {geometry_type!r}")
        coordinates = geometry.get("coordinates")
        require(isinstance(coordinates, list) and coordinates, f"{code} has no coordinates")
        polygons = [coordinates] if geometry_type == "Polygon" else coordinates
        for polygon_index, polygon in enumerate(polygons, start=1):
            label = f"{code} polygon {polygon_index}"
            require(isinstance(polygon, list) and polygon, f"{label} has no rings")
            for ring_index, ring in enumerate(polygon, start=1):
                validate_ring(ring, f"{label}, ring {ring_index}")

    return f"{len(codes)} country boundaries"


def validate_democracy(data):
    require(isinstance(data, dict), "expected a V-Dem dataset object")
    version = data.get("version")
    require(type(version) is int and 0 < version <= sys.maxsize, "expected a positive integer V-Dem release version")
    countries = data.get("countries")
    require(isinstance(countries, dict) and countries, "expected a non-empty countries object")

    years = set()
    for code, series in countries.items():
        require(COUNTRY_CODE.fullmatch(code), f"invalid V-Dem area code {code!r}")
        require(isinstance(series, list) and series, f"{code} has no observations")
        previous_year = 0
        for index, observation in enumerate(series):
            require(isinstance(observation, dict), f"{code} observation {index} must be an object")
            year = observation.get("year")
            require(type(year) is int and 1 <= year <= 9999, f"{code} has an invalid observation year {year!r}")
            require(year > previous_year, f"{code} has a duplicate or out-of-order year {year}")
            require(in_range(observation.get("value"), 0, 1), f"{code} {year} has an invalid democracy score")
            years.add(year)
            previous_year = year

    first_year, last_year = min(years), max(years)
    require(last_year - first_year <= 9, f"V-Dem observations span more than ten years ({first_year}–{last_year})")
    return f"V-Dem v{version}, {len(countries)} areas, {first_year}–{last_year}"


def main():
    datasets = (
        ("iOS/Tellus/Features/Countries/Resources/country-borders.geojson", validate_boundaries),
        ("iOS/Tellus/Features/CountryGuide/DemocracySafety/vdem-democracy.json", validate_democracy),
    )
    for path, validate in datasets:
        try:
            with (ROOT / path).open(encoding="utf-8") as source:
                data = json.load(source, object_pairs_hook=unique_object, parse_constant=reject_constant)
            print(f"{path}: {validate(data)}")
        except (OSError, ValueError) as error:
            print(f"{path}: {error}", file=sys.stderr)
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
