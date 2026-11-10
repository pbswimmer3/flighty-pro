"""Tests for scripts/testflight_feedback.py. Run: python3 -m unittest discover -s scripts -p 'test_*.py'

No network: App Store Connect and GitHub are replaced with in-memory fakes.
"""
import datetime as dt
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import testflight_feedback as tf  # noqa: E402


SCREENSHOT_DOC = {
    "data": {
        "type": "betaFeedbackScreenshotSubmissions",
        "id": "AbC123",
        "attributes": {
            "createdDate": "2026-11-10T05:30:00.000Z",
            "comment": "See traffic at SNA opens SFO\nsecond line",
            "deviceModel": "iPhone16,2",
            "osVersion": "26.1",
            "locale": "en-US",
            "timeZone": "America/Los_Angeles",
            "connectionType": "WIFI",
            "batteryPercentage": 51,
            "appUptimeInMilliseconds": 754000,
            "screenWidthInPoints": 430,
            "screenHeightInPoints": 932,
            "screenshots": [{"url": "https://example.com/a.png", "width": 1290, "height": 2796}],
        },
        "relationships": {
            "build": {"data": {"type": "builds", "id": "b1"}},
            "tester": {"data": {"type": "betaTesters", "id": "t1"}},
        },
    },
    "included": [
        {"type": "builds", "id": "b1", "attributes": {"version": "2"}},
        {"type": "betaTesters", "id": "t1", "attributes": {"firstName": "Test", "lastName": "Er"}},
    ],
}


class Formatting(unittest.TestCase):
    def setUp(self):
        self.submission = tf.flatten(SCREENSHOT_DOC["data"], SCREENSHOT_DOC["included"], "screenshot")

    def test_flatten_resolves_build_and_tester(self):
        s = self.submission
        self.assertEqual(s["build"], "2")
        self.assertEqual(s["tester"], "Test Er")
        self.assertEqual(s["screen"], "430×932 pt")
        self.assertEqual(s["created"], dt.datetime(2026, 11, 10, 5, 30, tzinfo=dt.timezone.utc))

    def test_title_uses_first_line_and_is_capped(self):
        self.assertEqual(tf.issue_title(self.submission), "TestFlight: See traffic at SNA opens SFO")
        long = dict(self.submission, comment="x" * 200)
        self.assertLessEqual(len(tf.issue_title(long)), len("TestFlight: ") + 72)
        crash = dict(self.submission, kind="crash", comment="")
        self.assertEqual(tf.issue_title(crash), "TestFlight: Crash on iPhone16,2")

    def test_issue_body_carries_marker_quote_and_images(self):
        body = tf.report_markdown(self.submission, ["https://x/s.png"], "", for_issue=True)
        self.assertIn("<!-- testflight-feedback-id: AbC123 -->", body)
        self.assertIn("> See traffic at SNA opens SFO\n> second line", body)
        self.assertIn("![screenshot 1](https://x/s.png)", body)
        self.assertIn("| Build | 2 |", body)
        self.assertIn("| App running for | 12m 34s |", body)

    def test_claude_copy_has_no_marker_and_points_at_full_log(self):
        body = tf.report_markdown(dict(self.submission, kind="crash"), [], "line\n" * 500, for_issue=False)
        self.assertNotIn("testflight-feedback-id", body)
        self.assertIn("crash.log", body)
        self.assertNotIn("```", body)

    def test_issue_crash_log_is_truncated(self):
        body = tf.report_markdown(dict(self.submission, kind="crash"), [], "l\n" * 500, for_issue=True)
        self.assertIn("380 more lines", body)

    def test_pem_without_line_breaks_is_rebuilt(self):
        body = "A" * 150
        squashed = f"-----BEGIN PRIVATE KEY-----{body}-----END PRIVATE KEY-----"
        rebuilt = tf.normalise_pem(squashed)
        self.assertTrue(rebuilt.startswith("-----BEGIN PRIVATE KEY-----\n" + "A" * 64 + "\n"))
        self.assertTrue(rebuilt.endswith("-----END PRIVATE KEY-----\n"))
        self.assertEqual(tf.normalise_pem("x\\ny"), "x\ny\n")

    def test_token_is_es256_with_kid(self):
        import jwt
        from cryptography.hazmat.primitives import serialization
        from cryptography.hazmat.primitives.asymmetric import ec

        key = ec.generate_private_key(ec.SECP256R1())
        pem = key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                                serialization.NoEncryption()).decode()
        token = tf.AppStoreConnect("KEY123", "issuer-uuid", pem).token()
        header = jwt.get_unverified_header(token)
        self.assertEqual((header["alg"], header["kid"]), ("ES256", "KEY123"))
        claims = jwt.decode(token, key.public_key(), algorithms=["ES256"], audience="appstoreconnect-v1")
        self.assertEqual(claims["iss"], "issuer-uuid")
        self.assertLessEqual(claims["exp"] - claims["iat"], 20 * 60)


class FakeGitHub:
    repository = "owner/repo"

    def __init__(self):
        self.calls = []

    def call(self, method, path, payload=None, params=None):
        self.calls.append((method, path, payload))
        if path == "/pulls" and method == "POST":
            return {"number": 42}
        return {}


