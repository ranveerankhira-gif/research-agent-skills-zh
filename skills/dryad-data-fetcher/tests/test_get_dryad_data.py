from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import unittest
from urllib.parse import urlparse


SKILL_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = SKILL_ROOT / "scripts" / "Get-DryadData.ps1"
PWSH = os.environ.get("PWSH", "pwsh")


class DryadFixture:
    def __init__(self) -> None:
        self.files = [self.file_record(1, "data.csv", b"alpha")]
        self.modes: dict[int, str] = {1: "redirect"}

    @staticmethod
    def file_record(file_id: int, name: str, payload: bytes, digest: str | None = None) -> dict:
        return {
            "id": file_id,
            "path": name,
            "payload": payload,
            "size": len(payload),
            "digest": digest if digest is not None else hashlib.sha256(payload).hexdigest(),
        }

    def api_entry(self, item: dict) -> dict:
        return {
            "_links": {
                "self": {"href": f"/api/v2/files/{item['id']}"},
                "stash:download": {"href": f"/api/v2/files/{item['id']}/download"},
            },
            "path": item["path"],
            "size": item["size"],
            "mimeType": "text/csv",
            "digest": item["digest"],
            "digestType": "sha-256",
        }


def make_handler(fixture: DryadFixture):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_args) -> None:
            pass

        def json_response(self, value: dict) -> None:
            data = json.dumps(value).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/hal+json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self) -> None:  # noqa: N802 - stdlib callback name
            parsed = urlparse(self.path)
            path = parsed.path
            if path.startswith("/api/v2/datasets/"):
                self.json_response({"_links": {"stash:version": {"href": "/api/v2/versions/1"}}})
                return
            if path == "/api/v2/versions/1":
                self.json_response({"_links": {"stash:files": {"href": "/api/v2/versions/1/files"}}})
                return
            if path == "/api/v2/versions/1/files" and parsed.query == "page=2":
                self.json_response({"_links": {}, "_embedded": {"stash:files": [fixture.api_entry(x) for x in fixture.files[1:]]}})
                return
            if path == "/api/v2/versions/1/files":
                first = fixture.files[:1]
                links = {"next": {"href": "/api/v2/versions/1/files?page=2"}} if len(fixture.files) > 1 else {}
                self.json_response({"_links": links, "_embedded": {"stash:files": [fixture.api_entry(x) for x in first]}})
                return
            if (path.startswith("/api/v2/files/") and path.endswith("/download")) or path.startswith("/downloads/file_stream/"):
                file_id = int(path.rstrip("/").split("/")[-2] if path.endswith("/download") else path.rstrip("/").split("/")[-1])
                mode = fixture.modes.get(file_id, "redirect")
                if mode == "evil-redirect":
                    self.send_response(302)
                    self.send_header("Location", "https://example.invalid/stolen")
                    self.end_headers()
                    return
                if mode == "html":
                    body = b"<!doctype html><html><body>Anubis</body></html>"
                    self.send_response(200)
                    self.send_header("Content-Type", "text/html")
                    self.send_header("Content-Length", str(len(body)))
                    self.end_headers()
                    self.wfile.write(body)
                    return
                self.send_response(302)
                self.send_header("Location", f"/asset/{file_id}")
                self.end_headers()
                return
            if path.startswith("/asset/"):
                file_id = int(path.split("/")[2])
                item = next(x for x in fixture.files if x["id"] == file_id)
                body = item["payload"]
                self.send_response(200)
                self.send_header("Content-Type", "text/csv")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return
            self.send_error(404)

    return Handler


class DryadFetcherTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.fixture = DryadFixture()
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), make_handler(cls.fixture))
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.base_uri = f"http://127.0.0.1:{cls.server.server_port}/api/v2/"

    @classmethod
    def tearDownClass(cls) -> None:
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join(timeout=5)

    def setUp(self) -> None:
        self.fixture.files = [self.fixture.file_record(1, "data.csv", b"alpha")]
        self.fixture.modes = {1: "redirect"}
        self.temp = tempfile.TemporaryDirectory(prefix="dryad-fetcher-test-")
        self.temp_path = Path(self.temp.name)

    def tearDown(self) -> None:
        self.temp.cleanup()

    def run_skill(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        command = [
            PWSH, "-NoLogo", "-NoProfile", "-File", str(SCRIPT),
            "-Dataset", "10.5068/D1TEST", "-ApiBaseUri", self.base_uri,
            "-AllowTestApiBaseUri", *map(str, arguments),
        ]
        return subprocess.run(command, text=True, encoding="utf-8", capture_output=True, timeout=45, check=False)

    def assert_failed_without_partial(self, result: subprocess.CompletedProcess[str], output: Path) -> None:
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertEqual([], list(output.glob("*.partial")) + list(output.glob(".*.partial")))

    def test_list_is_paginated_and_does_not_resolve_opencli(self) -> None:
        self.fixture.files.append(self.fixture.file_record(2, "notes.txt", b"beta"))
        result = self.run_skill("-ListOnly", "-OpenCli", str(self.temp_path / "missing-opencli.cmd"))
        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual(["data.csv", "notes.txt"], [x["name"] for x in payload["files"]])

    def test_download_reuse_collision_and_concurrent_writes(self) -> None:
        output = self.temp_path / "output"
        first = self.run_skill("-OutputDirectory", output)
        self.assertEqual(first.returncode, 0, first.stderr)
        first_payload = json.loads(first.stdout)["files"][0]
        self.assertFalse(first_payload["reused_existing"])

        repeat = self.run_skill("-OutputDirectory", output)
        self.assertEqual(repeat.returncode, 0, repeat.stderr)
        self.assertTrue(json.loads(repeat.stdout)["files"][0]["reused_existing"])

        process_args = [PWSH, "-NoLogo", "-NoProfile", "-File", str(SCRIPT), "-Dataset", "10.5068/D1TEST",
                        "-ApiBaseUri", self.base_uri, "-AllowTestApiBaseUri", "-OutputDirectory", str(output)]
        left = subprocess.Popen(process_args, text=True, encoding="utf-8", stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        right = subprocess.Popen(process_args, text=True, encoding="utf-8", stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        left_out, left_err = left.communicate(timeout=45)
        right_out, right_err = right.communicate(timeout=45)
        self.assertEqual(left.returncode, 0, left_err)
        self.assertEqual(right.returncode, 0, right_err)
        self.assertEqual("alpha", (output / "data.csv").read_text(encoding="utf-8"))

        self.fixture.files = [self.fixture.file_record(1, "data.csv", b"bravo")]
        changed = self.run_skill("-OutputDirectory", output)
        self.assertEqual(changed.returncode, 0, changed.stderr)
        changed_path = Path(json.loads(changed.stdout)["files"][0]["path"])
        self.assertNotEqual(changed_path, output / "data.csv")
        self.assertIn(hashlib.sha256(b"bravo").hexdigest(), changed_path.name)
        self.assertEqual(b"alpha", (output / "data.csv").read_bytes())
        self.assertEqual(b"bravo", changed_path.read_bytes())

    def test_limits_redirect_digest_empty_and_partial_cleanup(self) -> None:
        output = self.temp_path / "output"
        too_large = self.run_skill("-OutputDirectory", output, "-MaxBytes", "4")
        self.assert_failed_without_partial(too_large, output)
        self.assertIn("above -MaxBytes", too_large.stderr)

        self.fixture.modes[1] = "evil-redirect"
        evil = self.run_skill("-OutputDirectory", output)
        self.assert_failed_without_partial(evil, output)
        self.assertIn("unexpected host", evil.stderr)

        self.fixture.modes[1] = "redirect"
        self.fixture.files[0]["digest"] = "0" * 64
        bad_digest = self.run_skill("-OutputDirectory", output)
        self.assert_failed_without_partial(bad_digest, output)
        self.assertIn("digest does not match", bad_digest.stderr)

        self.fixture.files = [self.fixture.file_record(1, "empty.csv", b"")]
        empty = self.run_skill("-OutputDirectory", output)
        self.assert_failed_without_partial(empty, output)
        self.assertIn("empty", empty.stderr.lower())

    def test_path_names_output_boundary_and_reparse_point(self) -> None:
        output = self.temp_path / "output"
        for unsafe_name in ("../escape.csv", "CON.txt", "x" * 181 + ".csv"):
            with self.subTest(name=unsafe_name):
                self.fixture.files = [self.fixture.file_record(1, unsafe_name, b"alpha")]
                result = self.run_skill("-OutputDirectory", output)
                self.assert_failed_without_partial(result, output)

        self.fixture.files = [self.fixture.file_record(1, "data.csv", b"alpha")]
        inside_skill = self.run_skill("-OutputDirectory", SKILL_ROOT / "forbidden-test-output")
        self.assertNotEqual(inside_skill.returncode, 0)
        self.assertIn("Skill directory", inside_skill.stderr)

        target = self.temp_path / "target"
        junction = self.temp_path / "junction"
        target.mkdir()
        created = subprocess.run(["cmd", "/c", "mklink", "/J", str(junction), str(target)], capture_output=True, text=True)
        if created.returncode != 0:
            self.skipTest(f"could not create test junction: {created.stderr}")
        try:
            linked = self.run_skill("-OutputDirectory", junction)
            self.assertNotEqual(linked.returncode, 0)
            self.assertIn("reparse point", linked.stderr)
        finally:
            os.rmdir(junction)

    def test_malformed_browser_base64_is_rejected(self) -> None:
        self.fixture.modes[1] = "html"
        output = self.temp_path / "output"
        fake_opencli = self.temp_path / "opencli.ps1"
        fake_opencli.write_text(
            "param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Remaining)\n"
            "$joined = $Remaining -join ' '\n"
            "if ($joined -match '^profile list$') { 'test default connected'; exit 0 }\n"
            "if ($Remaining -contains 'eval') {\n"
            "  $javascript = $Remaining[-1]\n"
            "  if ($javascript -notmatch \"^fetch\\('http://127\\.0\\.0\\.1:\") { Write-Error 'URL was not single-quoted'; exit 9 }\n"
            "  'DRYAD|200|application/octet-stream|5|%%%'\n"
            "  exit 0\n"
            "}\n"
            "'{\"page\":\"fixture-page\"}'\n",
            encoding="utf-8",
        )
        result = self.run_skill("-OutputDirectory", output, "-OpenCli", fake_opencli, "-ChallengeTimeoutSeconds", "15")
        self.assert_failed_without_partial(result, output)
        self.assertIn("malformed Base64", result.stderr)

        unsafe_cmd = self.temp_path / "opencli.cmd"
        unsafe_cmd.write_text("@echo off\n", encoding="utf-8")
        rejected = self.run_skill("-OutputDirectory", output, "-OpenCli", unsafe_cmd, "-ChallengeTimeoutSeconds", "15")
        self.assert_failed_without_partial(rejected, output)
        self.assertIn("full Windows .cmd shim path", rejected.stderr)

    def test_config_allowlist(self) -> None:
        valid = self.temp_path / "valid.json"
        valid.write_text(json.dumps({"opencli": "opencli", "maxBytes": 1024, "challengeTimeoutSeconds": 15}), encoding="utf-8")
        listed = self.run_skill("-ListOnly", "-ConfigPath", valid)
        self.assertEqual(listed.returncode, 0, listed.stderr)

        invalid = self.temp_path / "invalid.json"
        invalid.write_text(json.dumps({"outputDirectory": "C:\\unexpected"}), encoding="utf-8")
        rejected = self.run_skill("-ListOnly", "-ConfigPath", invalid)
        self.assertNotEqual(rejected.returncode, 0)
        self.assertIn("Unsupported config field", rejected.stderr)


if __name__ == "__main__":
    unittest.main()
