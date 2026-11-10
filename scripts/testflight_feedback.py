#!/usr/bin/env python3
"""TestFlight feedback → GitHub issue → Claude fix → pull request.

Runs inside GitHub Actions (see .github/workflows/testflight-feedback.yml and
docs/feedback-autofix.md). Standard library plus PyJWT for the App Store
Connect token. Subcommands:

  collect           Gather work for Claude, in one of three modes:
                      --kind/--id   one submission, as the relay dispatches it
                      --issue N     redo an existing issue, adding the
                                    developer's comments on it and on its PR
                      (neither)     sweep the last --days days
                    For each item: save the report, screenshots and crash log
                    under .testflight-feedback/<id>/ for Claude, and (new
                    feedback only) open a GitHub issue. Writes `items` (JSON)
                    to $GITHUB_OUTPUT for the fix and publish matrices.
  publish           Apply the patch Claude's job produced — only paths on the
                    allowlist, never symlinks — commit it on the fix branch,
                    push, and open or update the PR. If there's nothing to
                    apply, post Claude's explanation on the issue instead.
  register-webhook  Create (or update) the App Store Connect webhook that
                    points at the relay, ping it, and wait for the result.
  deliveries        Show the webhook's most recent deliveries — the first
                    place to look when feedback doesn't trigger a run.

Environment:
  ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY   App Store Connect API key
  ASC_APP_ID                                   the app's Apple ID (numeric)
  GITHUB_TOKEN, GITHUB_REPOSITORY              provided by Actions
  APPLE_WEBHOOK_SECRET                         register-webhook only
  FEEDBACK_PUBLIC_SCREENSHOTS=true             opt in to posting screenshots
                                               in a *public* repo's issues

Trust model. Everything a tester wrote is data, not instructions. Claude reads
it in a job whose GitHub token is read-only and whose tools can only edit
allowlisted folders. Its output leaves that job as a patch file, and `publish`
— running from a fresh checkout of main in a separate job — is the only thing
holding a write token. It applies the patch only to ALLOWED paths, refuses
anything that looks like a credential, and never runs code from the patch.
"""
from __future__ import annotations

import argparse
import base64
import datetime as dt
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ASC_API = "https://api.appstoreconnect.apple.com"
GITHUB_API = "https://api.github.com"

LABEL = "testflight-feedback"
ASSETS_BRANCH = "testflight-feedback-assets"
WORK_DIR = Path(".testflight-feedback")
WEBHOOK_NAME = "FlightDeck feedback relay"
WEBHOOK_EVENTS = [
    "BETA_FEEDBACK_SCREENSHOT_SUBMISSION_CREATED",
    "BETA_FEEDBACK_CRASH_SUBMISSION_CREATED",
]

KINDS = {
    "screenshot": "betaFeedbackScreenshotSubmissions",
    "crash": "betaFeedbackCrashSubmissions",
}

# The only places a feedback-driven change may land. Everything else in a
# patch is dropped and named in the PR.
ALLOWED = ("FlightDeck/", "docs/", ".claude/skills/")

# Checked as well, in case an allowlist entry is ever widened: these steer CI,
# secrets, signing, or every future Claude session in this repo.
PROTECTED = (
    ".github/",
    "relay/",
    "scripts/",
    "codemagic.yaml",
    "FlightDeck.xcodeproj/",
    "FlightDeck.xcworkspace/",
    ".claude/settings",
    ".claude/commands/",
    ".claude/agents/",
    "CLAUDE.md",
    ".mcp.json",
    ".gitattributes",
    ".gitmodules",
)

# Anything shaped like these never leaves the fix job: not in a commit, not in
# a comment. The fix job holds the Claude credential, and its summary is
# posted publicly.
SECRET_PATTERNS = [
    re.compile(r"\bgh[pousr]_[A-Za-z0-9]{30,}"),
    re.compile(r"\bgithub_pat_[A-Za-z0-9_]{30,}"),
    re.compile(r"\bsk-ant-[A-Za-z0-9_-]{20,}"),
    re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
    re.compile(r"x-access-token:[^@\s]+@"),
]

CRASH_LOG_LINES_IN_ISSUE = 120
# A leading "-" is refused so an id can never be read as a command-line flag.
ID_PATTERN = re.compile(r"^[A-Za-z0-9_][A-Za-z0-9_-]{0,127}$")
MARKER = re.compile(r"<!-- testflight-feedback-id: ([A-Za-z0-9_-]+)(?: kind: (screenshot|crash))? -->")
TRUSTED_AUTHORS = {"OWNER", "MEMBER", "COLLABORATOR"}


# ---------------------------------------------------------------- HTTP ----


class HTTPError(RuntimeError):
    def __init__(self, status: int, url: str, body: str):
        super().__init__(f"HTTP {status} from {url}: {body[:500]}")
        self.status = status
        self.body = body


