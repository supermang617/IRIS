import unittest
import sys
import urllib.error
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import provider


class ProviderWebResearchTests(unittest.TestCase):
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
