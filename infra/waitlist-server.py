#!/usr/bin/env python3
"""Tiny waitlist endpoint. Listens on 127.0.0.1:8091 behind Caddy.

POST /api/waitlist with body: email=foo@bar.com&tier=Pro
Appends one line per submission to /var/lib/opspocket/waitlist.txt.
"""
import http.server
import socketserver
import urllib.parse
import re
import datetime
import os
import pathlib

LOG_FILE = pathlib.Path("/var/lib/opspocket/waitlist.txt")
EMAIL_RE = re.compile(r"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$")

class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path != "/api/waitlist":
            self.send_response(404); self.end_headers(); return
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length).decode("utf-8", errors="replace")
        params = urllib.parse.parse_qs(body)
        email = (params.get("email", [""])[0] or "").strip().lower()
        tier = (params.get("tier", [""])[0] or "").strip()[:40]
        if not EMAIL_RE.match(email):
            self.send_response(400)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"ok":false,"error":"invalid email"}')
            return
        ts = datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
        line = f"{ts}\t{email}\t{tier}\n"
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(line)
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"ok":true}')

    def log_message(self, fmt, *args):
        # Silence default per-request stderr logging.
        pass

if __name__ == "__main__":
    with socketserver.ThreadingTCPServer(("127.0.0.1", 8091), Handler) as srv:
        srv.serve_forever()