def http(method: str, url: str, headers: dict, body: bytes | None = None,
         retries: int = 3) -> tuple[int, bytes]:
    """One request with retries on 429/5xx. Raises HTTPError on other failures."""
    for attempt in range(retries):
        request = urllib.request.Request(url, data=body, method=method, headers=headers)
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                return response.status, response.read()
        except urllib.error.HTTPError as error:
            payload = error.read().decode("utf-8", "replace")
            if error.code in (429, 500, 502, 503, 504) and attempt < retries - 1:
                time.sleep(2 ** attempt * 3)
                continue
            raise HTTPError(error.code, url, payload) from None
        except urllib.error.URLError:
            if attempt < retries - 1:
                time.sleep(2 ** attempt * 3)
                continue
            raise
    raise RuntimeError("unreachable")


def json_request(method: str, url: str, headers: dict, payload=None):
    body = None
    if payload is not None:
        body = json.dumps(payload).encode()
        headers = {**headers, "Content-Type": "application/json"}
    _, raw = http(method, url, headers, body)
    return json.loads(raw) if raw.strip() else {}


# ------------------------------------------------- App Store Connect -------


class AppStoreConnect:
    """Minimal client. Tokens live 20 minutes at most; mint one per call."""

    def __init__(self, key_id: str, issuer_id: str, private_key: str):
        self.key_id = key_id
        self.issuer_id = issuer_id
        self.private_key = normalise_pem(private_key)

    def token(self) -> str:
        import jwt  # PyJWT[crypto]; imported late so `publish` doesn't need it

        now = int(time.time())
        return jwt.encode(
            {"iss": self.issuer_id, "iat": now, "exp": now + 15 * 60, "aud": "appstoreconnect-v1"},
            self.private_key,
            algorithm="ES256",
            headers={"kid": self.key_id, "typ": "JWT"},
        )

    def request(self, method: str, path: str, params: dict | None = None, payload=None):
        url = path if path.startswith("https://") else ASC_API + path
        if params:
            url += "?" + urllib.parse.urlencode(params)
        headers = {"Authorization": f"Bearer {self.token()}", "Accept": "application/json"}
        return json_request(method, url, headers, payload)

    def get(self, path, params=None):
        return self.request("GET", path, params)


def asc_from_env() -> AppStoreConnect:
    return AppStoreConnect(env("ASC_KEY_ID"), env("ASC_ISSUER_ID"), env("ASC_PRIVATE_KEY"))


def normalise_pem(text: str) -> str:
    """Secrets pasted through web forms sometimes arrive with literal `\\n`s or
    without the line breaks entirely. Rebuild a PEM PyJWT will accept."""
    text = text.strip().replace("\\n", "\n").replace("\r", "")
    if "\n" in text:
        return text + "\n"
    match = re.match(r"-----BEGIN ([A-Z ]+)-----(.*)-----END \1-----", text)
    if not match:
        return text
    label, body = match.group(1), re.sub(r"\s+", "", match.group(2))
    lines = [body[i:i + 64] for i in range(0, len(body), 64)]
    return f"-----BEGIN {label}-----\n" + "\n".join(lines) + f"\n-----END {label}-----\n"


SUBMISSION_PARAMS = {"include": "build", "fields[builds]": "version,uploadedDate"}


def fetch_submission(asc: AppStoreConnect, kind: str, submission_id: str) -> dict:
    document = asc.get(f"/v1/{KINDS[kind]}/{submission_id}", SUBMISSION_PARAMS)
    return flatten(document["data"], document.get("included", []), kind)


def list_recent_submissions(asc: AppStoreConnect, app_id: str, kind: str,
                            since: dt.datetime) -> list[dict]:
    """Newest first, stopping at the first one older than `since`."""
    found: list[dict] = []
    url = (f"{ASC_API}/v1/apps/{app_id}/{KINDS[kind]}?"
           + urllib.parse.urlencode({**SUBMISSION_PARAMS, "sort": "-createdDate", "limit": "50"}))
    while url:
        document = asc.request("GET", url)
        for item in document.get("data", []):
            submission = flatten(item, document.get("included", []), kind)
            if submission["created"] and submission["created"] < since:
                return found
            found.append(submission)
        url = document.get("links", {}).get("next")
    return found


def flatten(item: dict, included: list[dict], kind: str) -> dict:
    """One submission as a plain dict, with its build resolved.

    Deliberately leaves out the tester's name and email: issues may be public,
    and on a solo project the tester is you anyway."""
    attributes = item.get("attributes", {}) or {}
    relationships = item.get("relationships", {}) or {}
    lookup = {(inc.get("type"), inc.get("id")): inc.get("attributes", {}) or {} for inc in included}
    build_ref = (relationships.get("build") or {}).get("data") or {}
    build = lookup.get((build_ref.get("type"), build_ref.get("id")), {})
    return {
        "id": item["id"],
        "kind": kind,
        "created": parse_time(attributes.get("createdDate")),
        "comment": (attributes.get("comment") or "").strip(),
        "build": build.get("version") or "",
        "device": attributes.get("deviceModel") or "",
        "os": attributes.get("osVersion") or "",
        "locale": attributes.get("locale") or "",
        "time_zone": attributes.get("timeZone") or "",
        "connection": attributes.get("connectionType") or "",
        "battery": attributes.get("batteryPercentage"),
        "uptime_ms": attributes.get("appUptimeInMilliseconds"),
        "screen": _screen(attributes),
        "screenshots": [s for s in attributes.get("screenshots") or [] if s.get("url")],
    }


