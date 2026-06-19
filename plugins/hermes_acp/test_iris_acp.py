from __future__ import annotations

import io
import json
import sys
import unittest
from contextlib import redirect_stdout
from pathlib import Path


sys.path.insert(0, str(Path(__file__).resolve().parent))
import iris_acp


class IrisAcpBridgeTests(unittest.TestCase):
    def test_audit_reports_local_ollama_generation_limits(self):
        buffer = io.StringIO()
        with redirect_stdout(buffer):
            self.assertEqual(iris_acp.audit_tools(), 0)

        audit = json.loads(buffer.getvalue())
        self.assertEqual(audit["maxTokens"], 4096)
        self.assertEqual(audit["requestOverrides"]["temperature"], 0)
        self.assertEqual(audit["requestOverrides"]["toolChoice"], "prompt_scoped")
        self.assertTrue(audit["promptScopedTools"])
        self.assertFalse(audit["requestOverrides"]["extraBody"]["think"])
        self.assertEqual(
            audit["requestOverrides"]["extraBody"]["options"]["numPredict"],
            4096,
        )

    def test_prompt_scoped_tools_omit_tools_for_plain_answers(self):
        self.assertEqual(
            iris_acp.tool_names_for_prompt(
                [{"type": "text", "text": "Reply with exactly IRIS_ROUNDTRIP_OK."}]
            ),
            set(),
        )

    def test_prompt_scoped_tools_select_explicit_groups(self):
        self.assertEqual(
            iris_acp.tool_names_for_prompt(
                [{"type": "text", "text": "Call iris_query_memory with query age."}]
            ),
            {"iris_query_memory"},
        )
        self.assertIn(
            "browser_open",
            iris_acp.tool_names_for_prompt(
                [{"type": "text", "text": "Call browser_open with https://example.com."}]
            ),
        )
        self.assertEqual(
            iris_acp.tool_names_for_prompt(
                [{"type": "text", "text": "Call terminal with native PowerShell."}]
            ),
            {"terminal", "process"},
        )

    def test_authorized_research_prompt_selects_browser_without_interactive_tools(self):
        allowed = iris_acp.tool_names_for_prompt(
            [{
                "type": "text",
                "text": (
                    "IRIS_RESEARCH_AUTHORIZED_BY_USER: true\n"
                    "Use Brave Search for the latest Ollama release."
                ),
            }]
        )

        self.assertIn("browser_open", allowed)
        self.assertIn("browser_snapshot", allowed)
        self.assertNotIn("browser_fill", allowed)
        self.assertNotIn("browser_download", allowed)

    def test_natural_memory_prompt_selects_memory_query(self):
        self.assertEqual(
            iris_acp.tool_names_for_prompt(
                [{"type": "text", "text": "What do you remember about me?"}]
            ),
            {"iris_query_memory"},
        )


if __name__ == "__main__":
    unittest.main()
