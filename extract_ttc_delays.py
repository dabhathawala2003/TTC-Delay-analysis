"""
Step 2: Pull the FULL current dataset (since 2025) for subway, bus, and
streetcar delays, handling pagination properly, and normalize the
inconsistent Date field we spotted in the test run.

Run locally:
    python extract_ttc_delays.py

Output:
    One JSON file per mode in ./output/, e.g. output/subway_delays.json
    Each row has a clean "date" field (YYYY-MM-DD, no time component)
    in addition to the original raw fields.
"""

import json
import os
import requests

BASE_URL = "https://ckan0.cf.opendata.inter.prod-toronto.ca"

# Package ids confirmed live in the test run
DATASETS = {
    "subway": "ttc-subway-delay-data",
    "bus": "ttc-bus-delay-data",
    "streetcar": "ttc-streetcar-delay-data",
}

PAGE_SIZE = 1000
OUTPUT_DIR = "output"


def get_active_data_resource_id(package_id: str) -> str:
    """
    Find the datastore_active resource that holds the actual delay
    records (not the Code Descriptions lookup table).
    """
    url = f"{BASE_URL}/api/3/action/package_show"
    resp = requests.get(url, params={"id": package_id}, timeout=30)
    resp.raise_for_status()
    result = resp.json()["result"]

    for resource in result["resources"]:
        if resource.get("datastore_active") and "since 2025" in resource.get("name", ""):
            return resource["id"]

    raise ValueError(f"No active 'since 2025' resource found for {package_id}")


def get_code_lookup_resource_id(package_id: str) -> str:
    """Find the datastore_active Code Descriptions lookup table."""
    url = f"{BASE_URL}/api/3/action/package_show"
    resp = requests.get(url, params={"id": package_id}, timeout=30)
    resp.raise_for_status()
    result = resp.json()["result"]

    for resource in result["resources"]:
        if resource.get("datastore_active") and resource.get("name") == "Code Descriptions":
            return resource["id"]

    raise ValueError(f"No Code Descriptions lookup found for {package_id}")


def fetch_all_rows(resource_id: str) -> list:
    """Page through datastore_search until we've pulled every row."""
    url = f"{BASE_URL}/api/3/action/datastore_search"
    all_records = []
    offset = 0

    while True:
        resp = requests.get(
            url,
            params={"id": resource_id, "limit": PAGE_SIZE, "offset": offset},
            timeout=30,
        )
        resp.raise_for_status()
        payload = resp.json()

        if not payload.get("success"):
            raise RuntimeError(f"datastore_search failed: {payload}")

        records = payload["result"]["records"]
        all_records.extend(records)

        if len(records) < PAGE_SIZE:
            break  # last page was partial or empty, we're done

        offset += PAGE_SIZE

    return all_records


def normalize_date(raw_date: str) -> str:
    """
    Handle the two formats seen: '2025-01-01' and '2025-01-01T00:00:00'.
    Always return just the date portion.
    """
    if raw_date is None:
        return None
    return raw_date.split("T")[0]


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    for mode, package_id in DATASETS.items():
        print(f"\n{'=' * 50}")
        print(f"Mode: {mode}")
        print("=" * 50)

        # 1. Pull the delay code lookup table for this mode
        code_resource_id = get_code_lookup_resource_id(package_id)
        code_records = fetch_all_rows(code_resource_id)
        print(f"  Delay codes: {len(code_records)} rows")

        with open(f"{OUTPUT_DIR}/{mode}_delay_codes.json", "w") as f:
            json.dump(code_records, f, indent=2)

        # 2. Pull the actual delay data
        data_resource_id = get_active_data_resource_id(package_id)
        records = fetch_all_rows(data_resource_id)
        print(f"  Delay records: {len(records)} rows")

        # 3. Normalize the Date field on every row
        for row in records:
            row["date_clean"] = normalize_date(row.get("Date"))

        with open(f"{OUTPUT_DIR}/{mode}_delays.json", "w") as f:
            json.dump(records, f, indent=2)

        # Quick sanity check: show the earliest and latest clean dates
        dates = [r["date_clean"] for r in records if r["date_clean"]]
        if dates:
            print(f"  Date range: {min(dates)} to {max(dates)}")

    print(f"\n{'=' * 50}")
    print(f"Done. Files saved in ./{OUTPUT_DIR}/")
    print("=" * 50)


if __name__ == "__main__":
    main()