def _screen(attributes: dict) -> str:
    w, h = attributes.get("screenWidthInPoints"), attributes.get("screenHeightInPoints")
    return f"{w}×{h} pt" if w and h else ""


def parse_time(value: str | None) -> dt.datetime | None:
    if not value:
        return None
    try:
        return dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def fetch_crash_log(asc: AppStoreConnect, submission_id: str) -> str:
    try:
        document = asc.get(f"/v1/betaFeedbackCrashSubmissions/{submission_id}/crashLog")
    except HTTPError as error:
        if error.status == 404:
            return ""
        raise
    return ((document.get("data") or {}).get("attributes") or {}).get("logText") or ""


def download(url: str, width: int | None = None, height: int | None = None) -> bytes:
    # Some App Store Connect image URLs are templates ("…/{w}x{h}bb.{f}").
    url = url.replace("{w}", str(width or 1290)).replace("{h}", str(height or 2796)).replace("{f}", "png")
    _, data = http("GET", url, {"User-Agent": "flightdeck-feedback"})
    return data


def image_extension(data: bytes) -> str:
    if data.startswith(b"\x89PNG"):
        return "png"
    if data.startswith(b"\xff\xd8"):
        return "jpg"
    if data[4:12] in (b"ftypheic", b"ftypheix", b"ftypmif1"):
        return "heic"
    return "png"


# ------------------------------------------------------------- GitHub ------


class GitHub:
    def __init__(self, token: str, repository: str):
        self.repository = repository
        self.headers = {
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "flightdeck-feedback",
        }

    def call(self, method: str, path: str, payload=None, params: dict | None = None):
        url = f"{GITHUB_API}/repos/{self.repository}{path}"
        if params:
            url += "?" + urllib.parse.urlencode(params)
        return json_request(method, url, self.headers, payload)

    def is_public(self) -> bool:
        repo = json_request("GET", f"{GITHUB_API}/repos/{self.repository}", self.headers)
        return not repo.get("private", False)

    def ensure_label(self):
        try:
            self.call("POST", "/labels", {"name": LABEL, "color": "0e8a16",
                                         "description": "Filed automatically from TestFlight feedback"})
        except HTTPError as error:
            if error.status != 422:  # 422 = already exists
                raise

    def filed_ids(self) -> set[str]:
        """Feedback IDs that already have an issue, open or closed."""
        ids: set[str] = set()
        page = 1
        while True:
            issues = self.call("GET", "/issues", params={
                "labels": LABEL, "state": "all", "per_page": "100", "page": str(page)})
            for issue in issues:
                ids.update(match[0] for match in MARKER.findall(issue.get("body") or ""))
            if len(issues) < 100:
                return ids
            page += 1

    def branch_exists(self, branch: str) -> bool:
        try:
            self.call("GET", f"/branches/{urllib.parse.quote(branch, safe='')}")
            return True
        except HTTPError as error:
            if error.status == 404:
                return False
            raise

    def open_pr_for(self, branch: str) -> dict | None:
        owner = self.repository.split("/")[0]
        prs = self.call("GET", "/pulls", params={"head": f"{owner}:{branch}", "state": "open"})
        return prs[0] if prs else None

    def trusted_comments(self, number: int) -> list[dict]:
        comments, page = [], 1
        while True:
            batch = self.call("GET", f"/issues/{number}/comments",
                              params={"per_page": "100", "page": str(page)})
            comments += [c for c in batch
                         if c.get("author_association") in TRUSTED_AUTHORS
                         and (c.get("user") or {}).get("type") != "Bot"]
            if len(batch) < 100:
                return comments
            page += 1

    def ensure_assets_branch(self):
        """An orphan branch holding only screenshots, so it never carries (or
        triggers builds of) the app itself."""
        try:
            self.call("GET", f"/git/ref/heads/{ASSETS_BRANCH}")
            return
        except HTTPError as error:
            if error.status != 404:
                raise
        readme = b"Screenshots from TestFlight feedback, referenced by issues. Never merged.\n"
        blob = self.call("POST", "/git/blobs", {"content": base64.b64encode(readme).decode(),
                                               "encoding": "base64"})
        tree = self.call("POST", "/git/trees", {"tree": [
            {"path": "README.md", "mode": "100644", "type": "blob", "sha": blob["sha"]}]})
        commit = self.call("POST", "/git/commits", {"message": "Start screenshot store",
                                                   "tree": tree["sha"], "parents": []})
        self.call("POST", "/git/refs", {"ref": f"refs/heads/{ASSETS_BRANCH}", "sha": commit["sha"]})

    def put_file(self, path: str, content: bytes, message: str) -> str:
        """Commit one file to the assets branch; returns a URL that renders in
        issues for anyone who can read the repo. Retries the race where two
        runs commit to the branch at once."""
        payload = {"message": message, "branch": ASSETS_BRANCH,
                   "content": base64.b64encode(content).decode()}
        for attempt in range(4):
            try:
                existing = self.call("GET", f"/contents/{path}", params={"ref": ASSETS_BRANCH})
                payload["sha"] = existing["sha"]
            except HTTPError as error:
                if error.status != 404:
                    raise
            try:
                self.call("PUT", f"/contents/{path}", payload)
                break
            except HTTPError as error:
                if error.status not in (409, 422) or attempt == 3:
                    raise
                time.sleep(1 + attempt)
        return f"https://github.com/{self.repository}/blob/{ASSETS_BRANCH}/{path}?raw=true"


