from __future__ import annotations

import io
import json
import sys
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch


sys.path.insert(0, str(Path(__file__).resolve().parent))
import iris_acp


class IrisAcpBridgeTests(unittest.TestCase):
    @staticmethod
    def _locked_compression_runtime(model="locked-model"):
        return {
            "model": model,
            "provider": "custom",
            "base_url": iris_acp.IRIS_OLLAMA_BASE_URL,
            "api_key": iris_acp.IRIS_OLLAMA_API_KEY,
            "api_mode": "chat_completions",
        }

    def test_every_agentic_model_request_revalidates_the_parent_model_lock_once(self):
        class FakeAgentBase:
            def _ensure_primary_openai_client(self, *, reason):
                return {"reason": reason}

            def _create_request_openai_client(self, *, reason, api_kwargs=None):
                client = self._ensure_primary_openai_client(reason=reason)
                return {**client, "api_kwargs": api_kwargs}

        class LockedFakeAgent(iris_acp.IrisLockedOllamaAgentMixin, FakeAgentBase):
            pass

        agent = LockedFakeAgent()
        with patch.object(
            iris_acp.iris_broker,
            "assert_iris_ollama_model_identity",
            return_value={},
        ) as verify:
            self.assertEqual(
                agent._create_request_openai_client(
                    reason="first",
                    api_kwargs={"messages": []},
                )["reason"],
                "first",
            )
            agent._create_request_openai_client(reason="second")

        self.assertEqual(verify.call_count, 2)

    def test_iteration_limit_summary_and_retry_revalidate_the_parent_model_lock(self):
        from agent.chat_completion_helpers import handle_max_iterations

        reasons = []

        class FakeCompletions:
            def __init__(self):
                self.contents = iter(("", "summary after retry"))

            def create(self, **_kwargs):
                return SimpleNamespace(content=next(self.contents))

        request_client = SimpleNamespace(
            chat=SimpleNamespace(completions=FakeCompletions())
        )

        class FakeAgentBase:
            def _ensure_primary_openai_client(self, *, reason):
                reasons.append(reason)
                return request_client

            def _should_sanitize_tool_calls(self):
                return False

            def _copy_reasoning_content_for_api(self, _source, _target):
                return None

            def _sanitize_api_messages(self, messages):
                return messages

            def _drop_thinking_only_and_merge_users(self, messages):
                return messages

            def _supports_reasoning_extra_body(self):
                return False

            def _max_tokens_param(self, value):
                return {"max_tokens": value}

            def _is_openrouter_url(self):
                return False

            def _get_transport(self):
                return SimpleNamespace(
                    normalize_response=lambda response: response
                )

        class LockedFakeAgent(iris_acp.IrisLockedOllamaAgentMixin, FakeAgentBase):
            pass

        agent = LockedFakeAgent()
        agent.max_iterations = 8
        agent.model = "locked-model"
        agent.base_url = "http://127.0.0.1:11434/v1"
        agent._base_url_lower = agent.base_url
        agent.provider = "custom"
        agent.api_mode = "chat_completions"
        agent.max_tokens = 512
        agent.reasoning_config = {"enabled": False}
        agent._cached_system_prompt = ""
        agent.ephemeral_system_prompt = ""
        agent.prefill_messages = []
        agent.providers_allowed = []
        agent.providers_ignored = []
        agent.providers_order = []
        agent.provider_sort = None
        agent.openrouter_min_coding_score = None
        with patch.object(
            iris_acp.iris_broker,
            "assert_iris_ollama_model_identity",
            return_value={},
        ) as verify:
            with redirect_stdout(io.StringIO()):
                response = handle_max_iterations(
                    agent,
                    [{"role": "user", "content": "finish"}],
                    8,
                )

        self.assertEqual(response, "summary after retry")
        self.assertEqual(
            reasons,
            ["iteration_limit_summary", "iteration_limit_summary_retry"],
        )
        self.assertEqual(verify.call_count, 2)

    def test_agentic_model_request_fails_closed_when_identity_revalidation_fails(self):
        class FakeAgentBase:
            def _ensure_primary_openai_client(self, *, reason):
                return {"reason": reason}

        class LockedFakeAgent(iris_acp.IrisLockedOllamaAgentMixin, FakeAgentBase):
            pass

        agent = LockedFakeAgent()
        with patch.object(
            iris_acp.iris_broker,
            "assert_iris_ollama_model_identity",
            side_effect=RuntimeError("model identity mismatch"),
        ):
            with self.assertRaisesRegex(RuntimeError, "model identity mismatch"):
                agent._ensure_primary_openai_client(
                    reason="iteration_limit_summary"
                )

    def test_context_compression_uses_only_locked_iris_generation(self):
        from agent import context_compressor as hermes_context_compressor

        original_call_llm = hermes_context_compressor.call_llm
        compressor = hermes_context_compressor.ContextCompressor(
            model="locked-model",
            base_url=iris_acp.IRIS_OLLAMA_BASE_URL,
            api_key=iris_acp.IRIS_OLLAMA_API_KEY,
            config_context_length=65_536,
            provider="custom",
            api_mode="chat_completions",
            quiet_mode=True,
            abort_on_summary_failure=False,
        )
        agent = SimpleNamespace(
            context_compressor=compressor,
            compression_enabled=False,
        )
        with patch.object(
            hermes_context_compressor,
            "call_llm",
            original_call_llm,
        ), patch.object(
            iris_acp.iris_broker,
            "configured_iris_model_lock",
            return_value={"model_id": "locked-model"},
        ), patch.object(
            iris_acp.iris_broker,
            "iris_generate_text",
            return_value="## Active Task\nNone.",
        ) as generate:
            iris_acp.configure_iris_locked_context_compression(agent)
            self.assertTrue(agent.compression_enabled)
            self.assertTrue(agent._compression_feasibility_checked)
            self.assertTrue(compressor.abort_on_summary_failure)
            summary = compressor._generate_summary(
                [{"role": "user", "content": "Summarize this completed task."}]
            )

        self.assertIn("## Active Task", summary)
        generate.assert_called_once()
        self.assertEqual(
            generate.call_args.kwargs,
            {"max_tokens": iris_acp.IRIS_COMPRESSION_MAX_TOKENS, "temperature": 0.0},
        )

    def test_context_compression_rejects_model_or_route_overrides(self):
        valid_runtime = self._locked_compression_runtime()
        with patch.object(
            iris_acp.iris_broker,
            "configured_iris_model_lock",
            return_value={"model_id": "locked-model"},
        ), patch.object(iris_acp.iris_broker, "iris_generate_text") as generate:
            with self.assertRaisesRegex(RuntimeError, "runtime differs"):
                iris_acp.iris_locked_compression_call(
                    task="compression",
                    main_runtime={**valid_runtime, "model": "drifted-model"},
                    messages=[{"role": "user", "content": "summary"}],
                    max_tokens=512,
                )
            with self.assertRaisesRegex(RuntimeError, "override is forbidden"):
                iris_acp.iris_locked_compression_call(
                    task="compression",
                    provider="openrouter",
                    main_runtime=valid_runtime,
                    messages=[{"role": "user", "content": "summary"}],
                    max_tokens=512,
                )

        generate.assert_not_called()

    def test_context_compression_identity_failure_preserves_all_messages(self):
        from agent import context_compressor as hermes_context_compressor

        compressor = hermes_context_compressor.ContextCompressor(
            model="locked-model",
            base_url=iris_acp.IRIS_OLLAMA_BASE_URL,
            api_key=iris_acp.IRIS_OLLAMA_API_KEY,
            config_context_length=65_536,
            provider="custom",
            api_mode="chat_completions",
            quiet_mode=True,
            abort_on_summary_failure=False,
        )
        agent = SimpleNamespace(
            context_compressor=compressor,
            compression_enabled=False,
        )
        messages = [{"role": "system", "content": "system"}]
        for index in range(40):
            messages.append(
                {"role": "user", "content": f"request {index} " + "u" * 2_000}
            )
            messages.append(
                {"role": "assistant", "content": f"answer {index} " + "a" * 2_000}
            )

        with patch.object(
            iris_acp.iris_broker,
            "configured_iris_model_lock",
            return_value={"model_id": "locked-model"},
        ), patch.object(
            iris_acp.iris_broker,
            "iris_generate_text",
            side_effect=RuntimeError("model identity mismatch"),
        ):
            iris_acp.configure_iris_locked_context_compression(agent)
            with self.assertLogs("agent.context_compressor", level="WARNING"):
                result = compressor.compress(messages, current_tokens=65_536, force=True)

        self.assertEqual(result, messages)
        self.assertTrue(compressor._last_compress_aborted)
        self.assertEqual(compressor._last_summary_dropped_count, 0)

    def test_context_compression_prompt_and_output_are_bounded(self):
        prompt = "h" * 20_000 + "middle" + "t" * 20_000
        with patch.object(
            iris_acp.iris_broker,
            "configured_iris_model_lock",
            return_value={"model_id": "locked-model"},
        ), patch.object(
            iris_acp.iris_broker,
            "iris_generate_text",
            return_value="bounded summary",
        ) as generate:
            response = iris_acp.iris_locked_compression_call(
                task="compression",
                main_runtime=self._locked_compression_runtime(),
                messages=[{"role": "user", "content": prompt}],
                max_tokens=20_000,
            )

        self.assertEqual(response.choices[0].message.content, "bounded summary")
        bounded_prompt = generate.call_args.args[0]
        self.assertEqual(len(bounded_prompt), iris_acp.IRIS_COMPRESSION_MAX_PROMPT_CHARS)
        self.assertIn("IRIS BOUNDED COMPRESSION", bounded_prompt)
        self.assertEqual(
            generate.call_args.kwargs["max_tokens"],
            iris_acp.IRIS_COMPRESSION_MAX_TOKENS,
        )

    def test_audit_reports_local_ollama_generation_limits(self):
        buffer = io.StringIO()
        with redirect_stdout(buffer):
            self.assertEqual(iris_acp.audit_tools(), 0)

        audit = json.loads(buffer.getvalue())
        self.assertEqual(audit["maxTokens"], 512)
        self.assertEqual(audit["requestOverrides"]["temperature"], 0)
        self.assertEqual(audit["requestOverrides"]["toolChoice"], "prompt_scoped")
        self.assertTrue(audit["promptScopedTools"])
        self.assertTrue(audit["irisOwnedSystemPrompt"])
        self.assertEqual(audit["systemPromptChars"], len(iris_acp.IRIS_SYSTEM_PROMPT))
        self.assertLess(audit["systemPromptChars"], 700)
        self.assertFalse(audit["requestOverrides"]["extraBody"]["think"])
        self.assertEqual(
            audit["requestOverrides"]["extraBody"]["options"]["numPredict"],
            512,
        )
        self.assertIn("only the tools Iris provides", iris_acp.IRIS_SYSTEM_PROMPT)
        self.assertIn("untrusted evidence", iris_acp.IRIS_SYSTEM_PROMPT)
        self.assertEqual(audit["contextCompression"], "iris_locked_ollama")
        self.assertEqual(
            audit["compressionMaxTokens"], iris_acp.IRIS_COMPRESSION_MAX_TOKENS
        )
        self.assertFalse(audit["auxiliaryFallbackModels"])

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

    def test_explicit_single_tool_prompt_forces_exact_tool_choice(self):
        prompt = [{"type": "text", "text": "Call read_file on seed.txt now."}]
        allowed = iris_acp.tool_names_for_prompt(prompt)

        self.assertIn("read_file", allowed)
        self.assertEqual(
            iris_acp.exact_tool_choice_for_prompt(prompt, allowed),
            {"type": "function", "function": {"name": "read_file"}},
        )

    def test_natural_browser_prompt_keeps_auto_tool_choice(self):
        prompt = [{"type": "text", "text": "Look online for the latest Ollama release."}]
        allowed = iris_acp.tool_names_for_prompt(prompt)

        self.assertIn("browser_open", allowed)
        self.assertIsNone(iris_acp.exact_tool_choice_for_prompt(prompt, allowed))


if __name__ == "__main__":
    unittest.main()
