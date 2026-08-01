#!/usr/bin/env python3
"""Serve the local fixtures, falling back to the real SlashDiablo file server.

Anything present under testenv/files is served from disk; everything else is
proxied to slashdiablo.net. That means a mod under development (d2gl) can be
served locally while the 1.13c and SlashDiablo patch manifests still come from
production, so a full patch run works end to end.

    python3 testenv/serve.py [--port 8666] [--no-proxy]
"""

import argparse
import http.server
import pathlib
import shutil
import urllib.error
import urllib.request

UPSTREAM = "https://slashdiablo.net/files"
ROOT = pathlib.Path(__file__).resolve().parent / "files"


class Handler(http.server.SimpleHTTPRequestHandler):
    proxy = True

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def do_GET(self):
        if self.proxy and not self._local_path().exists():
            self._proxy()
            return
        super().do_GET()

    def do_HEAD(self):
        if self.proxy and not self._local_path().exists():
            self._proxy(body=False)
            return
        super().do_HEAD()

    def _local_path(self):
        return pathlib.Path(self.translate_path(self.path))

    def _proxy(self, body=True):
        # slashdiablo.net answers 403 to the default Python-urllib agent.
        request = urllib.request.Request(
            UPSTREAM + self.path,
            headers={"User-Agent": "slashdiablo-launcher-testenv"},
        )
        try:
            with urllib.request.urlopen(request, timeout=30) as upstream:
                self.send_response(upstream.status)
                for header in ("Content-Type", "Content-Length", "Last-Modified"):
                    value = upstream.headers.get(header)
                    if value:
                        self.send_header(header, value)
                self.end_headers()
                if body:
                    shutil.copyfileobj(upstream, self.wfile)
        except urllib.error.HTTPError as err:
            self.send_error(err.code, f"upstream: {err.reason}")
        except Exception as err:  # noqa: BLE001 - report anything upstream does
            self.send_error(502, f"proxy error: {err}")

    def log_message(self, fmt, *args):
        source = "local" if self._local_path().exists() else "proxy"
        print(f"[{source}] {fmt % args}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8666)
    parser.add_argument(
        "--no-proxy",
        action="store_true",
        help="404 instead of falling back to slashdiablo.net",
    )
    args = parser.parse_args()

    if not ROOT.is_dir():
        raise SystemExit(f"no fixtures at {ROOT}; run testenv/make_fixtures.py first")

    Handler.proxy = not args.no_proxy
    mode = "local only" if args.no_proxy else f"local, falling back to {UPSTREAM}"
    print(f"serving {ROOT} on http://localhost:{args.port} ({mode})")

    server = http.server.ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