# --------------------------------------------------------------- collect ---


def issue_title(submission: dict) -> str:
    first_line = next((line.strip() for line in submission["comment"].splitlines() if line.strip()), "")
    if submission["kind"] == "crash":
        subject = f"Crash: {first_line}" if first_line else f"Crash on {submission['device'] or 'device'}"
    else:
        subject = first_line or "Screenshot feedback (no comment)"
    subject = re.sub(r"\s+", " ", subject)
    if len(subject) > 72:
        subject = subject[:71].rstrip() + "…"
    return f"TestFlight: {subject}"


def quote(text: str) -> str:
    if not text:
        return "> _(no comment)_"
    return "\n".join("> " + line if line.strip() else ">" for line in text.splitlines())


def details_table(submission: dict, *, public: bool) -> str:
    rows = [
        ("Submitted", submission["created"].strftime("%Y-%m-%d %H:%M UTC") if submission["created"] else ""),
        ("Build", submission["build"]),
        ("Device", submission["device"]),
        ("iOS", submission["os"]),
        ("Screen", submission["screen"]),
        # Locale and time zone narrow down where you are; useful to Claude,
        # not something to post on a public issue.
        ("Locale / time zone", "" if public else " · ".join(filter(None, [submission["locale"],
                                                                          submission["time_zone"]]))),
        ("Connection", submission["connection"]),
        ("Battery", f"{submission['battery']}%" if submission["battery"] is not None else ""),
        ("App running for", _uptime(submission["uptime_ms"])),
    ]
    lines = ["| | |", "|---|---|"]
    lines += [f"| {k} | {v} |" for k, v in rows if v]
    return "\n".join(lines)


def _uptime(ms) -> str:
    if not ms:
        return ""
    seconds = int(ms) // 1000
    minutes, seconds = divmod(seconds, 60)
    hours, minutes = divmod(minutes, 60)
    return f"{hours}h {minutes}m" if hours else f"{minutes}m {seconds}s"


def issue_body(submission: dict, images: list[str], withheld: int, crash_log: str, *, public: bool) -> str:
    kind = "Crash report" if submission["kind"] == "crash" else "Screenshot feedback"
    parts = [f"<!-- testflight-feedback-id: {submission['id']} kind: {submission['kind']} -->",
             f"**{kind}** from TestFlight", "", quote(submission["comment"]), "",
             details_table(submission, public=public)]
    if images:
        parts += ["", "### Screenshots", ""]
        parts += [f"![screenshot {i + 1}]({src})" for i, src in enumerate(images)]
    if withheld:
        parts += ["", f"_{withheld} screenshot(s) not posted because this repository is public. "
                      f"Claude still sees them during the fix._"]
    if crash_log:
        lines = crash_log.splitlines()
        shown = "\n".join(lines[:CRASH_LOG_LINES_IN_ISSUE])
        more = len(lines) - CRASH_LOG_LINES_IN_ISSUE
        note = f"\n… {more} more lines in Claude's copy." if more > 0 else ""
        parts += ["", "<details><summary>Crash log</summary>", "", "```", shown, "```", note, "</details>"]
    parts += ["", "---",
              "_Filed automatically from TestFlight. Claude is working on a fix — a pull request "
              "will be linked here. Reply `@claude …` to send it back with more detail._"]
    return "\n".join(parts) + "\n"


def claude_report(submission: dict, images: list[str], crash_log: str, follow_ups: list[dict]) -> str:
    """What Claude reads: the full report with local paths, plus anything the
    developer has said since, marked as such."""
    kind = "Crash report" if submission["kind"] == "crash" else "Screenshot feedback"
    parts = [f"**{kind}** from TestFlight", "", quote(submission["comment"]), "",
             details_table(submission, public=False)]
    if images:
        parts += ["", "Screenshots in this folder: " + ", ".join(f"`{name}`" for name in images)]
    if crash_log:
        parts += ["", "Full crash log: `crash.log` in this folder."]
    if follow_ups:
        parts += ["", "## Follow-up from the developer (oldest first)", "",
                  "These came after the first attempt. The newest one is what was just asked for; "
                  "the current fix branch is already checked out, so build on it."]
        for comment in follow_ups:
            parts += ["", f"**{comment['created_at']}:**", quote((comment.get("body") or "").strip())]
    return "\n".join(parts) + "\n"