class Finish(unittest.TestCase):
    """`finish` against a real git repository in a temp dir."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.remote = self.root / "remote.git"
        self.work = self.root / "work"
        run = lambda *a, cwd=None: subprocess.run(a, cwd=cwd, check=True, capture_output=True)
        run("git", "init", "--bare", "-q", str(self.remote))
        run("git", "init", "-q", "-b", "main", str(self.work))
        (self.work / "FlightDeck").mkdir()
        (self.work / "FlightDeck" / "App.swift").write_text("let a = 1\n")
        (self.work / ".github" / "workflows").mkdir(parents=True)
        (self.work / ".github" / "workflows" / "ci.yml").write_text("on: push\n")
        (self.work / ".gitignore").write_text(".testflight-feedback/\n")
        for args in (("config", "user.email", "t@t"), ("config", "user.name", "t"),
                     ("add", "-A"), ("commit", "-qm", "init"),
                     ("remote", "add", "origin", str(self.remote)), ("push", "-q", "origin", "main")):
            run("git", *args, cwd=self.work)
        self.cwd = os.getcwd()
        os.chdir(self.work)
        self.fake = FakeGitHub()
        self.patch = mock.patch.object(tf, "GitHub", lambda *a: self.fake)
        self.patch.start()
        os.environ.update(GITHUB_TOKEN="t", GITHUB_REPOSITORY="owner/repo")
        self.folder = Path(".testflight-feedback/ID1")
        self.folder.mkdir(parents=True)

    def tearDown(self):
        self.patch.stop()
        os.chdir(self.cwd)
        self.tmp.cleanup()

    def args(self):
        return tf.main.__globals__["argparse"].Namespace(id="ID1", issue=7, branch="testflight/x", base="main")

    def test_protected_edits_are_dropped_and_the_rest_becomes_a_pr(self):
        Path("FlightDeck/App.swift").write_text("let a = 2\n")
        Path("FlightDeck/New.swift").write_text("struct New {}\n")
        Path(".github/workflows/ci.yml").write_text("on: [push, pull_request]\n")
        Path(".github/workflows/evil.yml").write_text("steps: []\n")
        Path("codemagic.yaml").write_text("x: 1\n")
        (self.folder / "SUMMARY.md").write_text("Fix the SNA anchor\n\nIt anchored on SFO.\n")

        self.assertEqual(tf.finish(self.args()), 0)

        branch_files = subprocess.run(["git", "ls-tree", "-r", "--name-only", "testflight/x"],
                                      cwd=self.remote, capture_output=True, text=True).stdout.split()
        self.assertIn("FlightDeck/New.swift", branch_files)
        self.assertNotIn(".github/workflows/evil.yml", branch_files)
        self.assertNotIn("codemagic.yaml", branch_files)
        ci = subprocess.run(["git", "show", "testflight/x:.github/workflows/ci.yml"],
                            cwd=self.remote, capture_output=True, text=True).stdout
        self.assertEqual(ci, "on: push\n")

        pr = next(p for m, path, p in self.fake.calls if path == "/pulls")
        self.assertEqual(pr["title"], "Fix the SNA anchor")
        self.assertIn("Fixes #7", pr["body"])
        self.assertIn("`.github/workflows/evil.yml`", pr["body"])
        self.assertTrue(any(path == "/issues/7/comments" for _, path, _ in self.fake.calls))

    def test_no_changes_explains_on_the_issue_without_pushing(self):
        (self.folder / "SUMMARY.md").write_text("Not actionable\n\nNeed to know which flight.\n")
        self.assertEqual(tf.finish(self.args()), 0)
        comment = next(p for m, path, p in self.fake.calls if path == "/issues/7/comments")
        self.assertIn("Need to know which flight.", comment["body"])
        self.assertFalse(any(path == "/pulls" for _, path, _ in self.fake.calls))
        heads = subprocess.run(["git", "branch", "--list", "testflight/x"], cwd=self.remote,
                               capture_output=True, text=True).stdout
        self.assertEqual(heads.strip(), "")

    def test_only_protected_changes_counts_as_no_change(self):
        Path("scripts").mkdir()
        Path("scripts/steal.sh").write_text("curl evil\n")
        self.assertEqual(tf.finish(self.args()), 0)
        self.assertFalse(Path("scripts/steal.sh").exists())
        self.assertFalse(any(path == "/pulls" for _, path, _ in self.fake.calls))


class Unconfigured(unittest.TestCase):
    def test_sweep_without_secrets_is_a_quiet_no_op(self):
        with mock.patch.dict(os.environ, {"ASC_KEY_ID": "", "GITHUB_OUTPUT": ""}, clear=False):
            args = tf.main.__globals__["argparse"].Namespace(id="", kind=None, days=3, max_new=5)
            self.assertEqual(tf.collect(args), 0)

    def test_dispatch_without_secrets_fails_loudly(self):
        with mock.patch.dict(os.environ, {"ASC_KEY_ID": ""}, clear=False):
            args = tf.main.__globals__["argparse"].Namespace(id="X1", kind="crash", days=3, max_new=5)
            with self.assertRaises(SystemExit):
                tf.collect(args)


class Protection(unittest.TestCase):
    def test_paths(self):
        for path in (".github/workflows/x.yml", "relay/src/index.js", "scripts/a.py",
                     "codemagic.yaml", "FlightDeck.xcodeproj/project.pbxproj", ".claude/settings.json"):
            self.assertTrue(tf.is_protected(path), path)
        for path in ("FlightDeck/Views/A.swift", "docs/x.md", "README.md", ".claude/skills/flightdeck/SKILL.md"):
            self.assertFalse(tf.is_protected(path), path)


if __name__ == "__main__":
    unittest.main()
