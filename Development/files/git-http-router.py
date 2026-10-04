"""Allowlisted, anonymous smart Git HTTP redirects; never proxy repository data."""

import json
import re
import http.client
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


NAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,99}\Z")


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def checked_name(value):
    if not isinstance(value, str) or not NAME.fullmatch(value) or value in (".", ".."):
        raise ValueError("Repository names, owners, and cluster names must be plain identifiers")
    return value


def checked_weight(value):
    if type(value) is not int or not 0 <= value <= 10000:
        raise ValueError("Backend weight must be an integer from 0 to 10000")
    return value


class Router:
    def __init__(self, config):
        self.cluster = checked_name(config["clusterName"])
        self.timeout = config["probeTimeoutSeconds"]
        self.ttl = config["probeCacheSeconds"]
        if not 0 < self.timeout <= 5 or not 0 <= self.ttl <= 60:
            raise ValueError("Probe timeout must be in (0, 5], and cache TTL in [0, 60]")
        sites = {}
        for site in config["sites"]:
            name = checked_name(site["clusterName"])
            url = site["url"]
            parsed = urllib.parse.urlsplit(url)
            if (not isinstance(url, str) or any(c.isspace() for c in url)
                    or parsed.scheme != "https" or not parsed.hostname or parsed.username
                    or parsed.password or parsed.query or parsed.fragment
                    or parsed.path not in ("", "/") or name in sites):
                raise ValueError("Each site needs a unique cluster name and a credential-free HTTPS origin")
            sites[name] = url.rstrip("/")
        self.repos = {}
        for repo in config["repos"]:
            name = checked_name(repo["repoName"])
            path = repo.get("path", f"/{name}.git")
            parts = path.split("/")
            if (not path.startswith("/") or len(parts) not in (2, 3)
                    or parts[-1] != f"{name}.git" or path in self.repos):
                raise ValueError("Repository paths must be unique /[owner/]<repoName>.git aliases")
            for part in parts[1:]:
                checked_name(part)
            backends = []
            seen = set()
            for backend in repo.get("clusters", []):
                cluster = checked_name(backend["clusterName"])
                if cluster not in sites or cluster in seen:
                    raise ValueError("Repository cluster backends must name unique configured sites")
                seen.add(cluster)
                owner = checked_name(backend["owner"])
                backends.append({"name": cluster, "tier": 0 if cluster == self.cluster else 1,
                                 "weight": checked_weight(backend["weight"]),
                                 "url": f"{sites[cluster]}/{owner}/{name}.git"})
            if repo.get("github"):
                backend = repo["github"]
                owner = checked_name(backend["owner"])
                backends.append({"name": "github", "tier": 2,
                                 "weight": checked_weight(backend["weight"]),
                                 "url": f"https://github.com/{owner}/{name}.git"})
            if not backends:
                raise ValueError("Each repository must have at least one backend")
            # Stable ordering for equal weights, with local/peer/GitHub tiers fixed.
            self.repos[path] = sorted(backends, key=lambda b: (b["tier"], -b["weight"]))
        if not 1 <= len(self.repos) <= 16:
            raise ValueError("Configure between one and sixteen repositories per HTTPRoute")
        self.cache = {}
        self.locks = {b["url"]: threading.Lock() for bs in self.repos.values() for b in bs}
        # Ignore environment proxy credentials and never follow an upstream redirect.
        self.opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())

    def probe(self, backend):
        url = backend["url"]
        with self.locks[url]:
            now = time.monotonic()
            cached = self.cache.get(url)
            if cached and cached[0] > now:
                return cached[1]
            request = urllib.request.Request(url + "/info/refs?service=git-upload-pack",
                                             headers={"User-Agent": "CoRE-Git-HTTP-Redirect"})
            healthy = False
            try:
                with self.opener.open(request, timeout=self.timeout) as response:
                    healthy = (response.status == 200
                               and response.headers.get_content_type() == "application/x-git-upload-pack-advertisement"
                               and response.read(38).startswith(b"001e# service=git-upload-pack\n0000"))
            except (OSError, urllib.error.URLError, http.client.HTTPException, ValueError):
                pass
            self.cache[url] = (time.monotonic() + self.ttl, healthy)
            return healthy

    def select(self, path):
        return next((b for b in self.repos[path] if self.probe(b)), None)


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "CoRE-Git-HTTP"
    sys_version = ""

    def setup(self):
        self.request.settimeout(10)
        super().setup()

    def log_message(self, fmt, *args):
        # Request URLs, query parameters, and headers may carry credentials.
        pass

    def reply(self, status, location=None):
        self.send_response(status)
        self.send_header("Content-Length", "0")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Connection", "close")
        if location:
            self.send_header("Location", location)
        self.end_headers()
        self.close_connection = True

    def do_GET(self):
        self.redirect_git()

    def do_POST(self):
        self.redirect_git()

    def do_HEAD(self):
        self.reply(405)

    def redirect_git(self):
        if self.command == "GET" and self.path == "/healthz":
            return self.reply(200)
        if len(self.path) > 2048:
            return self.reply(414)
        try:
            parsed = urllib.parse.urlsplit(self.path)
            query = urllib.parse.parse_qs(parsed.query, keep_blank_values=True)
        except ValueError:
            return self.reply(400)
        if parsed.scheme or parsed.netloc or parsed.fragment:
            return self.reply(404)
        if self.command == "GET" and parsed.path.endswith("/info/refs"):
            path = parsed.path[:-len("/info/refs")]
            operation = "info/refs"
        else:
            path, _, operation = parsed.path.rpartition("/")
        if path not in self.server.router.repos:
            return self.reply(404)
        # Match only smart clone/fetch discovery and upload-pack RPC.
        if self.command == "GET":
            valid = parsed.path.endswith("/info/refs") and query == {"service": ["git-upload-pack"]}
        else:
            valid = (operation == "git-upload-pack" and not parsed.query
                     and self.headers.get("Content-Type", "").split(";", 1)[0] == "application/x-git-upload-pack-request")
        if not valid:
            return self.reply(404)
        # This alias has no credential scope; use a forge's own URL for authenticated access.
        if self.headers.get("Authorization") or self.headers.get("Proxy-Authorization"):
            return self.reply(400)
        backend = self.server.router.select(path)
        if backend is None:
            return self.reply(503)
        suffix = parsed.path[len(path):]
        location = backend["url"] + suffix + ("?" + parsed.query if parsed.query else "")
        self.reply(307, location)


class Server(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address, router, max_connections):
        if type(max_connections) is not int or not 1 <= max_connections <= 128:
            raise ValueError("maxConnections must be an integer from 1 to 128")
        self.router = router
        self.slots = threading.BoundedSemaphore(max_connections)
        super().__init__(address, Handler)

    def process_request(self, request, client_address):
        if not self.slots.acquire(blocking=False):
            self.shutdown_request(request)
            return
        try:
            super().process_request(request, client_address)
        except Exception:
            self.slots.release()
            raise

    def process_request_thread(self, request, client_address):
        try:
            super().process_request_thread(request, client_address)
        finally:
            self.slots.release()


if __name__ == "__main__":
    with open(sys.argv[1], encoding="utf-8") as config_file:
        config = json.load(config_file)
    Server(("0.0.0.0", 8080), Router(config), config["maxConnections"]).serve_forever()