def item_for(submission: dict, issue: int, github: GitHub) -> dict:
    branch = f"testflight/{submission['kind']}-{submission['id'][:24].lower()}"
    start = branch if github.branch_exists(branch) else "main"
    return {"id": submission["id"], "kind": submission["kind"], "issue": issue,
            "branch": branch, "start": start}


def save_for_claude(asc: AppStoreConnect, submission: dict, follow_ups: list[dict]) -> tuple[list, str]:
    """Download screenshots and crash log into the work folder. Returns the
    screenshot bytes (for the issue) and the crash log."""
    folder = WORK_DIR / submission["id"]
    folder.mkdir(parents=True, exist_ok=True)
    images: list[tuple[str, bytes]] = []
    for index, shot in enumerate(submission["screenshots"], start=1):
        try:
            data = download(shot["url"], shot.get("width"), shot.get("height"))
        except Exception as error:  # an expired link must not lose the report
            print(f"{submission['id']}: screenshot {index} unavailable ({error})", file=sys.stderr)
            continue
        name = f"screenshot-{index}.{image_extension(data)}"
        (folder / name).write_bytes(data)
        images.append((name, data))
    crash_log = fetch_crash_log(asc, submission["id"]) if submission["kind"] == "crash" else ""
    if crash_log:
        (folder / "crash.log").write_text(crash_log)
    (folder / "feedback.md").write_text(
        claude_report(submission, [name for name, _ in images], crash_log, follow_ups))
    return images, crash_log


def file_new(asc: AppStoreConnect, github: GitHub, submission: dict, public: bool) -> dict:
    images, crash_log = save_for_claude(asc, submission, [])
    post_images = not public or os.environ.get("FEEDBACK_PUBLIC_SCREENSHOTS", "").lower() == "true"
    urls = []
    if images and post_images:
        github.ensure_assets_branch()
        for name, data in images:
            urls.append(github.put_file(f"feedback/{submission['id']}/{name}", data,
                                        f"TestFlight feedback {submission['id']}: {name}"))
    issue = github.call("POST", "/issues", {
        "title": issue_title(submission),
        "body": issue_body(submission, urls, 0 if post_images else len(images), crash_log, public=public),
        "labels": [LABEL],
    })
    print(f"{submission['id']}: filed #{issue['number']}")
    return item_for(submission, issue["number"], github)


def redo_issue(asc: AppStoreConnect, github: GitHub, number: int) -> dict:
    """Re-run an existing feedback issue, with the developer's comments on the
    issue and on its PR as extra context."""
    issue = github.call("GET", f"/issues/{number}")
    match = MARKER.search(issue.get("body") or "")
    if not match:
        raise SystemExit(f"Issue #{number} has no TestFlight feedback marker.")
    feedback_id, kind = match.group(1), match.group(2)
    if kind:
        submission = fetch_submission(asc, kind, feedback_id)
    else:  # issues filed before the marker carried the kind
        submission = None
        for candidate in KINDS:
            try:
                submission = fetch_submission(asc, candidate, feedback_id)
                break
            except HTTPError as error:
                if error.status != 404:
                    raise
        if submission is None:
            raise SystemExit(f"Feedback {feedback_id} no longer exists in App Store Connect.")
    item = item_for(submission, number, github)
    follow_ups = github.trusted_comments(number)
    pr = github.open_pr_for(item["branch"])
    if pr:
        follow_ups += github.trusted_comments(pr["number"])
    follow_ups.sort(key=lambda c: c.get("created_at") or "")
    save_for_claude(asc, submission, follow_ups)
    print(f"#{number}: re-running {feedback_id} with {len(follow_ups)} follow-up comment(s), "
          f"starting from {item['start']}")
    return item


def collect(args) -> int:
    required = ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_PRIVATE_KEY", "ASC_APP_ID")
    if not (args.id or args.issue) and not all(os.environ.get(n, "").strip() for n in required):
        # The daily sweep starts running the moment this workflow is merged,
        # which is before anyone has added the secrets. Don't turn that gap
        # into a failure email every day.
        print("::notice::App Store Connect secrets aren't set yet; skipping the sweep. "
              "See docs/feedback-autofix.md.")
        write_output("items", "[]")
        return 0

    asc = asc_from_env()
    github = GitHub(env("GITHUB_TOKEN"), env("GITHUB_REPOSITORY"))
    items: list[dict] = []
    failures = 0
    try:
        if args.issue:
            items.append(redo_issue(asc, github, args.issue))
            return 0

        if args.id:
            if args.kind not in KINDS or not ID_PATTERN.match(args.id):
                print(f"Refusing kind={args.kind!r} id={args.id!r}", file=sys.stderr)
                return 2
            submissions = [fetch_submission(asc, args.kind, args.id)]
        else:
            since = dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=args.days)
            submissions = []
            for kind in KINDS:
                submissions += list_recent_submissions(asc, env("ASC_APP_ID"), kind, since)
            submissions.sort(key=lambda s: s["created"] or dt.datetime.min.replace(tzinfo=dt.timezone.utc))
            print(f"Found {len(submissions)} submission(s) in the last {args.days} day(s).")

        github.ensure_label()
        public = github.is_public()
        for submission in submissions:
            if len(items) >= args.max_new:
                print(f"{submission['id']}: over the per-run limit of {args.max_new}; "
                      f"run again to pick it up.")
                continue
            # Re-read just before filing: a webhook run and the sweep can overlap.
            if submission["id"] in github.filed_ids():
                print(f"{submission['id']}: already filed, skipping.")
                continue
            try:
                items.append(file_new(asc, github, submission, public))
            except Exception as error:
                # One bad submission must not strand the ones already filed:
                # those still go on to the fix job.
                failures += 1
                print(f"::error::{submission['id']}: {error}", file=sys.stderr)
        print(f"Filed {len(items)} new issue(s).")
        return 1 if failures and not items else 0
    finally:
        write_output("items", json.dumps(items))


