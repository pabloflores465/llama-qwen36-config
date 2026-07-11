#!/usr/bin/env python3
"""Minimal llama-server process/API used only by lifecycle integration tests."""
import json
import signal
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

def argument(name, default):
    try: return sys.argv[sys.argv.index(name) + 1]
    except (ValueError, IndexError): return default

host = argument("--host", "127.0.0.1")
port = int(argument("--port", "18081"))
alias = argument("--alias", "fake")

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health": body = {"status": "ok"}
        elif self.path == "/v1/models": body = {"data": [{"id": alias}]}
        else: self.send_error(404); return
        encoded = json.dumps(body).encode()
        self.send_response(200); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded))); self.end_headers(); self.wfile.write(encoded)
    def log_message(self, _format, *_args): pass

server = HTTPServer((host, port), Handler)
signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
server.serve_forever()
