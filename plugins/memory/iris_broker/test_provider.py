import unittest
import sys
import urllib.error
import json
import os
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import provider


class ProviderWebResearchTests(unittest.TestCase):
    def test_startup_check_requires_explicit_staging_counts(self):
        valid_status = {
            "ok": True,
            "loopbackOnly": True,
            "authenticated": True,
            "stagingItems": 3,
            "pendingStagingItems": 1,
            "decidedStagingItems": 2,
        }
        with patch.object(provider, "_broker_get", return_value=valid_status), patch.object(
            provider, "inference_policy", return_value={}
        ):
            self.assertEqual(provider.startup_check(), valid_status)

        missing_counts = {
            "ok": True,
            "loopbackOnly": True,
            "authenticated": True,
            "stagingItems": 1,
        }
        with patch.object(provider, "_broker_get", return_value=missing_counts):
            with self.assertRaisesRegex(
                provider.IrisBrokerUnavailable,
                "explicit staging counts",
            ):
                provider.startup_check()

    def test_startup_check_rejects_inconsistent_staging_counts(self):
        bad_status = {
            "ok": True,
            "loopbackOnly": True,
            "authenticated": True,
            "stagingItems": 3,
            "pendingStagingItems": 1,
            "decidedStagingItems": 1,
        }
        with patch.object(provider, "_broker_get", return_value=bad_status):
            with self.assertRaisesRegex(
                provider.IrisBrokerUnavailable,
                "staging counts are inconsistent",
            ):
                provider.startup_check()

    def test_startup_check_rejects_unauthenticated_status(self):
        status = {
            "ok": True,
            "loopbackOnly": True,
            "authenticated": False,
            "stagingItems": 0,
            "pendingStagingItems": 0,
            "decidedStagingItems": 0,
        }
        with patch.object(provider, "_broker_get", return_value=status):
            with self.assertRaisesRegex(
                provider.IrisBrokerUnavailable,
                "authenticated=true",
            ):
                provider.startup_check()

    def test_broker_configuration_is_required_and_loopback_only(self):
        with patch.object(provider, "_CONFIGURED_BROKER_URL", ""), patch.object(
            provider, "_CONFIGURED_BROKER_TOKEN", ""
        ):
            with self.assertRaisesRegex(provider.IrisBrokerUnavailable, "endpoint was not provided"):
                provider.broker_url()
            with self.assertRaisesRegex(provider.IrisBrokerUnavailable, "credential was not provided"):
                provider.broker_token()

        token = "ab" * 32
        with patch.object(
            provider, "_CONFIGURED_BROKER_URL", "http://example.com:43123"
        ), patch.object(provider, "_CONFIGURED_BROKER_TOKEN", token):
            with self.assertRaisesRegex(provider.IrisBrokerUnavailable, "loopback only"):
                provider.broker_url()

    def test_broker_requests_send_process_credential_without_exposing_it(self):
        token = "ab" * 32

        class FakeResponse:
            def __enter__(self):
                return self

            def __exit__(self, *_args):
                return False

            def read(self):
                return json.dumps({"ok": True}).encode("utf-8")

        with patch.object(
            provider, "_CONFIGURED_BROKER_URL", "http://127.0.0.1:43123"
        ), patch.object(provider, "_CONFIGURED_BROKER_TOKEN", token), patch(
            "urllib.request.urlopen", return_value=FakeResponse()
        ) as open_url:
            self.assertEqual(provider._broker_get(provider.STATUS_ENDPOINT), {"ok": True})

        request = open_url.call_args.args[0]
        self.assertEqual(request.full_url, "http://127.0.0.1:43123/memory/status")
        self.assertEqual(request.get_header("Authorization"), f"Bearer {token}")
        self.assertNotIn(token, repr(request))

    def test_broker_access_is_removed_from_the_child_environment(self):
        token = "cd" * 32
        with patch.dict(
            "os.environ",
            {
                "IRIS_HERMES_BROKER_URL": "http://127.0.0.1:43123",
                "IRIS_HERMES_BROKER_TOKEN": token,
            },
        ):
            endpoint, captured_token = provider._consume_broker_access_from_environment()
            self.assertNotIn("IRIS_HERMES_BROKER_URL", os.environ)
            self.assertNotIn("IRIS_HERMES_BROKER_TOKEN", os.environ)

        self.assertEqual(endpoint, "http://127.0.0.1:43123")
        self.assertEqual(captured_token, token)

    def test_release_queries_route_to_authoritative_repo(self):
        self.assertEqual(provider._release_repo_for_query("latest Ollama release"), "ollama/ollama")
        self.assertEqual(provider._release_repo_for_query("latest news"), "")

    def test_unrecognized_safe_research_requires_agentic_browser(self):
        with self.assertRaisesRegex(
            provider.IrisBrokerUnavailable,
            "Start an Agentic Session",
        ):
            provider.iris_web_research("latest general technology news")

    def test_authoritative_lookup_reports_network_failure_truthfully(self):
        with patch(
            "urllib.request.urlopen",
            side_effect=urllib.error.URLError("offline"),
        ):
            with self.assertRaisesRegex(
                provider.IrisBrokerUnavailable,
                "Primary-source release lookup unavailable",
            ):
                provider.iris_web_research("latest Ollama release")


if __name__ == "__main__":
    unittest.main()
