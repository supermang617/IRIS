from __future__ import annotations

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


sys.path.insert(0, str(Path(__file__).resolve().parent))
import iris_action_tools


class IrisActionToolPolicyTests(unittest.TestCase):
    def test_workspace_relative_read_needs_no_extra_approval(self):
        workspace = Path(tempfile.gettempdir()).resolve()
        self.assertIsNone(
            iris_action_tools._path_risk("project/readme.md", workspace)
        )

    def test_selected_agentic_workspace_overrides_stale_upstream_task_cwd(self):
        selected = Path(tempfile.gettempdir(), "iris-selected").resolve()
        stale = Path(tempfile.gettempdir(), "stale-upstream-task").resolve()
        from tools import terminal_tool

        with (
            patch.dict(
                os.environ,
                {"IRIS_AGENTIC_WORKSPACE": str(selected)},
            ),
            patch.dict(
                terminal_tool._task_env_overrides,
                {"task": {"cwd": str(stale)}},
            ),
        ):
            self.assertEqual(
                iris_action_tools._workspace_for_task("task"),
                selected,
            )

    def test_outside_workspace_read_requires_scope_confirmation(self):
        workspace = Path(tempfile.gettempdir(), "iris-workspace").resolve()
        outside = Path(tempfile.gettempdir(), "other", "notes.txt").resolve()
        self.assertEqual(
            iris_action_tools._path_risk(str(outside), workspace),
            "scope expansion",
        )

    def test_sensitive_file_requires_confirmation_inside_workspace(self):
        workspace = Path(tempfile.gettempdir(), "iris-workspace").resolve()
        self.assertEqual(
            iris_action_tools._path_risk(str(workspace / ".env"), workspace),
            "sensitive files",
        )

    def test_action_tool_inventory_is_exact(self):
        self.assertEqual(
            iris_action_tools.IRIS_ACTION_TOOLS,
            (
                "read_file",
                "write_file",
                "patch",
                "search_files",
                "terminal",
                "process",
            ),
        )

    def test_timeout_accepts_integral_numeric_values(self):
        self.assertEqual(iris_action_tools._coerce_timeout("180.0", default=60), 180)
        with self.assertRaises(ValueError):
            iris_action_tools._coerce_timeout("1.5", default=60)

    def test_user_denial_is_a_completed_safety_outcome(self):
        result = json.loads(
            iris_action_tools._approval_denied_result(
                "git reset --hard HEAD",
                {"message": "BLOCKED: User denied this command."},
            )
        )
        self.assertEqual(result["status"], "denied")
        self.assertEqual(result["exit_code"], 0)
        self.assertIsNone(result["error"])

    def test_process_output_is_bounded_and_preserves_the_tail(self):
        output = "a" * 25 + "b" * iris_action_tools.MAX_PROCESS_OUTPUT_CHARS
        truncated = iris_action_tools._trim_output(output)

        self.assertTrue(truncated.startswith("[earlier output truncated]\n"))
        self.assertTrue(truncated.endswith("b" * 100))
        self.assertLessEqual(
            len(truncated),
            iris_action_tools.MAX_PROCESS_OUTPUT_CHARS
            + len("[earlier output truncated]\n"),
        )

    def test_relative_file_target_is_normalized_to_workspace(self):
        workspace = Path(tempfile.gettempdir(), "iris-workspace").resolve()
        args = iris_action_tools._normalize_path_args(
            "read_file",
            {"path": "notes.txt"},
            workspace,
        )
        self.assertEqual(Path(args["path"]), workspace / "notes.txt")
        if os.name == "nt":
            self.assertNotIn("\\", args["path"])

    @unittest.skipUnless(os.name == "nt", "upstream Windows file adapter test")
    def test_upstream_read_file_handles_normalized_windows_path(self):
        from tools import terminal_tool
        from tools.registry import registry

        with tempfile.TemporaryDirectory(prefix="iris-file-tool-") as temp:
            workspace = Path(temp).resolve()
            (workspace / "seed.txt").write_text("IRIS_FILE_TOOL_OK", encoding="utf-8")
            terminal_tool._task_env_overrides["file-test"] = {"cwd": str(workspace)}
            iris_action_tools.register_iris_action_guards()
            result = json.loads(
                registry.get_entry("read_file").handler(
                    {"path": "seed.txt"},
                    task_id="file-test",
                )
            )
        self.assertIn("IRIS_FILE_TOOL_OK", result["content"])

    @unittest.skipUnless(os.name == "nt", "native PowerShell adapter is Windows-only")
    def test_native_powershell_returns_output_and_exit_status(self):
        workspace = Path(tempfile.gettempdir()).resolve()
        with (
            patch.object(
                iris_action_tools,
                "_workspace_for_task",
                return_value=workspace,
            ),
            patch(
                "tools.terminal_tool._check_all_guards",
                return_value={"approved": True},
            ),
        ):
            result = json.loads(
                iris_action_tools._native_terminal_handler(
                    {
                        "command": "Write-Output 'IRIS_NATIVE_POWERSHELL_OK'",
                        "timeout": 10,
                    },
                    task_id="test",
                )
            )
        self.assertEqual(result["exit_code"], 0)
        self.assertIn("IRIS_NATIVE_POWERSHELL_OK", result["output"])

    @unittest.skipUnless(os.name == "nt", "native PowerShell adapter is Windows-only")
    def test_background_process_can_be_waited_and_read(self):
        workspace = Path(tempfile.gettempdir()).resolve()
        with (
            patch.object(
                iris_action_tools,
                "_workspace_for_task",
                return_value=workspace,
            ),
            patch(
                "tools.terminal_tool._check_all_guards",
                return_value={"approved": True},
            ),
        ):
            started = json.loads(
                iris_action_tools._native_terminal_handler(
                    {
                        "command": (
                            "Start-Sleep -Milliseconds 100; "
                            "Write-Output 'IRIS_BACKGROUND_OK'"
                        ),
                        "background": True,
                    },
                    task_id="background-test",
                )
            )
        session_id = started["session_id"]
        waited = json.loads(
            iris_action_tools._native_process_handler(
                {"action": "wait", "session_id": session_id, "timeout": 10},
                task_id="background-test",
            )
        )
        logged = json.loads(
            iris_action_tools._native_process_handler(
                {"action": "log", "session_id": session_id},
                task_id="background-test",
            )
        )
        self.assertEqual(waited["exit_code"], 0)
        self.assertIn("IRIS_BACKGROUND_OK", logged["output"])


if __name__ == "__main__":
    unittest.main()
