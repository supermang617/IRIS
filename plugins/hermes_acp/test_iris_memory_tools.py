from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path


sys.path.insert(0, str(Path(__file__).resolve().parent))
import iris_memory_tools


class IrisMemoryToolTests(unittest.TestCase):
    def test_query_marks_memory_as_non_instructional_provenance(self):
        original = iris_memory_tools.iris_broker.iris_query_memory
        try:
            iris_memory_tools.iris_broker.iris_query_memory = lambda query, limit: {
                "ok": True,
                "readOnly": True,
                "results": [
                    {
                        "id": 7,
                        "text": "Alejandro is 45",
                        "score": 1.0,
                        "source": "iris_active_memory",
                        "provenance": {
                            "authority": "user_approved",
                            "memoryId": 7,
                        },
                    }
                ],
            }
            result = json.loads(
                iris_memory_tools.query_memory({"query": "age", "limit": 5})
            )
        finally:
            iris_memory_tools.iris_broker.iris_query_memory = original

        self.assertEqual(result["authority"], "iris_user_approved_memory")
        self.assertFalse(result["instructionAuthority"])
        self.assertEqual(result["results"][0]["provenance"]["memoryId"], 7)
        self.assertIn("IRIS_PROVENANCE:", result["content"])

    def test_proposal_remains_staged(self):
        original = iris_memory_tools.iris_broker.iris_propose_memory
        try:
            iris_memory_tools.iris_broker.iris_propose_memory = (
                lambda text, source, evidence: {
                    "ok": True,
                    "verdict": "staged",
                    "staging_id": 3,
                    "reason": "proposal written to staging only",
                }
            )
            result = json.loads(
                iris_memory_tools.propose_memory(
                    {
                        "text": "Alejandro is 45",
                        "source": "user_statement",
                        "evidence": "User stated this directly.",
                    }
                )
            )
        finally:
            iris_memory_tools.iris_broker.iris_propose_memory = original

        self.assertFalse(result["durableMemoryPromoted"])
        self.assertTrue(result["requiresUserDecision"])
        self.assertIn("IRIS_PROVENANCE:", result["content"])

    def test_conflicting_memory_results_preserve_both_sources(self):
        original = iris_memory_tools.iris_broker.iris_query_memory
        try:
            iris_memory_tools.iris_broker.iris_query_memory = lambda query, limit: {
                "ok": True,
                "readOnly": True,
                "results": [
                    {
                        "id": 7,
                        "text": "Alejandro is 45",
                        "provenance": {
                            "authority": "user_approved",
                            "source": "iris_active_memory",
                            "memoryId": 7,
                        },
                    },
                    {
                        "id": 8,
                        "text": "Alejandro is 46",
                        "provenance": {
                            "authority": "user_approved",
                            "source": "iris_active_memory",
                            "memoryId": 8,
                        },
                    },
                ],
            }
            result = json.loads(
                iris_memory_tools.query_memory({"query": "age", "limit": 5})
            )
        finally:
            iris_memory_tools.iris_broker.iris_query_memory = original

        self.assertEqual(len(result["results"]), 2)
        self.assertIn('"memoryId":7', result["content"])
        self.assertIn('"memoryId":8', result["content"])

    def test_broker_failure_is_not_hidden(self):
        original = iris_memory_tools.iris_broker.iris_query_memory
        try:
            iris_memory_tools.iris_broker.iris_query_memory = lambda query, limit: (
                (_ for _ in ()).throw(
                    iris_memory_tools.iris_broker.IrisBrokerUnavailable("offline")
                )
            )
            with self.assertRaisesRegex(
                iris_memory_tools.iris_broker.IrisBrokerUnavailable, "offline"
            ):
                iris_memory_tools.query_memory({"query": "age"})
        finally:
            iris_memory_tools.iris_broker.iris_query_memory = original


if __name__ == "__main__":
    unittest.main()
