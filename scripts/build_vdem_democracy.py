#!/usr/bin/env python3
"""Build Tellus's ten-year Electoral Democracy Index extract from a V-Dem Core ZIP."""

import argparse
import csv
import io
import json
import re
import zipfile
from pathlib import Path


OUTPUT = (
    Path(__file__).resolve().parents[1]
    / "iOS/Tellus/Features/CountryGuide/DemocracySafety/vdem-democracy.json"
)


def extract(archive_path):
    with zipfile.ZipFile(archive_path) as archive:
        [(member, version)] = [
            (member, int(match[1]))
            for member in archive.namelist()
            if (match := re.fullmatch(r"V-Dem-CY-Core-v(\d+)\.csv", Path(member).name))
            and not member.startswith("__MACOSX/")
        ]
        with io.TextIOWrapper(archive.open(member), encoding="utf-8-sig", newline="") as source:
            reader = csv.DictReader(source)
            required = {"country_text_id", "year", "v2x_polyarchy"}
            if not required.issubset(reader.fieldnames or []):
                raise ValueError("V-Dem CSV is missing required columns")
            countries = collect_observations(reader)
    return {"version": version, "countries": countries}


def collect_observations(rows):
    observations = {}
    latest_year = 0
    for row in rows:
        country = row["country_text_id"]
        year = int(row["year"])
        latest_year = max(latest_year, year)
        score = row["v2x_polyarchy"]
        if score in {"", "NA"}:
            continue
        value = float(score)
        if not 0 <= value <= 1:
            raise ValueError(f"Invalid Electoral Democracy Index for {country} in {year}")
        years = observations.setdefault(country, {})
        if year in years:
            raise ValueError(f"Duplicate V-Dem observation for {country} in {year}")
        years[year] = value

    first_year = latest_year - 9
    countries = {}
    for country, years in sorted(observations.items()):
        recent = [{"year": year, "value": years[year]} for year in sorted(years) if year >= first_year]
        if recent:
            countries[country] = recent
    if not countries:
        raise ValueError("No recent Electoral Democracy Index observations found")
    return countries


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path, help="V-Dem Country-Year Core CSV ZIP")
    args = parser.parse_args()
    extract_data = extract(args.archive)
    # Keep one country per line so data updates are easy to review.
    rows = [
        f"    {json.dumps(country)}: {json.dumps(series, separators=(',', ':'))}"
        for country, series in extract_data["countries"].items()
    ]
    output = '{\n  "version": %d,\n  "countries": {\n%s\n  }\n}\n' % (extract_data["version"], ",\n".join(rows))
    OUTPUT.write_text(output, encoding="utf-8")


if __name__ == "__main__":
    main()
