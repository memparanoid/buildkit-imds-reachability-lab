#!/usr/bin/env python3
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


TOKEN = "lab-imdsv2-token"
ROLE = "lab-role"


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        print("REQUEST", self.client_address[0], fmt % args, flush=True)

    def send_text(self, status, body, content_type="text/plain"):
        encoded = body.encode()
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def do_PUT(self):
        if self.path != "/latest/api/token":
            self.send_text(404, "not found\n")
            return
        if not self.headers.get("X-aws-ec2-metadata-token-ttl-seconds"):
            self.send_text(400, "missing token TTL\n")
            return
        self.send_text(200, TOKEN)

    def do_GET(self):
        if self.headers.get("X-aws-ec2-metadata-token") != TOKEN:
            self.send_text(401, "valid IMDSv2 token required\n")
            return
        if self.path == "/latest/meta-data/iam/security-credentials/":
            self.send_text(200, ROLE + "\n")
            return
        if self.path == "/latest/meta-data/iam/security-credentials/" + ROLE:
            document = {
                "Code": "Success",
                "AccessKeyId": "LAB_CANARY_NOT_A_SECRET",
                "SecretAccessKey": "LAB_FAKE_SECRET",
                "Token": "LAB_FAKE_SESSION_TOKEN",
                "Expiration": "2099-01-01T00:00:00Z",
            }
            self.send_text(200, json.dumps(document) + "\n", "application/json")
            return
        self.send_text(404, "not found\n")


server = ThreadingHTTPServer(("169.254.169.254", 80), Handler)
print("fake IMDSv2 listening on http://169.254.169.254", flush=True)
server.serve_forever()

