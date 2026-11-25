"""Read-only, allowlisted, loopback progress server. No project browsing."""

from __future__ import annotations

import argparse
import json
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1] / "progress"
STATES = {"pending", "active", "verified", "failed", "blocked"}
ASSETS = {
    "/": ("index.html", "text/html; charset=utf-8"),
    "/style.css": ("style.css", "text/css; charset=utf-8"),
    "/progress.js": ("progress.js", "text/javascript; charset=utf-8"),
    "/state.json": ("state.json", "application/json; charset=utf-8"),
}


def bounded_text(value: object, maximum: int = 1500) -> bool:
    if not isinstance(value, str) or not 0 < len(value) <= maximum or "\x00" in value:
        return False
    try:
        value.encode("utf-8")
    except UnicodeError:
        return False
    return True


def unique_object(pairs: list[tuple[str, object]]) -> dict:
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate progress field")
        result[key] = value
    return result


def guard_depth(data: bytes) -> None:
    depth = 0
    quoted = escaped = False
    for byte in data:
        if quoted:
            if escaped:
                escaped = False
            elif byte == 92:
                escaped = True
            elif byte == 34:
                quoted = False
        elif byte == 34:
            quoted = True
        elif byte in (91, 123):
            depth += 1
            if depth > 6:
                raise ValueError("Progress nesting limit")
        elif byte in (93, 125):
            depth -= 1
            if depth < 0:
                raise ValueError("Progress nesting mismatch")
    if depth or quoted:
        raise ValueError("Incomplete progress record")


def validate_record(data: bytes) -> dict:
    if not isinstance(data, bytes) or not 1 <= len(data) <= 65536:
        raise ValueError("Progress record too large")
    guard_depth(data)
    record = json.loads(data.decode("utf-8"), object_pairs_hook=unique_object)
    if not isinstance(record, dict) or set(record) != {
        "updated_at", "activity", "batch", "milestones", "blockers",
    }:
        raise ValueError("Unexpected record fields")
    if not bounded_text(record["activity"]) or not bounded_text(record["updated_at"], 64):
        raise ValueError("Invalid record text")
    stamp = datetime.fromisoformat(record["updated_at"].replace("Z", "+00:00"))
    if stamp.tzinfo is None:
        raise ValueError("Timestamp must contain timezone")
    batch = record["batch"]
    if not isinstance(batch, dict) or set(batch) != {"title", "tasks"} or not bounded_text(batch["title"]):
        raise ValueError("Invalid batch")
    ids = set()
    for collection in (batch["tasks"], record["milestones"]):
        if (not isinstance(collection, list) or len(collection) > 50
                or (collection is batch["tasks"] and not collection)):
            raise ValueError("Invalid task collection")
        for task in collection:
            if not isinstance(task, dict) or set(task) != {"id", "title", "state", "evidence"}:
                raise ValueError("Unexpected task fields")
            if not all(bounded_text(task[key]) for key in ("id", "title", "evidence")):
                raise ValueError("Invalid task text")
            if not bounded_text(task["state"], 16) or task["state"] not in STATES or task["id"] in ids:
                raise ValueError("Invalid or duplicate task")
            ids.add(task["id"])
    if not isinstance(record["blockers"], list) or len(record["blockers"]) > 30:
        raise ValueError("Invalid blockers")
    if not all(bounded_text(text) for text in record["blockers"]):
        raise ValueError("Invalid blocker text")
    return record


class Handler(BaseHTTPRequestHandler):
    def setup(self) -> None:
        super().setup()
        self.connection.settimeout(3)

    def log_message(self, *_args: object) -> None:
        pass

    def do_GET(self) -> None:
        asset = ASSETS.get(self.path)
        if asset is None:
            self.send_error(404)
            return
        try:
            data = (ROOT / asset[0]).read_bytes()
            if self.path == "/state.json":
                validate_record(data)
        except (OSError, ValueError, TypeError, KeyError):
            self.send_error(503, "Progress unavailable")
            return
        self.connection.settimeout(3)
        self.send_response(200)
        self.send_header("Content-Type", asset[1])
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Content-Security-Policy", "default-src 'self'; frame-ancestors 'none'; base-uri 'none'; object-src 'none'")
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self) -> None:
        self.send_error(405)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8799)
    args = parser.parse_args()
    if not 1 <= args.port <= 65535:
        parser.error("Invalid port")
    validate_record((ROOT / "state.json").read_bytes())
    with ThreadingHTTPServer(("127.0.0.1", args.port), Handler) as server:
        print(f"Progress: http://127.0.0.1:{args.port}/", flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass


if __name__ == "__main__":
    main()
