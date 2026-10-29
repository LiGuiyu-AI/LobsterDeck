#!/usr/bin/env python3
"""Push a home layout to LobsterDeck.

Usage:
  LOBSTERDECK_URL=https://deck.example.com LOBSTERDECK_TOKEN=... python3 update_home.py layout.json
"""
import os
import sys
import urllib.request

url = os.environ["LOBSTERDECK_URL"].rstrip("/") + "/api/v1/home/layout"
token = os.environ["LOBSTERDECK_TOKEN"]
body = open(sys.argv[1], "rb").read()
req = urllib.request.Request(url, data=body, method="PUT", headers={
    "Authorization": "Bearer " + token,
    "Content-Type": "application/json",
})
with urllib.request.urlopen(req, timeout=20) as r:
    print(r.status, r.read().decode())
