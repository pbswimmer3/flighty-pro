#!/usr/bin/env python3
"""TestFlight feedback → GitHub issue → Claude fix → pull request.

Runs inside GitHub Actions (see .github/workflows/testflight-feedback.yml and
docs/feedback-autofix.md). Standard library plus PyJWT for the App Store
Connect token. Four subcommands:

  collect           Fetch one feedback submission (by kind + id, as the relay
                    dispatches it) or sweep the last N days. For each one not
                    already filed: save the report, screenshots and crash log
                    for Claude, publish the screenshots to an assets branch,
                    and open a GitHub issue. Writes `items` (JSON) to
                    $GITHUB_OUTPUT for the fix job's matrix.
  finish            After Claude has run: drop any edits to protected paths,
                    commit what's left on the fix branch, push, open the PR,
                    and report back on the issue — or, if Claude changed
                    nothing, post its explanation on the issue instead.
  register-webhook  Create (or update) the App Store Connect webhook that
                    points at the relay, then send it a test ping.
  deliveries        Show the webhook's most recent deliveries — the first
                    place to look when feedback doesn't trigger a run.

Environment:
  ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY   App Store Connect API key
  ASC_APP_ID                                   the app's Apple ID (numeric)
  GITHUB_TOKEN, GITHUB_REPOSITORY              provided by Actions
  APPLE_WEBHOOK_SECRET                         register-webhook only

Everything a tester wrote is data, not instructions. It reaches Claude as a
file it is told to treat that way, and `finish` enforces the one rule that
matters even if Claude were talked out of it: changes to CI, the relay,
these scripts or signing config are never committed.
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

# Paths a feedback-driven change must never touch, whatever the feedback says.
# Workflows and scripts could exfiltrate secrets; the relay and signing config
# are the trust boundary; the project file is how the app is built and signed.
PROTECTED = (
    ".github/",
    "relay/",
    "scripts/",
    "codemagic.yaml",
    "FlightDeck.xcodeproj/",
    ".claude/settings",
)

CRASH_LOG_LINES_IN_ISSUE = 120
ID_PATTERN = re.compile(r"^[A-Za-z0-9_-]{1,128}$")


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
        import jwt  # PyJWT[crypto]; imported late so `finish` doesn't need it

        now = int(time.time())
        return jwt.encode(
            {"iss": self.issuer_id, "iat": now, "exp": now + 15 * 60, "aud": "appstoreconnect-v1"},
            self.private_key,
            algorithm="ES256",
            headers={"kid": self.key_id, "typ": "JWT"},
        )

    def request(self, method: str, path: str, params: dict | None = None, payload=None):
        url = ASC_API + path
        if params:
            url += "?" + urllib.parse.urlencode(params)
        headers = {"Authorization": f"Bearer {self.token()}", "Accept": "application/json"}
        return json_request(method, url, headers, payload)

    def get(self, path, params=None):
        return self.request("GET", path, params)


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


SUBMISSION_PARAMS = {
    "include": "build,tester",
    "fields[builds]": "version,uploadedDate",
    "fields[betaTesters]": "firstName,lastName,email",
}


def fetch_submission(asc: AppStoreConnect, kind: str, submission_id: str) -> dict:
    document = asc.get(f"/v1/{KINDS[kind]}/{submission_id}", SUBMISSION_PARAMS)
    return flatten(document["data"], document.get("included", []), kind)


def list_recent_submissions(asc: AppStoreConnect, app_id: str, kind: str,
                            since: dt.datetime) -> list[dict]:
    """Newest first, stopping at the first one older than `since`."""
    params = {**SUBMISSION_PARAMS, "sort": "-createdDate", "limit": "50"}
    path = f"/v1/apps/{app_id}/{KINDS[kind]}"
    found: list[dict] = []
    url = ASC_API + path + "?" + urllib.parse.urlencode(params)
    while url:
        headers = {"Authorization": f"Bearer {asc.token()}", "Accept": "application/json"}
        document = json_request("GET", url, headers)
        for item in document.get("data", []):
            submission = flatten(item, document.get("included", []), kind)
            if submission["created"] and submission["created"] < since:
                return found
            found.append(submission)
        url = document.get("links", {}).get("next")
    return found


def flatten(item: dict, included: list[dict], kind: str) -> dict:
    """One submission as a plain dict, with its build and tester resolved."""
    attributes = item.get("attributes", {}) or {}
    relationships = item.get("relationships", {}) or {}
    lookup = {(inc.get("type"), inc.get("id")): inc.get("attributes", {}) or {} for inc in included}

    def related(name: str) -> dict:
        data = (relationships.get(name) or {}).get("data") or {}
        return lookup.get((data.get("type"), data.get("id")), {})

    build = related("build")
    tester = related("tester")
    tester_name = " ".join(filter(None, [tester.get("firstName"), tester.get("lastName")]))
    return {
        "id": item["id"],
        "kind": kind,
        "created": parse_time(attributes.get("createdDate")),
        "comment": (attributes.get("comment") or "").strip(),
        "tester": tester_name or attributes.get("email") or tester.get("email") or "",
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
                ids.update(re.findall(r"<!-- testflight-feedback-id: ([A-Za-z0-9_-]+) -->",
                                      issue.get("body") or ""))
            if len(issues) < 100:
                return ids
            page += 1

    def ensure_assets_branch(self):
        try:
            self.call("GET", f"/git/ref/heads/{ASSETS_BRANCH}")
            return
        except HTTPError as error:
            if error.status != 404:
                raise
        repo = json_request("GET", f"{GITHUB_API}/repos/{self.repository}", self.headers)
        base = self.call("GET", f"/git/ref/heads/{repo['default_branch']}")
        self.call("POST", "/git/refs", {"ref": f"refs/heads/{ASSETS_BRANCH}",
                                        "sha": base["object"]["sha"]})

    def put_file(self, path: str, content: bytes, message: str) -> str:
        """Commit one file to the assets branch; returns a URL that renders in
        issues for anyone who can read the repo (private repos included)."""
        payload = {"message": message, "branch": ASSETS_BRANCH,
                   "content": base64.b64encode(content).decode()}
        try:
            existing = self.call("GET", f"/contents/{path}", params={"ref": ASSETS_BRANCH})
            payload["sha"] = existing["sha"]
        except HTTPError as error:
            if error.status != 404:
                raise
        self.call("PUT", f"/contents/{path}", payload)
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


def details_table(submission: dict) -> str:
    rows = [
        ("Submitted", submission["created"].strftime("%Y-%m-%d %H:%M UTC") if submission["created"] else ""),
        ("Build", submission["build"]),
        ("Device", submission["device"]),
        ("iOS", submission["os"]),
        ("Screen", submission["screen"]),
        ("Locale / time zone", " · ".join(filter(None, [submission["locale"], submission["time_zone"]]))),
        ("Connection", submission["connection"]),
        ("Battery", f"{submission['battery']}%" if submission["battery"] is not None else ""),
        ("App running for", _uptime(submission["uptime_ms"])),
        ("Tester", submission["tester"]),
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


def report_markdown(submission: dict, images: list[str], crash_log: str, *, for_issue: bool) -> str:
    """The same report twice: once for the issue (images on the assets
    branch, log truncated) and once for Claude (local paths, full log)."""
    kind = "Crash report" if submission["kind"] == "crash" else "Screenshot feedback"
    parts = []
    if for_issue:
        parts.append(f"<!-- testflight-feedback-id: {submission['id']} -->")
    parts += [f"**{kind}** from TestFlight", "", quote(submission["comment"]), "", details_table(submission)]
    if images:
        parts += ["", "### Screenshots", ""]
        parts += [f"![screenshot {i + 1}]({src})" for i, src in enumerate(images)]
    if crash_log:
        lines = crash_log.splitlines()
        if for_issue:
            shown = "\n".join(lines[:CRASH_LOG_LINES_IN_ISSUE])
            more = len(lines) - CRASH_LOG_LINES_IN_ISSUE
            note = f"\n… {more} more lines in the workflow run's artifact." if more > 0 else ""
            parts += ["", "<details><summary>Crash log</summary>", "", "```", shown, "```", note, "</details>"]
        else:
            parts += ["", "Full crash log: `crash.log` in this folder."]
    if for_issue:
        parts += ["", "---",
                  "_Filed automatically from TestFlight. Claude is working on a fix — "
                  "a pull request will be linked here._"]
    return "\n".join(parts) + "\n"


def collect(args) -> int:
    required = ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_PRIVATE_KEY", "ASC_APP_ID")
    if not args.id and not all(os.environ.get(name, "").strip() for name in required):
        # The daily sweep starts running the moment this workflow is merged,
        # which is before anyone has added the secrets. Don't turn that gap
        # into a failure email every day.
        print("::notice::App Store Connect secrets aren't set yet; skipping the sweep. "
              "See docs/feedback-autofix.md.")
        write_output("items", "[]")
        return 0
    asc = AppStoreConnect(env("ASC_KEY_ID"), env("ASC_ISSUER_ID"), env("ASC_PRIVATE_KEY"))
    github = GitHub(env("GITHUB_TOKEN"), env("GITHUB_REPOSITORY"))

    if args.id:
        if args.kind not in KINDS or not ID_PATTERN.match(args.id):
            print(f"Refusing kind={args.kind!r} id={args.id!r}", file=sys.stderr)
            return 2
        submissions = [fetch_submission(asc, args.kind, args.id)]
    else:
        since = dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=args.days)
        app_id = env("ASC_APP_ID")
        submissions = []
        for kind in KINDS:
            submissions += list_recent_submissions(asc, app_id, kind, since)
        submissions.sort(key=lambda s: s["created"] or dt.datetime.min.replace(tzinfo=dt.timezone.utc))
        print(f"Found {len(submissions)} submission(s) in the last {args.days} day(s).")

    github.ensure_label()
    already = github.filed_ids()
    items = []
    for submission in submissions:
        if submission["id"] in already:
            print(f"{submission['id']}: already filed, skipping.")
            continue
        if len(items) >= args.max_new:
            print(f"{submission['id']}: over the per-run limit of {args.max_new}; the next sweep will pick it up.")
            continue
        items.append(file_one(asc, github, submission))

    write_output("items", json.dumps(items))
    print(f"Filed {len(items)} new issue(s).")
    return 0


def file_one(asc: AppStoreConnect, github: GitHub, submission: dict) -> dict:
    folder = WORK_DIR / submission["id"]
    folder.mkdir(parents=True, exist_ok=True)

    local_images, issue_images = [], []
    if submission["screenshots"]:
        github.ensure_assets_branch()
    for index, shot in enumerate(submission["screenshots"], start=1):
        try:
            data = download(shot["url"], shot.get("width"), shot.get("height"))
        except Exception as error:  # an expired link must not lose the report
            print(f"{submission['id']}: screenshot {index} unavailable ({error})", file=sys.stderr)
            continue
        name = f"screenshot-{index}.png"
        (folder / name).write_bytes(data)
        local_images.append(name)
        issue_images.append(github.put_file(f"feedback/{submission['id']}/{name}", data,
                                            f"TestFlight feedback {submission['id']}: {name}"))

    crash_log = fetch_crash_log(asc, submission["id"]) if submission["kind"] == "crash" else ""
    if crash_log:
        (folder / "crash.log").write_text(crash_log)

    (folder / "feedback.md").write_text(report_markdown(submission, local_images, crash_log, for_issue=False))
    issue = github.call("POST", "/issues", {
        "title": issue_title(submission),
        "body": report_markdown(submission, issue_images, crash_log, for_issue=True),
        "labels": [LABEL],
    })
    print(f"{submission['id']}: filed #{issue['number']}")
    return {
        "id": submission["id"],
        "kind": submission["kind"],
        "issue": issue["number"],
        "branch": f"testflight/{submission['kind']}-{submission['id'][:24].lower()}",
    }


# ---------------------------------------------------------------- finish ---


def git(*args: str, check: bool = True) -> str:
    result = subprocess.run(["git", *args], check=check, capture_output=True, text=True)
    return result.stdout


def changed_paths() -> list[str]:
    """Every path the working tree differs from HEAD in, untracked included,
    ignoring the gitignored feedback folder."""
    out = git("status", "--porcelain", "--untracked-files=all", "-z")
    paths = []
    entries = out.split("\0")
    i = 0
    while i < len(entries):
        entry = entries[i]
        i += 1
        if len(entry) < 4:
            continue
        status, path = entry[:2], entry[3:]
        paths.append(path)
        if status[0] in "RC":  # renames carry the source path as the next entry
            paths.append(entries[i])
            i += 1
    return [p for p in paths if not p.startswith(str(WORK_DIR) + "/")]


def is_protected(path: str) -> bool:
    return any(path == p.rstrip("/") or path.startswith(p) for p in PROTECTED)


def revert_protected(paths: list[str]) -> list[str]:
    reverted = [p for p in paths if is_protected(p)]
    for path in reverted:
        tracked = git("ls-files", "--error-unmatch", "--", path, check=False).strip()
        if tracked:
            git("checkout", "HEAD", "--", path)
        else:
            Path(path).unlink(missing_ok=True)
    return reverted


def read_summary(folder: Path, issue: int) -> tuple[str, str]:
    summary_file = folder / "SUMMARY.md"
    text = summary_file.read_text().strip() if summary_file.exists() else ""
    if not text:
        return f"Fix TestFlight feedback (#{issue})", "_Claude didn't write a summary._"
    first, _, rest = text.partition("\n")
    title = re.sub(r"^#+\s*", "", first).strip().strip("*") or f"Fix TestFlight feedback (#{issue})"
    if len(title) > 72:
        title = title[:71].rstrip() + "…"
    return title, rest.strip() or text


def finish(args) -> int:
    github = GitHub(env("GITHUB_TOKEN"), env("GITHUB_REPOSITORY"))
    folder = WORK_DIR / args.id
    title, summary = read_summary(folder, args.issue)

    reverted = revert_protected(changed_paths())
    remaining = changed_paths()
    guard_note = ""
    if reverted:
        guard_note = ("\n\n> [!WARNING]\n> These edits were dropped because feedback-driven changes may not touch "
                      "CI, the relay, scripts or build configuration: " + ", ".join(f"`{p}`" for p in reverted))

    if not remaining:
        github.call("POST", f"/issues/{args.issue}/comments", {
            "body": f"Claude looked into this and didn't change any code.\n\n{summary}{guard_note}\n\n"
                    f"[Workflow run]({run_url()})"})
        print("No code changes; explained on the issue.")
        return 0

    git("config", "user.name", "github-actions[bot]")
    git("config", "user.email", "41898282+github-actions[bot]@users.noreply.github.com")
    git("add", "--all", "--", *remaining)
    git("commit", "-m", title, "-m", f"Fixes #{args.issue} (TestFlight feedback {args.id}).")
    # The branch belongs to this one piece of feedback and only this workflow
    # writes to it, so a re-run replaces it outright.
    git("push", "--force", "origin", f"HEAD:refs/heads/{args.branch}")

    body = (f"{summary}{guard_note}\n\n---\nFixes #{args.issue} — filed from TestFlight feedback "
            f"`{args.id}`.\n\nWritten by Claude from the tester's report; it could not build iOS here, so "
            f"**check that Codemagic's compile check passed** and try it on device before merging.\n\n"
            f"[Workflow run]({run_url()})")
    try:
        pr = github.call("POST", "/pulls", {"title": title, "head": args.branch,
                                            "base": args.base, "body": body})
    except HTTPError as error:
        if error.status == 403:
            print("GitHub refused to open the PR. Enable Settings → Actions → General → "
                  "'Allow GitHub Actions to create and approve pull requests'.", file=sys.stderr)
            raise
        if error.status != 422:
            raise
        # A re-run: the PR from last time is still open and now has the new push.
        owner = github.repository.split("/")[0]
        open_prs = github.call("GET", "/pulls", params={"head": f"{owner}:{args.branch}", "state": "open"})
        if not open_prs:
            raise
        pr = github.call("PATCH", f"/pulls/{open_prs[0]['number']}", {"title": title, "body": body})
    github.call("POST", f"/issues/{args.issue}/comments", {
        "body": f"Proposed fix: #{pr['number']} — {title}"})
    print(f"Opened PR #{pr['number']}")
    return 0


def run_url() -> str:
    server = os.environ.get("GITHUB_SERVER_URL", "https://github.com")
    return f"{server}/{os.environ.get('GITHUB_REPOSITORY', '')}/actions/runs/{os.environ.get('GITHUB_RUN_ID', '')}"


# ------------------------------------------------------------- webhooks ----


def register_webhook(args) -> int:
    asc = AppStoreConnect(env("ASC_KEY_ID"), env("ASC_ISSUER_ID"), env("ASC_PRIVATE_KEY"))
    app_id, secret = env("ASC_APP_ID"), env("APPLE_WEBHOOK_SECRET")
    url = args.url.strip()
    if not url.startswith("https://"):
        print("The relay URL must start with https://", file=sys.stderr)
        return 2

    attributes = {"name": WEBHOOK_NAME, "url": url, "secret": secret,
                  "eventTypes": WEBHOOK_EVENTS, "enabled": True}
    existing = asc.get(f"/v1/apps/{app_id}/webhooks", {"limit": "50"}).get("data", [])
    match = next((w for w in existing if (w.get("attributes") or {}).get("name") == WEBHOOK_NAME), None)
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

    asc.request("POST", "/v1/webhookPings", payload={"data": {
        "type": "webhookPings",
        "relationships": {"webhook": {"data": {"type": "webhooks", "id": webhook_id}}}}})
    print("Sent a test ping. Waiting for the delivery result…")
    time.sleep(15)
    return show_deliveries(asc, webhook_id, require_success=True)


def deliveries(args) -> int:
    asc = AppStoreConnect(env("ASC_KEY_ID"), env("ASC_ISSUER_ID"), env("ASC_PRIVATE_KEY"))
    existing = asc.get(f"/v1/apps/{env('ASC_APP_ID')}/webhooks", {"limit": "50"}).get("data", [])
    match = next((w for w in existing if (w.get("attributes") or {}).get("name") == WEBHOOK_NAME), None)
    if not match:
        print("No FlightDeck webhook is registered. Run the setup workflow first.")
        return 1
    return show_deliveries(asc, match["id"], require_success=False)


def show_deliveries(asc: AppStoreConnect, webhook_id: str, require_success: bool) -> int:
    document = asc.get(f"/v1/webhooks/{webhook_id}/deliveries", {"limit": "10", "include": "event"})
    events = {inc["id"]: inc.get("attributes", {}) for inc in document.get("included", [])}
    rows = document.get("data", [])
    if not rows:
        print("No deliveries recorded yet.")
        return 1 if require_success else 0
    newest_ok = False
    for index, row in enumerate(rows):
        a = row.get("attributes", {})
        event_id = ((row.get("relationships") or {}).get("event") or {}).get("data", {}).get("id")
        event = events.get(event_id, {})
        response = a.get("response") or {}
        print(f"{a.get('createdDate')}  {a.get('deliveryState'):9}  HTTP {response.get('httpStatusCode')}  "
              f"{'ping' if event.get('ping') else event.get('eventType', '')}  {a.get('errorMessage') or ''}")
        if index == 0:
            newest_ok = a.get("deliveryState") == "SUCCEEDED"
    if require_success and not newest_ok:
        print("\nThe newest delivery didn't succeed. Check the relay's URL and that the same "
              "APPLE_WEBHOOK_SECRET is set in both GitHub and Cloudflare.", file=sys.stderr)
        return 1
    return 0


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
    c.add_argument("--days", type=int, default=3)
    c.add_argument("--max-new", type=int, default=5,
                   help="cap on issues (and Claude runs) per invocation")
    c.set_defaults(func=collect)

    f = sub.add_parser("finish")
    f.add_argument("--id", required=True)
    f.add_argument("--issue", type=int, required=True)
    f.add_argument("--branch", required=True)
    f.add_argument("--base", default="main")
    f.set_defaults(func=finish)

    r = sub.add_parser("register-webhook")
    r.add_argument("--url", required=True)
    r.set_defaults(func=register_webhook)

    d = sub.add_parser("deliveries")
    d.set_defaults(func=deliveries)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