# --------------------------------------------------------------- publish ---


def git(*args: str, check: bool = True) -> str:
    result = subprocess.run(["git", *args], check=check, capture_output=True, text=True)
    return result.stdout


def is_protected(path: str) -> bool:
    return any(path == p.rstrip("/") or path.startswith(p) for p in PROTECTED)


def is_allowed(path: str) -> bool:
    if path.startswith('"') or any(ch in path for ch in "*?[\\"):
        return False  # git quotes odd names; refuse rather than guess
    if any(part in ("", ".", "..") for part in path.split("/")):
        return False
    return path.startswith(ALLOWED) and not is_protected(path)


def patch_entries(patch: str) -> list[dict]:
    """One entry per file in a git patch: every path it names (both sides of a
    rename or copy), and whether it creates or keeps a symlink or submodule."""
    entries: list[dict] = []
    for line in patch.splitlines():
        if line.startswith("diff --git "):
            match = re.match(r"diff --git a/(.+) b/(.+)$", line)
            names = set(match.groups()) if match else {line[len("diff --git "):]}
            entries.append({"paths": names, "special": False})
        elif not entries:
            continue
        elif line.startswith(("rename from ", "rename to ", "copy from ", "copy to ")):
            entries[-1]["paths"].add(line.split(" ", 2)[2])
        elif re.match(r"(new file mode|new mode|old mode|deleted file mode|index [0-9a-f]+\.\.[0-9a-f]+) "
                      r"(120000|160000)$", line):
            entries[-1]["special"] = True
    return entries


def split_patch(patch: str) -> tuple[list[str], list[str]]:
    """(paths to apply, paths to drop). An entry is applied only if every path
    it names is allowed: a rename from a protected file into FlightDeck/ is
    dropped whole, never applied as "add the new name" while git quietly
    deletes the old one."""
    keep: set[str] = set()
    drop: set[str] = set()
    for entry in patch_entries(patch):
        if not entry["special"] and all(is_allowed(p) for p in entry["paths"]):
            keep |= entry["paths"]
        else:
            drop |= entry["paths"]
    return sorted(keep), sorted(drop - keep)


def find_secret(text: str) -> str | None:
    for pattern in SECRET_PATTERNS:
        if pattern.search(text):
            return pattern.pattern
    return None


def read_summary(bundle: Path, issue: int) -> tuple[str, str]:
    summary_file = bundle / "SUMMARY.md"
    text = summary_file.read_text(errors="replace").strip() if summary_file.exists() else ""
    if not text:
        return f"Fix TestFlight feedback (#{issue})", "_Claude didn't write a summary._"
    first, _, rest = text.partition("\n")
    title = re.sub(r"^#+\s*", "", first).strip().strip("*") or f"Fix TestFlight feedback (#{issue})"
    if len(title) > 72:
        title = title[:71].rstrip() + "…"
    return title, rest.strip() or text


def publish(args) -> int:
    github = GitHub(env("GITHUB_TOKEN"), env("GITHUB_REPOSITORY"))

    def tell_issue(text: str):
        github.call("POST", f"/issues/{args.issue}/comments", {"body": f"{text}\n\n[Workflow run]({run_url()})"})

    try:
        return _publish(args, github, tell_issue)
    except Exception as error:
        tell_issue(f"Publishing the fix failed: `{type(error).__name__}`. See the workflow run.")
        raise


