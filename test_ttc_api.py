"""
Step 1: Verify the Toronto Open Data CKAN API actually responds and see
what it gives us, before writing any real extraction/pipeline code.

Run this locally:
    pip install requests
    python test_ttc_api.py

What it does:
    1. Calls package_show for each of the three TTC delay datasets
       (subway, bus, streetcar) to see if they exist and what resources
       (files / tables) they contain.
    2. For any resource marked "datastore_active" (meaning it's a real
       queryable table, not just a downloadable file), it pulls a
       5-row sample via datastore_search so we can see actual columns.
    3. Saves the raw package metadata to a local JSON file so we can
       inspect it later without re-hitting the API.
"""

import json
import requests

BASE_URL = "https://ckan0.cf.opendata.inter.prod-toronto.ca"
PACKAGE_IDS = [
    "ttc-subway-delay-data",
    "ttc-bus-delay-data",
    "ttc-streetcar-delay-data",
]


def get_package(package_id: str) -> dict:
    """Fetch metadata + resource list for a dataset ('package')."""
    url = f"{BASE_URL}/api/3/action/package_show"
    resp = requests.get(url, params={"id": package_id}, timeout=30)
    resp.raise_for_status()
    return resp.json()


def get_sample_rows(resource_id: str, limit: int = 5) -> dict:
    """Pull a small sample from a datastore-active resource."""
    url = f"{BASE_URL}/api/3/action/datastore_search"
    resp = requests.get(
        url, params={"id": resource_id, "limit": limit}, timeout=30
    )
    resp.raise_for_status()
    return resp.json()


def main():
    all_metadata = {}

    for package_id in PACKAGE_IDS:
        print(f"\n{'=' * 60}")
        print(f"Dataset: {package_id}")
        print("=" * 60)

        try:
            package_response = get_package(package_id)
        except requests.exceptions.RequestException as e:
            print(f"  FAILED to reach API for this dataset: {e}")
            continue

        if not package_response.get("success"):
            print(f"  API responded but reported failure: {package_response}")
            continue

        result = package_response["result"]
        all_metadata[package_id] = result

        print(f"  Title: {result.get('title')}")
        print(f"  Last refreshed: {result.get('last_refreshed', 'unknown')}")
        print(f"  Number of resources: {len(result.get('resources', []))}")

        for resource in result.get("resources", []):
            print(f"\n  --- Resource: {resource.get('name')} ---")
            print(f"      Format: {resource.get('format')}")
            print(f"      datastore_active: {resource.get('datastore_active')}")
            print(f"      URL: {resource.get('url')}")

            if resource.get("datastore_active"):
                try:
                    sample = get_sample_rows(resource["id"], limit=5)
                    if sample.get("success"):
                        fields = sample["result"].get("fields", [])
                        records = sample["result"].get("records", [])
                        field_names = [f["id"] for f in fields]
                        print(f"      Columns: {field_names}")
                        print(f"      Sample row: {records[0] if records else 'no records'}")
                    else:
                        print(f"      datastore_search reported failure: {sample}")
                except requests.exceptions.RequestException as e:
                    print(f"      FAILED to sample this resource: {e}")

    # Save everything we found so we can look at it in detail later
    with open("ttc_package_metadata.json", "w") as f:
        json.dump(all_metadata, f, indent=2, default=str)

    print(f"\n{'=' * 60}")
    print("Done. Full metadata saved to ttc_package_metadata.json")
    print("=" * 60)


if __name__ == "__main__":
    main()
