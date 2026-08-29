import azure.functions as func
import datetime
import json
import logging
import os
import requests
from azure.storage.blob import BlobServiceClient

app = func.FunctionApp()

BASE_URL = "https://ckan0.cf.opendata.inter.prod-toronto.ca"
CONTAINER_NAME = "raw-ttc-data"
PAGE_SIZE = 1000

DATASETS = {
    "subway": "ttc-subway-delay-data",
    "bus": "ttc-bus-delay-data",
    "streetcar": "ttc-streetcar-delay-data",
}


def get_active_data_resource_id(package_id: str) -> str:
    url = f"{BASE_URL}/api/3/action/package_show"
    resp = requests.get(url, params={"id": package_id}, timeout=30)
    resp.raise_for_status()
    result = resp.json()["result"]

    for resource in result["resources"]:
        if resource.get("datastore_active") and "since 2025" in resource.get("name", ""):
            return resource["id"]

    raise ValueError(f"No active 'since 2025' resource found for {package_id}")


def get_code_lookup_resource_id(package_id: str) -> str:
    url = f"{BASE_URL}/api/3/action/package_show"
    resp = requests.get(url, params={"id": package_id}, timeout=30)
    resp.raise_for_status()
    result = resp.json()["result"]

    for resource in result["resources"]:
        if resource.get("datastore_active") and resource.get("name") == "Code Descriptions":
            return resource["id"]

    raise ValueError(f"No Code Descriptions lookup found for {package_id}")


def fetch_all_rows(resource_id: str) -> list:
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
            break

        offset += PAGE_SIZE

    return all_records


def normalize_date(raw_date):
    if raw_date is None:
        return None
    return raw_date.split("T")[0]


def upload_json_to_blob(container_client, blob_path: str, data: list) -> int:
    """Uploads a Python list as JSON directly to blob storage, no local file."""
    payload = json.dumps(data, indent=2).encode("utf-8")
    container_client.upload_blob(name=blob_path, data=payload, overwrite=True)
    return len(payload)


@app.timer_trigger(schedule="0 0 8 * * *", arg_name="myTimer", run_on_startup=False,
              use_monitor=False)
def daily_ttc_pull(myTimer: func.TimerRequest) -> None:

    if myTimer.past_due:
        logging.info('The timer is past due!')

    logging.info('Starting daily TTC delay data pull.')

    connection_string = os.environ["AzureWebJobsStorage"]
    blob_service_client = BlobServiceClient.from_connection_string(connection_string)
    container_client = blob_service_client.get_container_client(CONTAINER_NAME)

    pull_date = datetime.date.today().isoformat()
    logging.info(f"Pull date: {pull_date}")

    for mode, package_id in DATASETS.items():
        try:
            logging.info(f"[{mode}] Fetching delay code lookup table...")
            code_resource_id = get_code_lookup_resource_id(package_id)
            code_records = fetch_all_rows(code_resource_id)

            code_blob_path = f"pull_date={pull_date}/{mode}_delay_codes.json"
            size = upload_json_to_blob(container_client, code_blob_path, code_records)
            logging.info(f"[{mode}] Uploaded {len(code_records)} code rows ({size} bytes)")

            logging.info(f"[{mode}] Fetching delay records...")
            data_resource_id = get_active_data_resource_id(package_id)
            records = fetch_all_rows(data_resource_id)

            for row in records:
                row["date_clean"] = normalize_date(row.get("Date"))

            data_blob_path = f"pull_date={pull_date}/{mode}_delays.json"
            size = upload_json_to_blob(container_client, data_blob_path, records)
            logging.info(f"[{mode}] Uploaded {len(records)} delay rows ({size} bytes)")

        except Exception as e:
            # Log and continue -- one dataset failing shouldn't stop the others
            logging.error(f"[{mode}] FAILED: {e}")

    logging.info('Daily TTC delay data pull complete.')