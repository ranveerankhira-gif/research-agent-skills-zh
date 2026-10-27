import importlib.util
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).parents[1] / "scripts" / "meta_analysis.py"
SPEC = importlib.util.spec_from_file_location("meta_analysis", SCRIPT)
ma = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(ma)


class MetaAnalysisTests(unittest.TestCase):
    def setUp(self):
        self.rows = [
            {"study_id": "A", "yi": 0.2, "vi": 0.04},
            {"study_id": "B", "yi": 0.5, "vi": 0.09},
            {"study_id": "C", "yi": -0.1, "vi": 0.0625},
            {"study_id": "D", "yi": 0.35, "vi": 0.05},
        ]

    def test_common_effect_known_value(self):
        result = ma.analyze(self.rows, model="common", ci_method="z")
        weights = [1 / row["vi"] for row in self.rows]
        expected = sum(weight * row["yi"] for weight, row in zip(weights, self.rows)) / sum(weights)
        self.assertAlmostEqual(result["estimate"], expected, places=12)
        self.assertEqual(result["tau2"], 0.0)

    def test_distribution_helpers(self):
        self.assertAlmostEqual(ma.student_t_ppf(0.975, 10), 2.228138852, places=7)
        self.assertAlmostEqual(ma.chi2_sf(3.8414588207, 1), 0.05, places=7)

    def test_tau_estimators_nonnegative_and_converged(self):
        reml, reml_converged = ma.tau2_reml(self.rows)
        pm, pm_converged = ma.tau2_pm(self.rows)
        self.assertGreaterEqual(reml, 0)
        self.assertGreaterEqual(pm, 0)
        self.assertTrue(reml_converged)
        self.assertTrue(pm_converged)

    def test_duplicate_study_id_rejected(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            source = Path(temp_dir) / "data.csv"
            source.write_text("study_id,yi,vi\nA,0.1,0.02\nA,0.2,0.03\n", encoding="utf-8")
            with self.assertRaisesRegex(ma.MetaAnalysisError, "duplicate study_id"):
                ma.load_effects(source)

    def test_path_collision_and_existing_output_rejected(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            source = Path(temp_dir) / "data.csv"
            source.write_text("study_id,yi,vi\nA,0.1,0.02\nB,0.2,0.03\n", encoding="utf-8")
            with self.assertRaisesRegex(ma.MetaAnalysisError, "input path"):
                ma._validate_outputs(source, [source], False)
            output = Path(temp_dir) / "out.json"
            with self.assertRaisesRegex(ma.MetaAnalysisError, "distinct"):
                ma._validate_outputs(source, [output, output], False)
            output.write_text("keep", encoding="utf-8")
            with self.assertRaisesRegex(ma.MetaAnalysisError, "output exists"):
                ma._validate_outputs(source, [output], False)

    def test_svg_generation(self):
        result = ma.analyze(self.rows, model="random", tau_method="reml", ci_method="hksj")
        svg = ma.render_svg(result)
        self.assertIn("<svg", svg)
        self.assertIn("Summary (random)", svg)
        self.assertNotIn("nan", svg.lower())

    def test_svg_uses_requested_confidence_level_for_study_intervals(self):
        result = ma.analyze(self.rows, model="random", tau_method="reml", ci_method="hksj", alpha=0.10)
        svg = ma.render_svg(result)
        self.assertIn("90% study intervals", svg)
        self.assertIn("summary interval: hksj", svg)

    def test_cli_writes_all_outputs_and_protects_them(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            source = root / "data.csv"
            source.write_text(
                "study_id,yi,sei\nA,0.10,0.20\nB,0.25,0.25\nC,-0.05,0.30\n",
                encoding="utf-8",
            )
            json_path, csv_path, svg_path = root / "result.json", root / "weights.csv", root / "forest.svg"
            args = ["--input", str(source), "--output-json", str(json_path),
                    "--output-csv", str(csv_path), "--forest-svg", str(svg_path)]
            self.assertEqual(ma.main(args), 0)
            self.assertTrue(json_path.read_text(encoding="utf-8").startswith("{"))
            self.assertIn("kind,study_id", csv_path.read_text(encoding="utf-8"))
            self.assertIn("<svg", svg_path.read_text(encoding="utf-8"))
            self.assertEqual(ma.main(args), 2)


if __name__ == "__main__":
    unittest.main()
