"""Thin Power BI REST client shared by the governance scripts (service principal auth)."""
from __future__ import annotations

import os
import time

import msal
import requests

API = "https://api.powerbi.com/v1.0/myorg"


class PowerBI:
    def __init__(self) -> None:
        app = msal.ConfidentialClientApplication(
            os.environ["CLIENT_ID"],
            authority=f"https://login.microsoftonline.com/{os.environ['TENANT_ID']}",
            client_credential=os.environ["CLIENT_SECRET"],
        )
        tok = app.acquire_token_for_client(scopes=["https://analysis.windows.net/powerbi/api/.default"])
        self.s = requests.Session()
        self.s.headers["Authorization"] = f"Bearer {tok['access_token']}"

    def get(self, path: str, **params) -> dict:
        r = self.s.get(f"{API}{path}", params=params, timeout=120)
        r.raise_for_status()
        return r.json()

    def post(self, path: str, body: dict | None = None) -> requests.Response:
        r = self.s.post(f"{API}{path}", json=body or {}, timeout=120)
        r.raise_for_status()
        return r

    def wait_operation(self, url: str, poll: int = 10, timeout: int = 1800) -> dict:
        start = time.time()
        while time.time() - start < timeout:
            r = self.s.get(url, timeout=60).json()
            if r.get("status") in ("Succeeded", "Failed"):
                return r
            time.sleep(poll)
        raise TimeoutError(url)
