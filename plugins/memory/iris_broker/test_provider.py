import unittest
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import provider


class ProviderWebResearchTests(unittest.TestCase):
    def test_parse_bing_html_extracts_results(self):
        html = '''
        <li class="b_algo"><h2><a href="https://example.test/a">Example &amp; Result</a></h2>
        <p>Useful snippet &amp; evidence.</p></li>
        '''

        results = provider._parse_bing_html(html, 1)

        self.assertEqual(results, [{
            "title": "Example & Result",
            "url": "https://example.test/a",
            "snippet": "Useful snippet & evidence.",
        }])

    def test_clean_bing_url_decodes_target_url(self):
        url = "https://www.bing.com/ck/a?!&&u=a1aHR0cHM6Ly9leGFtcGxlLnRlc3QvcGF0aA&ntb=1"

        self.assertEqual(provider._clean_bing_url(url), "https://example.test/path")

    def test_release_queries_route_to_authoritative_repo(self):
        self.assertEqual(provider._release_repo_for_query("latest Ollama release"), "ollama/ollama")
        self.assertEqual(provider._release_repo_for_query("latest news"), "")


if __name__ == "__main__":
    unittest.main()
