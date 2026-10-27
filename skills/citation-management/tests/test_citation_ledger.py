import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).parents[1] / "scripts" / "citation_ledger.py"
SPEC = importlib.util.spec_from_file_location("citation_ledger", SCRIPT)
ledger = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(ledger)


class CitationLedgerTests(unittest.TestCase):
    def test_identifier_and_url_normalization(self):
        self.assertEqual(ledger.normalize_doi("https://doi.org/10.1000/ABC.1."), "10.1000/abc.1")
        self.assertEqual(
            ledger.normalize_doi("https://doi.org/10.1000/ABC.1?utm_source=example#part"),
            "10.1000/abc.1",
        )
        self.assertEqual(
            ledger.normalize_url("HTTPS://Example.COM/paper?utm_source=x&view=full#section"),
            "https://example.com/paper?view=full",
        )

    def test_duplicate_groups_do_not_delete_records(self):
        records = [
            {"id": "a", "title": "Same", "DOI": "10.1/X", "issued": {"date-parts": [[2024]]}},
            {"id": "b", "title": "Same", "DOI": "https://doi.org/10.1/x", "issued": {"date-parts": [[2024]]}},
            {"id": "c", "title": "Another Study", "DOI": "10.2/a", "issued": {"date-parts": [[2023]]}},
            {"id": "d", "title": "Another study!", "DOI": "10.2/b", "issued": {"date-parts": [[2023]]}},
        ]
        normalized, report = ledger.audit_records(records)
        self.assertEqual(len(normalized), 4)
        self.assertEqual(report["exact_duplicate_groups"][0]["record_ids"], ["a", "b"])
        self.assertEqual(report["possible_duplicate_groups"][0]["record_ids"], ["c", "d"])

    def test_duplicate_ids_rejected(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "records.json"
            path.write_text(json.dumps([{"id": "x", "title": "One"}, {"id": "x", "title": "Two"}]), encoding="utf-8")
            with self.assertRaisesRegex(ledger.CitationLedgerError, "duplicate CSL id"):
                ledger.load_records(path)

    def test_invalid_status_rejected(self):
        record = {"id": "a", "title": "One", "_audit": {"verification_status": "大概正确"}}
        with self.assertRaisesRegex(ledger.CitationLedgerError, "unsupported verification_status"):
            ledger.normalize_record(record)

    def test_path_collision_and_existing_output_rejected(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            source = Path(temp_dir) / "records.json"
            source.write_text("[]", encoding="utf-8")
            with self.assertRaisesRegex(ledger.CitationLedgerError, "input path"):
                ledger._validate_outputs(source, [source], False)
            output = Path(temp_dir) / "out.json"
            with self.assertRaisesRegex(ledger.CitationLedgerError, "distinct"):
                ledger._validate_outputs(source, [output, output], False)
            output.write_text("keep", encoding="utf-8")
            with self.assertRaisesRegex(ledger.CitationLedgerError, "output exists"):
                ledger._validate_outputs(source, [output], False)

    def test_bibtex_export_is_conservative(self):
        records = [{
            "id": "Smith2024", "type": "article-journal", "title": "A & B",
            "author": [{"family": "Smith", "given": "Ada"}],
            "issued": {"date-parts": [[2024]]}, "DOI": "10.1/example",
        }]
        text = ledger.render_bibtex(records)
        self.assertIn("@article{Smith2024,", text)
        self.assertIn("title = {A \\& B}", text)
        self.assertIn("author = {Smith, Ada}", text)
        self.assertIn("doi = {10.1/example}", text)

    def test_cli_writes_outputs_and_protects_them(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            source = root / "records.json"
            source.write_text(json.dumps([{"id": "a", "title": "One"}]), encoding="utf-8")
            normalized, report, bib = root / "normalized.json", root / "report.json", root / "refs.bib"
            args = ["--input", str(source), "--normalized-json", str(normalized),
                    "--report-json", str(report), "--bibtex", str(bib)]
            self.assertEqual(ledger.main(args), 0)
            self.assertIsInstance(json.loads(normalized.read_text(encoding="utf-8")), list)
            self.assertEqual(json.loads(report.read_text(encoding="utf-8"))["record_count"], 1)
            self.assertIn("@misc{a,", bib.read_text(encoding="utf-8"))
            self.assertEqual(ledger.main(args), 2)


if __name__ == "__main__":
    unittest.main()
