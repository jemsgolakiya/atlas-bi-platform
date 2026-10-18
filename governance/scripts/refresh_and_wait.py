"""Trigger an enhanced refresh of a semantic model and block until it finishes (used in CI before reconciliation)."""
import os
import sys
import time

from pbi_client import PowerBI

pbi = PowerBI()
ws, ds = os.environ["WORKSPACE_ID"], os.environ["DATASET_ID"]
pbi.post(f"/groups/{ws}/datasets/{ds}/refreshes", {"type": "full", "commitMode": "transactional", "retryCount": 1})

for _ in range(180):
    time.sleep(10)
    last = pbi.get(f"/groups/{ws}/datasets/{ds}/refreshes", **{"$top": 1})["value"][0]
    if last["status"] in ("Completed", "Failed", "Disabled"):
        print("refresh", last["status"])
        sys.exit(0 if last["status"] == "Completed" else 1)
sys.exit("refresh timed out")
