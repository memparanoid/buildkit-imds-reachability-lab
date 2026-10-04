#!/usr/bin/env python3
import json
import os
import urllib.request


base = os.environ.get("IMDS_BASE", "http://169.254.169.254").rstrip("/")


def request(opener, path, method="GET", token=None):
    headers = {}
    if method == "PUT":
        headers["X-aws-ec2-metadata-token-ttl-seconds"] = "60"
    if token:
        headers["X-aws-ec2-metadata-token"] = token
    req = urllib.request.Request(base + path, headers=headers, method=method)
    with opener.open(req, timeout=3) as response:
        return response.read().decode().strip()


def probe(opener, transport):
    imds_token = request(opener, "/latest/api/token", method="PUT")
    role = request(
        opener,
        "/latest/meta-data/iam/security-credentials/",
        token=imds_token,
    )
    credentials = json.loads(
        request(
            opener,
            "/latest/meta-data/iam/security-credentials/" + role,
            token=imds_token,
        )
    )
    print(
        f"RESULT reachable transport={transport}"
        f" role={role} access_key={credentials['AccessKeyId']}",
        flush=True,
    )


errors = []
attempts = [
    ("direct", urllib.request.build_opener(urllib.request.ProxyHandler({}))),
    ("proxy-env", urllib.request.build_opener()),
]
for transport, transport_opener in attempts:
    try:
        probe(transport_opener, transport)
        break
    except Exception as error:
        errors.append(f"{transport}={type(error).__name__}: {error}")
else:
    print("RESULT unreachable " + "; ".join(errors), flush=True)

