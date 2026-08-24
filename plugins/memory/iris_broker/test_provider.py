import hashlib
import json
import os
import sys
import tempfile
import unittest
import urllib.error
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import provider


class ProviderWebResearchTests(unittest.TestCase):
    def _locked_store_fixture(self, temporary_root: str):
        lock = json.loads(
            (provider.repo_root() / "profiles" / "iris_ollama_model.lock.json").read_text(
                encoding="utf-8"
            )
        )
        models_root = Path(temporary_root) / "models"
        config_bytes = b"config"
        model_bytes = b"locked model"
        config_digest = "sha256:" + hashlib.sha256(config_bytes).hexdigest()
        model_digest = "sha256:" + hashlib.sha256(model_bytes).hexdigest()
        manifest = {
            "config": {
                "mediaType": "application/vnd.docker.container.image.v1+json",
                "digest": config_digest,
                "size": len(config_bytes),
            },
            "layers": [
                {
                    "mediaType": "application/vnd.ollama.image.model",
                    "digest": model_digest,
                    "size": len(model_bytes),
                }
            ],
        }
        manifest_bytes = json.dumps(manifest, separators=(",", ":")).encode("utf-8")
        lock["manifest_digest"] = hashlib.sha256(manifest_bytes).hexdigest()
        lock["model_layer_digest"] = model_digest
        lock["total_bytes"] = len(config_bytes) + len(model_bytes)
        manifest_path = provider._ollama_manifest_path(models_root, lock["model_id"])
        manifest_path.parent.mkdir(parents=True)
        manifest_path.write_bytes(manifest_bytes)
        blobs = models_root / "blobs"
        blobs.mkdir(parents=True)
        descriptor_rows = []
        for descriptor, content in zip(
            [manifest["config"], *manifest["layers"]],
            [config_bytes, model_bytes],
            strict=True,
        ):
            blob = blobs / descriptor["digest"].replace(":", "-", 1)
            blob.write_bytes(content)
            metadata = blob.stat()
            descriptor_rows.append(
                {
                    "media_type": descriptor["mediaType"],
                    "digest": descriptor["digest"],
                    "size": descriptor["size"],
                    "modified_unix_ns": metadata.st_mtime_ns,
                    "created_unix_ns": getattr(
                        metadata, "st_birthtime_ns", metadata.st_ctime_ns
                    ),
                }
            )
        attestation = {
            "schema_version": 1,
            "model_id": lock["model_id"],
            "models_root": str(models_root),
            "manifest_digest": lock["manifest_digest"],
            "model_layer_digest": lock["model_layer_digest"],
            "descriptors": descriptor_rows,
        }
        details = {
            "family": lock["family"],
            "parameter_size": lock["parameter_size"],
            "quantization_level": lock["quantization_level"],
        }
        tag = {
            "name": lock["model_id"],
            "model": lock["model_id"],
            "digest": lock["manifest_digest"],
            "size": lock["total_bytes"],
            "details": details,
        }
        model_blob = blobs / model_digest.replace(":", "-", 1)
        show = {
            "modelfile": (
                f"# FROM {lock['model_id']}\n\nFROM {model_blob}\n"
                'LICENSE """\nFROM inside license text\n"""'
            ),
            "details": details,
            "capabilities": lock["required_capabilities"],
        }
        return lock, tag, show, attestation, models_root, model_blob

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
        ), patch.object(
            provider, "assert_iris_ollama_model_identity", return_value={}
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

    def test_locked_model_identity_is_required_before_each_generation(self):
        with tempfile.TemporaryDirectory() as temporary_root:
            lock, tag, show, attestation, _, _ = self._locked_store_fixture(
                temporary_root
            )
            with patch.object(
                provider, "_CONFIGURED_MODEL_LOCK_JSON", json.dumps(lock)
            ), patch.object(
                provider,
                "_CONFIGURED_MODEL_STORE_ATTESTATION_JSON",
                json.dumps(attestation),
            ), patch.object(
                provider, "_ollama_json_request", side_effect=[{"models": [tag]}, show]
            ) as identity_request:
                self.assertEqual(
                    provider.assert_iris_ollama_model_identity()["manifest_digest"],
                    lock["manifest_digest"],
                )
            self.assertEqual(identity_request.call_count, 2)

            drifted = dict(tag)
            drifted["digest"] = "0" * 64
            with patch.object(
                provider, "_CONFIGURED_MODEL_LOCK_JSON", json.dumps(lock)
            ), patch.object(
                provider,
                "_CONFIGURED_MODEL_STORE_ATTESTATION_JSON",
                json.dumps(attestation),
            ), patch.object(
                provider,
                "_ollama_json_request",
                side_effect=[{"models": [drifted]}, show],
            ):
                with self.assertRaisesRegex(
                    provider.IrisBrokerUnavailable, "digest differs"
                ):
                    provider.assert_iris_ollama_model_identity()

    def test_locked_model_source_requires_unique_from_under_verified_root(self):
        with tempfile.TemporaryDirectory() as temporary_root:
            lock, _, show, attestation, models_root, _ = self._locked_store_fixture(
                temporary_root
            )
            with patch.object(
                provider,
                "_CONFIGURED_MODEL_STORE_ATTESTATION_JSON",
                json.dumps(attestation),
            ):
                provider.assert_iris_ollama_model_store(lock, show)

                wrong_root_show = dict(show)
                wrong_root_show["modelfile"] = (
                    "FROM "
                    + str(
                        models_root.parent
                        / "different-store"
                        / "blobs"
                        / lock["model_layer_digest"].replace(":", "-", 1)
                    )
                )
                with self.assertRaisesRegex(
                    provider.IrisBrokerUnavailable, "differs from Iris"
                ):
                    provider.assert_iris_ollama_model_store(lock, wrong_root_show)

                ambiguous_show = dict(show)
                ambiguous_show["modelfile"] = (
                    show["modelfile"]
                    + "\nFROM "
                    + str(models_root / "blobs" / ("sha256-" + "0" * 64))
                )
                with self.assertRaisesRegex(
                    provider.IrisBrokerUnavailable, "more than one active FROM"
                ):
                    provider.assert_iris_ollama_model_store(lock, ambiguous_show)

                missing_show = dict(show)
                missing_show["modelfile"] = "# FROM commented-only"
                with self.assertRaisesRegex(
                    provider.IrisBrokerUnavailable, "did not report an active FROM"
                ):
                    provider.assert_iris_ollama_model_store(lock, missing_show)

    def test_locked_model_store_rechecks_descriptor_metadata_per_request(self):
        with tempfile.TemporaryDirectory() as temporary_root:
            lock, _, show, attestation, _, model_blob = self._locked_store_fixture(
                temporary_root
            )
            with patch.object(
                provider,
                "_CONFIGURED_MODEL_STORE_ATTESTATION_JSON",
                json.dumps(attestation),
            ):
                provider.assert_iris_ollama_model_store(lock, show)
                original = model_blob.read_bytes()
                model_blob.write_bytes(bytes([original[0] ^ 1]) + original[1:])
                metadata = model_blob.stat()
                os.utime(
                    model_blob,
                    ns=(metadata.st_atime_ns, metadata.st_mtime_ns + 1_000_000_000),
                )
                with self.assertRaisesRegex(
                    provider.IrisBrokerUnavailable, "metadata changed"
                ):
                    provider.assert_iris_ollama_model_store(lock, show)

    def test_locked_generation_uses_bounded_requested_options(self):
        lock = {"model_id": "locked-model"}

        class FakeResponse:
            def __enter__(self):
                return self

            def __exit__(self, *_args):
                return False

            def read(self, _limit):
                return json.dumps({"response": "locked response"}).encode("utf-8")

        with patch.object(
            provider,
            "assert_iris_ollama_model_identity",
            return_value=lock,
        ) as verify, patch(
            "urllib.request.urlopen",
            return_value=FakeResponse(),
        ) as open_url:
            self.assertEqual(
                provider.iris_generate_text(
                    "compression prompt",
                    max_tokens=1024,
                    temperature=0.0,
                ),
                "locked response",
            )

        verify.assert_called_once_with()
        request = open_url.call_args.args[0]
        payload = json.loads(request.data.decode("utf-8"))
        self.assertEqual(request.full_url, provider.IRIS_OLLAMA_GENERATE_URL)
        self.assertEqual(open_url.call_args.kwargs["timeout"], 180)
        self.assertEqual(payload["model"], "locked-model")
        self.assertEqual(payload["options"]["num_predict"], 1024)
        self.assertEqual(payload["options"]["temperature"], 0.0)

    def test_locked_generation_rejects_unbounded_options_before_identity_check(self):
        with patch.object(
            provider,
            "assert_iris_ollama_model_identity",
        ) as verify:
            with self.assertRaisesRegex(ValueError, "max_tokens"):
                provider.iris_generate_text(
                    "prompt",
                    max_tokens=provider.MAX_IRIS_GENERATION_TOKENS + 1,
                )
            with self.assertRaisesRegex(ValueError, "temperature"):
                provider.iris_generate_text("prompt", temperature=True)

        verify.assert_not_called()


if __name__ == "__main__":
    unittest.main()
