"""
Promote content through the Power BI deployment pipeline (DEV=0 -> TEST=1 -> PROD=2).
Deployment rules in the pipeline switch the 'Environment' parameter per stage.

Usage: python deploy_pipeline.py --source-stage 0 --note "CI <sha>"
"""
import argparse
import os
import sys

from pbi_client import API, PowerBI

p = argparse.ArgumentParser()
p.add_argument("--source-stage", type=int, required=True, choices=[0, 1])
p.add_argument("--note", default="automated deployment")
a = p.parse_args()

pbi = PowerBI()
pipeline = os.environ["PIPELINE_ID"]
body = {
    "sourceStageOrder": a.source_stage,
    "options": {
        "allowCreateArtifact": True,
        "allowOverwriteArtifact": True,
        "allowOverwriteTargetArtifactLabel": False,   # never downgrade a sensitivity label
        "allowPurgeData": False,
    },
    "note": a.note,
}
resp = pbi.post(f"/pipelines/{pipeline}/deployAll", body)
op = pbi.wait_operation(f"{API}/pipelines/{pipeline}/operations/{resp.json()['id']}")
print(f"deployment {op['status']}: stage {a.source_stage} -> {a.source_stage + 1}")
sys.exit(0 if op["status"] == "Succeeded" else 1)
