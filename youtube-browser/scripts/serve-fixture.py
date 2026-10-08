"""Serve only the synthetic test video, including the byte ranges WebKit uses."""
import re
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

media = (Path(__file__).resolve().parents[1] / ".build/BrowserFixture.mp4").read_bytes()


class FixtureVideo(BaseHTTPRequestHandler):
    def do_HEAD(self):
        self.respond(include_body=False)

    def do_GET(self):
        self.respond(include_body=True)

    def respond(self, include_body):
        if self.path != "/BrowserFixture.mp4":
            self.send_error(404)
            return
        start, end, status = 0, len(media) - 1, 200
        if requested := self.headers.get("Range"):
            match = re.fullmatch(r"bytes=(\d*)-(\d*)", requested)
            if not match or not any(match.groups()):
                self.send_error(416)
                return
            first, last = match.groups()
            if first:
                start = int(first)
                end = min(int(last), end) if last else end
            else:
                start = max(0, len(media) - int(last))
            if start > end or start >= len(media):
                self.send_response(416)
                self.send_header("Content-Range", f"bytes */{len(media)}")
                self.end_headers()
                return
            status = 206
        self.send_response(status)
        self.send_header("Content-Type", "video/mp4")
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(end - start + 1))
        self.send_header("Cache-Control", "no-store")
        if status == 206:
            self.send_header("Content-Range", f"bytes {start}-{end}/{len(media)}")
        self.end_headers()
        if include_body:
            self.wfile.write(media[start:end + 1])


print("Synthetic browser video available at http://127.0.0.1:8766/BrowserFixture.mp4", flush=True)
ThreadingHTTPServer(("127.0.0.1", 8766), FixtureVideo).serve_forever()
