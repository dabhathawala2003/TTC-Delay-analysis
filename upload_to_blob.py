"""
Step 3: Upload the locally extracted JSON files into Azure Blob Storage
(the raw-ttc-data container), partitioned by the date we pulled them.

Setup (PowerShell, one time per terminal session):
    pip install azure-storage-blob
    $env:AZURE_STORAGE_CONNECTION_STRING="<paste your connection string here>"

Then run:
    python upload_to_blob.py

This does NOT hardcode any credentials in the script itself -- the
connection string is read from an environment variable so it never
ends up committed to GitHub later.

Files land in Blob Storage like:
    raw-ttc-data/pull_date=2026-08-27/subway_delays.json
    raw-ttc-data/pull_date=2026-08-27/subway_delay_codes.json
    raw-ttc-data/pull_date=2026-08-27/bus_delays.json
    ...

Partitioning by pull_date means every day's pull is kept separately --
nothing gets overwritten, and Snowflake can later load by date range.
"""

import os
from datetime import date
from azure.storage.blob import BlobServiceClient

CONTAINER_NAME = "raw-ttc-data"
LOCAL_OUTPUT_DIR = "output"

FILES_TO_UPLOAD = [
    "subway_delays.json",
    "subway_delay_codes.json",
    "bus_delays.json",
    "bus_delay_codes.json",
    "streetcar_delays.json",
    "streetcar_delay_codes.json",
]


def main():
    connection_string = os.environ.get("AZURE_STORAGE_CONNECTION_STRING")
    if not connection_string:
        raise EnvironmentError(
            "AZURE_STORAGE_CONNECTION_STRING is not set. "
            "Run: $env:AZURE_STORAGE_CONNECTION_STRING=\"<your connection string>\" "
            "in this terminal session first."
        )

    blob_service_client = BlobServiceClient.from_connection_string(connection_string)
    container_client = blob_service_client.get_container_client(CONTAINER_NAME)

    pull_date = date.today().isoformat()  # e.g. "2026-08-27"
    print(f"Uploading files under pull_date={pull_date}\n")

    for filename in FILES_TO_UPLOAD:
        local_path = os.path.join(LOCAL_OUTPUT_DIR, filename)

        if not os.path.exists(local_path):
            print(f"  SKIPPED (not found locally): {filename}")
            continue

        blob_path = f"pull_date={pull_date}/{filename}"

        with open(local_path, "rb") as data:
            container_client.upload_blob(
                name=blob_path,
                data=data,
                overwrite=True,  # safe: re-running today just replaces today's copy
            )

        size_kb = os.path.getsize(local_path) / 1024
        print(f"  Uploaded: {blob_path} ({size_kb:.1f} KB)")

    print("\nDone. Check the raw-ttc-data container in the Azure Portal to confirm.")


if __name__ == "__main__":
    main()