def _publish(args, github: GitHub, tell_issue) -> int:
    bundle = Path(args.bundle)
    patch_file = bundle / "patch.diff"
    if not patch_file.exists():
        tell_issue("The fix job didn't produce a result (it may have failed or run out of turns). "
                   "Reply `@claude try again` to retry.")
        return 1

    title, summary = read_summary(bundle, args.issue)
    patch = patch_file.read_bytes()
    patch_text = patch.decode("utf-8", "replace")
    leaked = find_secret(summary) or find_secret(patch_text)
    if leaked:
        # Not posted anywhere: the summary and the diff are both withheld.
        tell_issue("Claude's result was withheld because it contained something shaped like a "
                   "credential. Nothing was committed. Check the workflow run.")
        print(f"::error::Result matched secret pattern {leaked}", file=sys.stderr)
        return 1

    if not patch_text.strip():
        tell_issue(f"Claude looked into this and didn't change any code.\n\n{summary}")
        print("No code changes; explained on the issue.")
        return 0

    allowed, dropped = split_patch(patch_text)
    note = ""
    if dropped:
        note = ("\n\n> [!WARNING]\n> Left out because feedback-driven changes may only touch "
                + ", ".join(f"`{a}`" for a in ALLOWED) + " (and never as symlinks): "
                + ", ".join(f"`{p}`" for p in dropped))
    if not allowed:
        tell_issue(f"Claude's change only touched paths it isn't allowed to change, so nothing "
                   f"was committed.\n\n{summary}{note}")
        return 0

    # Work from the fix branch if it exists, otherwise from main — never from
    # whatever the patch's own checkout looked like.
    git("fetch", "--quiet", "origin", args.start)
    git("checkout", "--quiet", "-B", "feedback-publish", "FETCH_HEAD")
    patch_file_abs = str(patch_file.resolve())
    includes = [f"--include={p}" for p in allowed]
    git("apply", "--index", "--whitespace=nowarn", *includes, patch_file_abs)
    # --no-renames lists both sides of any rename, so a deletion can't hide.
    staged = set(filter(None, git("diff", "--cached", "--name-only", "--no-renames", "-z").split("\0")))
    if not staged or not staged <= set(allowed):
        raise RuntimeError(f"staged paths {sorted(staged)} don't match the allowed set")

    git("config", "user.name", "github-actions[bot]")
    git("config", "user.email", "41898282+github-actions[bot]@users.noreply.github.com")
    git("commit", "--quiet", "-m", title, "-m", f"Fixes #{args.issue} (TestFlight feedback {args.id}).")
    if args.start == args.branch:
        git("push", "--quiet", "origin", f"HEAD:refs/heads/{args.branch}")
    else:
        # A fresh attempt from main replaces whatever an earlier one left.
        git("push", "--quiet", "--force", "origin", f"HEAD:refs/heads/{args.branch}")

    body = (f"{summary}{note}\n\n---\nFixes #{args.issue} — filed from TestFlight feedback "
            f"`{args.id}`.\n\nWritten by Claude from the tester's report. It couldn't build iOS, so "
            f"**check Codemagic's compile check** and try it on a phone before merging. "
            f"Reply `@claude …` here to send it back with changes.\n\n[Workflow run]({run_url()})")
    existing = github.open_pr_for(args.branch)
    if existing:
        github.call("POST", f"/issues/{existing['number']}/comments",
                    {"body": f"**Updated:** {title}\n\n{summary}{note}\n\n[Workflow run]({run_url()})"})
        print(f"Updated PR #{existing['number']}")
        return 0
    try:
        pr = github.call("POST", "/pulls", {"title": title, "head": args.branch,
                                            "base": args.base, "body": body})
    except HTTPError as error:
        if error.status == 403:
            print("::error::GitHub refused to open the PR. Enable Settings → Actions → General → "
                  "'Allow GitHub Actions to create and approve pull requests'.", file=sys.stderr)
        raise
    try:
        github.call("POST", f"/issues/{pr['number']}/labels", {"labels": [LABEL]})
    except HTTPError:
        pass  # the label is a convenience; the PR stands without it
    github.call("POST", f"/issues/{args.issue}/comments", {"body": f"Proposed fix: #{pr['number']} — {title}"})
    print(f"Opened PR #{pr['number']}")
    return 0


def run_url() -> str:
    server = os.environ.get("GITHUB_SERVER_URL", "https://github.com")
    return f"{server}/{os.environ.get('GITHUB_REPOSITORY', '')}/actions/runs/{os.environ.get('GITHUB_RUN_ID', '')}"


# ------------------------------------------------------------- webhooks ----


def find_webhook(asc: AppStoreConnect, app_id: str) -> dict | None:
    existing = asc.get(f"/v1/apps/{app_id}/webhooks", {"limit": "50"}).get("data", [])
    return next((w for w in existing if (w.get("attributes") or {}).get("name") == WEBHOOK_NAME), None)


