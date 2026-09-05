import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import build as engine_build


class ConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        architecture = self.root / "source-repo/source/eval/nnue/architectures"
        architecture.mkdir(parents=True)
        (architecture / "nnue_arch_gen.py").write_text("# テスト用")
        (self.root / "source-repo/source/config.h").write_text("#define ENGINE_VERSION 1")
        (self.root / "ios.patch").write_text("# テスト用")
        (self.root / "nn.bin").write_bytes(b"nnue-fixture")
        (self.root / "progress.bin").write_bytes(b"progress-fixture")
        self.item = {"id": "first-engine", "displayName": "最初のエンジン", "version": "1",
                     "source": "source-repo", "patch": "ios.patch", "architecture": "SFNN_example",
                     "nnue": "nn.bin", "options": {"FV_SCALE": 40}}

    def load(self, engines, default="first-engine", policy="first-engine"):
        path = self.root / "engines.json"
        path.write_text(json.dumps({"engines": engines, "defaultEngine": default, "policyEngine": policy}))
        return engine_build.load_configuration(path, self.root)

    def test_second_engine_generates_registration_and_its_own_assets(self):
        first = copy.deepcopy(self.item)
        first["progress"] = "progress.bin"
        first["options"]["LS_PROGRESS_COEFF"] = "@progress"
        second = dict(self.item, id="second-engine", displayName='追加の"エンジン"')
        configuration = self.load([first, second], default="second-engine")
        swift = engine_build.swift_configuration(configuration)
        registry = engine_build.registry_source(configuration)
        self.assertIn('static let defaultEngine = engines[1]', swift)
        self.assertIn('directoryName: "second-engine"', swift)
        self.assertIn('progressSize: nil', swift)
        self.assertIn('追加の\\"エンジン\\"', swift)
        self.assertIn('engine_first_engine_start', registry)
        self.assertIn('engine_second_engine_start', registry)
        self.assertEqual(configuration.engines[1].options["FV_SCALE"], "40")

    def test_duplicate_ids_cannot_share_native_symbols(self):
        with self.assertRaisesRegex(ValueError, "重複"):
            self.load([self.item, self.item])
        with self.assertRaisesRegex(ValueError, "id:"):
            self.load([dict(self.item, id="first_engine")])

    def test_missing_progress_cannot_be_referenced_by_an_option(self):
        item = dict(self.item, options={"LS_PROGRESS_COEFF": "@progress"})
        with self.assertRaisesRegex(ValueError, "progressファイル"):
            self.load([item])

    def test_missing_resource_reports_the_exact_field(self):
        with self.assertRaisesRegex(ValueError, "first-engine.nnue"):
            self.load([dict(self.item, nnue="missing.bin")])

    def test_configuration_cannot_override_the_users_hash_setting(self):
        with self.assertRaisesRegex(ValueError, "USI_Hash"):
            self.load([dict(self.item, options={"USI_Hash": 1024})])

    def test_default_and_policy_must_name_built_engines(self):
        with self.assertRaisesRegex(ValueError, "defaultEngine"):
            self.load([self.item], default="missing")
        with self.assertRaisesRegex(ValueError, "policyEngine"):
            self.load([self.item], policy="missing")

    def test_shipped_resources_can_be_used_as_build_inputs(self):
        configuration = self.load([self.item])
        engine_build.publish_resources(configuration, self.root)
        bundled = self.root / "KifuLens/EngineAssets/first-engine/eval/nn.bin"
        expected = bundled.read_bytes()
        configuration.engines[0].nnue = bundled
        unused = self.root / "KifuLens/EngineAssets/unused-engine"
        unused.mkdir()
        (unused / "user-file").write_text("保持する")
        engine_build.publish_resources(configuration, self.root)
        self.assertEqual(bundled.read_bytes(), expected)
        self.assertTrue((unused / "user-file").exists())
        specification = json.loads((self.root / "engine-resources.yml").read_text())
        self.assertEqual(specification["targets"]["KifuLens"]["sources"], [
            {"path": "KifuLens/EngineAssets/first-engine", "type": "folder", "buildPhase": "resources"}
        ])


if __name__ == "__main__":
    unittest.main()
