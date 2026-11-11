#!/usr/bin/env python3
"""Run the Codemagic `screenshots` workflow and download the PNGs.

    python scripts/capture_screens.py --branch claude/app-store-prep \
        --out docs/store/raw-before [--scenes "flights detail"]

Token: env CODEMAGIC_API_TOKEN, else CODEMAGIC_API_TOKEN in
~/.testflight-autofix/secrets.env, else ~/.secrets/flightdeck/codemagic_token.
The token is never printed.
"""
import argparse, io, json, os, sys, time, urllib.request, urllib.error, zipfile

API = "https://api.codemagic.io"
APP_ID = "6ae34ccdbaf52d7600f9b455"
SECRETS = os.path.expanduser("~/.testflight-autofix/secrets.env")
TOKEN_FILE = os.path.expanduser("~/.secrets/flightdeck/codemagic_token")


def token():
    t = os.environ.get("CODEMAGIC_API_TOKEN")
    if t:
        return t.strip()
    if os.path.exists(SECRETS):
        with open(SECRETS) as f:
            for line in f:
                if line.startswith("CODEMAGIC_API_TOKEN="):
                    v = line.split("=", 1)[1].strip().strip("'\"")
                    if v:
                        return v
    if os.path.exists(TOKEN_FILE):
        with open(TOKEN_FILE) as f:
            v = f.read().strip()
            if v:
                return v
    sys.exit("Codemagic token not found (env, secrets.env or ~/.secrets/flightdeck/codemagic_token)")


TOKEN = None


def call(method, url, body=None, auth=True):
    headers = {"Content-Type": "application/json"}
    if auth:
        headers["x-auth-token"] = TOKEN
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read()


def download(url):
    """Artifact URLs need the auth header; fall back to a public-url call."""
    try:
        return call("GET", url)
    except urllib.error.HTTPError:
        pub = json.loads(call("POST", url.rstrip("/") + "/public-url",
                              {"expiresAt": int(time.time()) + 3600}))
        return call("GET", pub["url"], auth=False)


def main():
    global TOKEN
    ap = argparse.ArgumentParser()
    ap.add_argument("--branch", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--scenes", default="")
    ap.add_argument("--build-id", help="skip starting; poll/download this build")
    a = ap.parse_args()
    TOKEN = token()

    build_id = a.build_id
    if not build_id:
        body = {"appId": APP_ID, "workflowId": "screenshots", "branch": a.branch}
        if a.scenes:
            body["environment"] = {"variables": {"SCENES": a.scenes}}
        build_id = json.loads(call("POST", f"{API}/builds", body))["buildId"]
    print("build id:", build_id, flush=True)

    while True:
        b = json.loads(call("GET", f"{API}/builds/{build_id}"))["build"]
        if b["status"] in ("finished", "failed", "canceled", "timeout", "skipped", "warning"):
            break
        time.sleep(30)
    print("status:", b["status"], flush=True)

    if b["status"] not in ("finished", "warning"):
        for step in b.get("buildActions", []):
            if step.get("status") not in ("success", "skipped", None):
                print(f"failed step: {step.get('name')} ({step.get('status')})")
                for k in ("logUrl", "log_url"):
                    if step.get(k):
                        try:
                            log = download(step[k]).decode(errors="replace").splitlines()
                            print("\n".join(log[-40:]))
                        except Exception as e:
                            print("could not fetch log:", type(e).__name__)
        sys.exit(1)

    os.makedirs(a.out, exist_ok=True)
    for art in b.get("artefacts", []) or b.get("artifacts", []):
        raw = download(art["url"])
        if art["name"].endswith(".zip"):
            with zipfile.ZipFile(io.BytesIO(raw)) as z:
                for n in z.namelist():
                    if n.endswith(".png"):
                        path = os.path.join(a.out, os.path.basename(n))
                        open(path, "wb").write(z.read(n))
                        print("saved", path)
        else:
            path = os.path.join(a.out, os.path.basename(art["name"]))
            open(path, "wb").write(raw)
            print("saved", path)


if __name__ == "__main__":
    main()