def register_webhook(args) -> int:
    asc = asc_from_env()
    app_id, secret = env("ASC_APP_ID"), env("APPLE_WEBHOOK_SECRET")
    url = args.url.strip()
    if not url.startswith("https://"):
        print("The relay URL must start with https://", file=sys.stderr)
        return 2

    attributes = {"name": WEBHOOK_NAME, "url": url, "secret": secret,
                  "eventTypes": WEBHOOK_EVENTS, "enabled": True}
    match = find_webhook(asc, app_id)
    if match:
        webhook_id = match["id"]
        asc.request("PATCH", f"/v1/webhooks/{webhook_id}", payload={
            "data": {"type": "webhooks", "id": webhook_id, "attributes": attributes}})
        print(f"Updated webhook {webhook_id} → {url}")
    else:
        created = asc.request("POST", "/v1/webhooks", payload={"data": {
            "type": "webhooks", "attributes": attributes,
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})
        webhook_id = created["data"]["id"]
        print(f"Created webhook {webhook_id} → {url}")

    pinged_at = dt.datetime.now(dt.timezone.utc) - dt.timedelta(seconds=5)
    asc.request("POST", "/v1/webhookPings", payload={"data": {
        "type": "webhookPings",
        "relationships": {"webhook": {"data": {"type": "webhooks", "id": webhook_id}}}}})
    print("Sent a test ping. Waiting for the delivery result…")
    for _ in range(12):
        time.sleep(5)
        rows = fetch_deliveries(asc, webhook_id, since=pinged_at)
        settled = [r for r in rows if r["state"] in ("SUCCEEDED", "FAILED")]
        if settled:
            print_deliveries(fetch_deliveries(asc, webhook_id))
            if settled[0]["state"] == "SUCCEEDED":
                print("\nThe relay answered the ping. Setup is complete.")
                return 0
            print("\nThe ping reached the relay but failed. If it says HTTP 401, the "
                  "APPLE_WEBHOOK_SECRET in GitHub and in Cloudflare differ.", file=sys.stderr)
            return 1
    print_deliveries(fetch_deliveries(asc, webhook_id))
    print("\nThe webhook is registered, but the ping's result hadn't arrived after a minute. "
          "Run this workflow again with action `deliveries` in a few minutes.", file=sys.stderr)
    return 1


def deliveries(args) -> int:
    asc = asc_from_env()
    match = find_webhook(asc, env("ASC_APP_ID"))
    if not match:
        print("No FlightDeck webhook is registered. Run the setup workflow with action `register`.")
        return 1
    print(f"Webhook {match['id']} → {(match.get('attributes') or {}).get('url')}\n")
    print_deliveries(fetch_deliveries(asc, match["id"]))
    return 0


def fetch_deliveries(asc: AppStoreConnect, webhook_id: str, since: dt.datetime | None = None) -> list[dict]:
    """Newest first — sorted here rather than trusting the API's order.

    Apple requires exactly one createdDate filter on this endpoint (HTTP 400
    PARAMETER_ERROR.INVALID without it), so "all recent" means the last 30 days.
    """
    if since is None:
        since = dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=30)
    params = {"limit": "20", "include": "event",
              "filter[createdDateGreaterThanOrEqualTo]": since.strftime("%Y-%m-%dT%H:%M:%S.000Z")}
    document = asc.get(f"/v1/webhooks/{webhook_id}/deliveries", params)
    events = {inc.get("id"): inc.get("attributes", {}) or {} for inc in document.get("included", [])}
    rows = []
    for row in document.get("data", []):
        a = row.get("attributes", {}) or {}
        event_id = (((row.get("relationships") or {}).get("event") or {}).get("data") or {}).get("id")
        event = events.get(event_id, {})
        rows.append({
            "created": a.get("createdDate") or "",
            "state": str(a.get("deliveryState") or "?"),
            "status": (a.get("response") or {}).get("httpStatusCode"),
            "event": "ping" if event.get("ping") else str(event.get("eventType") or ""),
            "error": a.get("errorMessage") or "",
        })
    rows.sort(key=lambda r: r["created"], reverse=True)
    return rows


def print_deliveries(rows: list[dict]):
    if not rows:
        print("No deliveries recorded yet.")
    for r in rows[:10]:
        print(f"{r['created']}  {r['state']:9}  HTTP {r['status'] if r['status'] is not None else '-'}  "
              f"{r['event']}  {r['error']}")


# ------------------------------------------------------------------ main ---


def env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        print(f"Missing environment variable {name}. See docs/feedback-autofix.md.", file=sys.stderr)
        sys.exit(2)
    return value


def write_output(name: str, value: str):
    path = os.environ.get("GITHUB_OUTPUT")
    if path:
        with open(path, "a") as handle:
            handle.write(f"{name}={value}\n")
    else:
        print(f"{name}={value}")


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)

    c = sub.add_parser("collect")
    c.add_argument("--kind", choices=sorted(KINDS), default=None)
    c.add_argument("--id", default="")
    c.add_argument("--issue", type=int, default=0)
    c.add_argument("--days", type=int, default=3)
    c.add_argument("--max-new", type=int, default=5,
                   help="cap on new issues (and Claude runs) per invocation")
    c.set_defaults(func=collect)

    p = sub.add_parser("publish")
    p.add_argument("--id", required=True)
    p.add_argument("--issue", type=int, required=True)
    p.add_argument("--branch", required=True)
    p.add_argument("--start", required=True)
    p.add_argument("--bundle", required=True)
    p.add_argument("--base", default="main")
    p.set_defaults(func=publish)

    r = sub.add_parser("register-webhook")
    r.add_argument("--url", required=True)
    r.set_defaults(func=register_webhook)

    d = sub.add_parser("deliveries")
    d.set_defaults(func=deliveries)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
