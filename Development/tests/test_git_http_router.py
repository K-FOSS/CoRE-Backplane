"""Exercise redirect boundaries, backend preference, and credential isolation."""

import copy
import http.client
import importlib.util
import threading
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

spec = importlib.util.spec_from_file_location("git_http_router", Path(__file__).parents[1] / "files/git-http-router.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def config():
    return {
        "clusterName": "home1", "probeTimeoutSeconds": 1, "probeCacheSeconds": 5,
        "sites": [{"clusterName": "home1", "url": "https://home.example"},
                  {"clusterName": "dc1", "url": "https://dc1.example"}],
        "repos": [{"repoName": "CoRE-Backplane", "path": "/CoRE/CoRE-Backplane.git",
                   "github": {"owner": "K-FOSS", "weight": 0},
                   "clusters": [{"clusterName": "dc1", "owner": "CoRE", "weight": 100},
                                {"clusterName": "home1", "owner": "CoRE", "weight": 100}]}],
    }


class RouterTests(unittest.TestCase):
    def setUp(self):
        self.router = module.Router(config())
        self.server = module.Server(("127.0.0.1", 0), self.router, 4)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.path = "/CoRE/CoRE-Backplane.git/info/refs?service=git-upload-pack"

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()

    def request(self, path=None, method="GET", headers=None, body=None):
        connection = http.client.HTTPConnection(*self.server.server_address, timeout=2)
        connection.request(method, path or self.path, body=body, headers=headers or {})
        response = connection.getresponse()
        result = response.status, response.getheader("Location")
        response.read()
        connection.close()
        return result

    def test_local_site_preferred_even_when_peer_listed_first(self):
        with patch.object(self.router, "probe", return_value=True) as probe:
            self.assertEqual(self.request(), (307, "https://home.example/CoRE/CoRE-Backplane.git/info/refs?service=git-upload-pack"))
            self.assertEqual(probe.call_args.args[0]["name"], "home1")

    def test_peer_fallback(self):
        with patch.object(self.router, "probe", side_effect=lambda b: b["name"] != "home1"):
            self.assertIn("dc1.example", self.request()[1])

    def test_zero_weight_github_is_last_fallback_and_owner_is_rewritten(self):
        with patch.object(self.router, "probe", side_effect=lambda b: b["name"] == "github"):
            self.assertEqual(self.request(), (307, "https://github.com/K-FOSS/CoRE-Backplane.git/info/refs?service=git-upload-pack"))

    def test_all_backends_down(self):
        with patch.object(self.router, "probe", return_value=False):
            self.assertEqual(self.request(), (503, None))

    def test_only_smart_git_read_paths_are_allowed(self):
        rejected = ["/", "/CoRE/CoRE-Backplane.git", "/api/v1/repos", "/CoRE/Other.git/info/refs?service=git-upload-pack",
                    "/CoRE/CoRE-Backplane.git/info/refs", "/CoRE/CoRE-Backplane.git/info/refs?service=git-receive-pack",
                    "/CoRE/CoRE-Backplane.git/info/refs?service=git-upload-pack&token=unused-test-value",
                    "/CoRE/CoRE-Backplane.git/info/refs?service=git-upload-pack&service=git-upload-pack",
                    "/CoRE/CoRE-Backplane.git/objects/aa/bb", "/CoRE/%43oRE-Backplane.git/info/refs?service=git-upload-pack"]
        with patch.object(self.router, "probe") as probe:
            for path in rejected:
                with self.subTest(path=path):
                    self.assertEqual(self.request(path), (404, None))
            self.assertEqual(self.request("/CoRE/CoRE-Backplane.git/git-receive-pack", "POST"), (404, None))
            probe.assert_not_called()

    def test_upload_pack_redirect_preserves_post_and_suffix(self):
        with patch.object(self.router, "probe", return_value=True):
            self.assertEqual(self.request("/CoRE/CoRE-Backplane.git/git-upload-pack", "POST",
                                          {"Content-Type": "application/x-git-upload-pack-request"}, b"0000"),
                             (307, "https://home.example/CoRE/CoRE-Backplane.git/git-upload-pack"))

    def test_credentials_rejected_before_probe(self):
        with patch.object(self.router, "probe") as probe:
            self.assertEqual(self.request(headers={"Authorization": "unused-test-value"}), (400, None))
            probe.assert_not_called()

    def test_probe_uses_anonymous_smart_advertisement_and_cache(self):
        response = Mock()
        response.status = 200
        response.headers.get_content_type.return_value = "application/x-git-upload-pack-advertisement"
        response.read.return_value = b"001e# service=git-upload-pack\n0000"
        response.__enter__ = Mock(return_value=response)
        response.__exit__ = Mock(return_value=False)
        backend = self.router.repos["/CoRE/CoRE-Backplane.git"][0]
        with patch.object(self.router.opener, "open", return_value=response) as opened:
            self.assertTrue(self.router.probe(backend))
            self.assertTrue(self.router.probe(backend))
            opened.assert_called_once()
            request = opened.call_args.args[0]
            self.assertEqual(request.full_url, "https://home.example/CoRE/CoRE-Backplane.git/info/refs?service=git-upload-pack")
            self.assertEqual(set(k.lower() for k in request.headers), {"user-agent"})

    def test_login_page_does_not_count_as_healthy(self):
        response = Mock()
        response.status = 200
        response.headers.get_content_type.return_value = "text/html"
        response.__enter__ = Mock(return_value=response)
        response.__exit__ = Mock(return_value=False)
        with patch.object(self.router.opener, "open", return_value=response):
            self.assertFalse(self.router.probe(self.router.repos["/CoRE/CoRE-Backplane.git"][0]))

    def test_health_is_independent_of_backend_availability(self):
        with patch.object(self.router, "probe") as probe:
            self.assertEqual(self.request("/healthz"), (200, None))
            probe.assert_not_called()

    def test_metrics_are_internal_and_include_bounded_request_counters(self):
        with patch.object(self.router, "probe", return_value=True):
            self.assertEqual(self.request(), (307, "https://home.example/CoRE/CoRE-Backplane.git/info/refs?service=git-upload-pack"))
        connection = http.client.HTTPConnection(*self.server.server_address, timeout=2)
        connection.request("GET", "/metrics")
        response = connection.getresponse()
        body = response.read().decode()
        connection.close()
        self.assertEqual(response.status, 200)
        self.assertIn('git_http_requests_total{method="GET",operation="info_refs",repository="CoRE-Backplane",status="307"} 1', body)
        self.assertIn("git_http_repositories_configured 1", body)

    def test_higher_peer_weight_wins_but_github_stays_last(self):
        c = config()
        c["clusterName"] = "another-site"
        c["repos"][0]["clusters"][1]["weight"] = 200
        c["repos"][0]["github"]["weight"] = 1000
        router = module.Router(c)
        self.assertEqual([b["name"] for b in router.repos["/CoRE/CoRE-Backplane.git"]], ["home1", "dc1", "github"])

    def test_optional_backends_and_default_alias(self):
        c = config()
        repo = c["repos"][0]
        del repo["path"]
        del repo["clusters"]
        router = module.Router(c)
        self.assertEqual(router.repos["/CoRE-Backplane.git"][0]["url"],
                         "https://github.com/K-FOSS/CoRE-Backplane.git")
        repo["clusters"] = config()["repos"][0]["clusters"]
        del repo["github"]
        router = module.Router(c)
        self.assertEqual([b["name"] for b in router.repos["/CoRE-Backplane.git"]], ["home1", "dc1"])

    def test_unsafe_config_fails_closed(self):
        changes = [lambda c: c["sites"][0].update(url="https://unused-test-value@home.example"),
                   lambda c: c["repos"][0]["github"].update(owner="../other"),
                   lambda c: c["repos"][0].update(path="/../CoRE-Backplane.git"),
                   lambda c: c["repos"][0]["clusters"][0].update(weight=-1),
                   lambda c: c["repos"][0]["clusters"][0].update(clusterName="unknown"),
                   lambda c: c.update(repos=[])]
        for change in changes:
            c = copy.deepcopy(config())
            change(c)
            with self.assertRaises(ValueError):
                module.Router(c)


if __name__ == "__main__":
    unittest.main()
