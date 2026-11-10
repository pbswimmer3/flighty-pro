# TestFlight feedback → automatic fix

Submit feedback from TestFlight (screenshot or crash) and, within a couple of
minutes, there's a GitHub issue with your report and a pull request from Claude
that fixes it. Codemagic compile-checks the PR; you merge from your phone; the
merge ships a new TestFlight build.

```
TestFlight ──webhook──▶ relay (Cloudflare Worker) ──dispatch──▶ GitHub Actions
                                                                │
          ┌─────────────────────────────────────────────────────┘
          ▼
  collect: fetch the report, screenshots, crash log from App Store Connect
           → issue labelled `testflight-feedback`
  fix:     Claude reads the report and the code, edits FlightDeck/
           → branch testflight/<kind>-<id> → pull request "Fixes #N"
          │
          ▼
  Codemagic compile check on the PR ──▶ you merge ──▶ TestFlight build
```

| Piece | Where | What it holds |
|---|---|---|
| `relay/` | Cloudflare Worker (free tier) | Webhook secret; a GitHub token that can only start workflows |
| `.github/workflows/testflight-feedback.yml` | GitHub Actions | Runs on each webhook, plus a daily backstop sweep |
| `.github/workflows/testflight-webhook-setup.yml` | GitHub Actions | Registers the webhook with Apple; shows recent deliveries |
| `scripts/testflight_feedback.py` | runs in Actions | App Store Connect calls, issue filing, the PR |
| `codemagic.yaml` → `compile-check` | Codemagic | Builds every PR into `main` |

## Safety rails

- **Feedback is data, not instructions.** Claude gets the report as a file it's
  told to treat that way, and runs with file tools only — no shell, no network,
  no git.
- **Protected paths.** Whatever Claude edits, `finish` drops any change to
  `.github/`, `relay/`, `scripts/`, `codemagic.yaml`, the Xcode project or
  `.claude/settings*` before committing, and says so in the PR.
- **Nothing merges itself.** Every fix is a PR for you to review.
- **Signed webhooks only.** The relay rejects anything without Apple's
  `x-apple-signature` HMAC. It never sees the App Store Connect key.
- **Keep testers to yourself** (internal testing). Anyone who can submit
  feedback can steer what Claude is asked to do. If you add outside testers,
  change the workflow to wait for a label before the fix job runs.

## Costs

- Cloudflare Workers free tier: 100,000 requests a day. You'll use a handful.
- GitHub Actions: each fix is roughly 5–20 minutes on a Linux runner. The
  daily sweep is under a minute.
- Claude: billed to your Claude subscription (`CLAUDE_CODE_OAUTH_TOKEN`) or API
  key (`ANTHROPIC_API_KEY`), whichever secret you set. `--max-turns 80` caps a
  single run.

---

## One-time setup

You'll need, in this order: the PR with this pipeline merged into `main`; a
**webhook secret** (any long random string — make one with a password
generator and keep it for steps 3 and 4); then the steps below.

The block below is written to be pasted into a browser agent (e.g. Claude in
Chrome) on a computer where you're signed in to GitHub, App Store Connect and
Cloudflare. Two values can't come from a browser — the `.p8` key file and a
Claude subscription token — so the agent stops and asks you for those.

````text
You are setting up an automation for my GitHub repository pbswimmer3/flighty-pro.
I'm signed in to github.com, appstoreconnect.apple.com and dash.cloudflare.com
in this browser. Work through the steps in order. Never paste a secret anywhere
except the exact field named. Stop and ask me whenever a step says ASK ME, or
if a page doesn't match what's described. At the end, report every value marked
REPORT and anything that failed.

Before you start, ask me for: the WEBHOOK SECRET (a long random string I made).

STEP 1 — App Store Connect: API key and app ID
1. Open https://appstoreconnect.apple.com/access/integrations/api (Users and
   Access → Integrations → App Store Connect API → Team Keys).
2. Copy the "Issuer ID" shown above the keys table. REPORT it as ASC_ISSUER_ID.
3. Click "+" (Generate API Key). Name: "FlightDeck feedback". Access: "App
   Manager". Generate. REPORT the new key's "Key ID" as ASC_KEY_ID.
4. Click "Download" on that key. This downloads AuthKey_<KEYID>.p8 and can only
   be done once. ASK ME to open the .p8 file in Notepad and give you its full
   contents (from -----BEGIN PRIVATE KEY----- to -----END PRIVATE KEY-----).
   That is ASC_PRIVATE_KEY. Don't save it anywhere else.
5. Open https://appstoreconnect.apple.com/apps, open "Prad's Flight Deck",
   then General → App Information. Copy the numeric "Apple ID". REPORT it as
   ASC_APP_ID.

STEP 2 — GitHub: a token the relay can use to start the workflow
1. Open https://github.com/settings/personal-access-tokens/new
2. Token name: "FlightDeck feedback relay". Expiration: 1 year (or the longest
   offered). Resource owner: pbswimmer3.
3. Repository access: "Only select repositories" → pbswimmer3/flighty-pro.
4. Permissions → Repository permissions → "Actions": Read and write. Leave
   every other permission at No access (Metadata: Read-only is automatic).
5. Generate token and copy it (starts with github_pat_). This is RELAY_TOKEN;
   you'll paste it in Step 4. REPORT the expiry date.

STEP 3 — GitHub: repository settings and secrets
1. Open https://github.com/pbswimmer3/flighty-pro/settings/actions
   Under "Workflow permissions", tick "Allow GitHub Actions to create and
   approve pull requests" and click Save. Leave the rest as it is.
2. Open https://github.com/pbswimmer3/flighty-pro/settings/secrets/actions
   and create these repository secrets ("New repository secret" for each):
     ASC_KEY_ID            from Step 1.3
     ASC_ISSUER_ID         from Step 1.2
     ASC_PRIVATE_KEY       the .p8 contents from Step 1.4
     ASC_APP_ID            from Step 1.5
     APPLE_WEBHOOK_SECRET  the WEBHOOK SECRET I gave you
3. Claude access — ASK ME which I have:
   a) A Claude Pro/Max subscription: I'll run `claude setup-token` in a
      terminal and give you the token. Save it as secret
      CLAUDE_CODE_OAUTH_TOKEN.
   b) An API key: open https://console.anthropic.com/settings/keys, create a
      key named "FlightDeck feedback", and save it as secret
      ANTHROPIC_API_KEY.
   Only one of the two is needed.

STEP 4 — Cloudflare: deploy the relay
1. Open https://dash.cloudflare.com → Workers & Pages → Create → Workers tab →
   "Import a repository" (Continue with GitHub). If asked, install the
   Cloudflare Workers and Pages GitHub app with access to ONLY
   pbswimmer3/flighty-pro.
2. Pick the flighty-pro repository. Project name: flightdeck-feedback-relay.
   Production branch: main. Under advanced/build settings set
   Root directory: relay   (Build command: leave empty; Deploy command:
   npx wrangler deploy). Click Create and deploy, and wait for it to finish.
   If Cloudflare asks you to choose a workers.dev subdomain, pick any name.
3. In the Worker: Settings → Variables and Secrets → Add:
     Type Secret, name APPLE_WEBHOOK_SECRET, value = the WEBHOOK SECRET
     Type Secret, name GITHUB_TOKEN,         value = RELAY_TOKEN from Step 2
   Save / Deploy.
4. Copy the Worker's URL (https://flightdeck-feedback-relay.<something>.workers.dev,
   shown under Domains & Routes or on the overview). REPORT it as RELAY_URL.
5. Open RELAY_URL in a new tab. It should say "FlightDeck feedback relay: POST
   only." If it doesn't, stop and tell me what it says.

STEP 5 — Register the webhook with Apple (done by a workflow)
1. Open https://github.com/pbswimmer3/flighty-pro/actions/workflows/testflight-webhook-setup.yml
2. Click "Run workflow". Action: register. relay_url: RELAY_URL. Run.
3. Open the run and wait for it to finish. The log ends with a list of
   deliveries; the newest should be "SUCCEEDED  HTTP 200  ping". REPORT the
   last 10 lines of that log. If the run failed with HTTP 403, tell me — the
   key from Step 1 may need the Admin role.

STEP 6 — Check Codemagic will compile the PRs
1. Open https://github.com/pbswimmer3/flighty-pro/settings/hooks and click the
   webhook whose URL starts with https://api.codemagic.io/hooks/.
2. Make sure "Pull requests" is among the selected events (as well as
   Pushes). If not, tick it and click "Update webhook".

STEP 7 — Fix the feedback that's already there
1. Open https://github.com/pbswimmer3/flighty-pro/actions/workflows/testflight-feedback.yml
2. Click "Run workflow". Leave feedback_kind and feedback_id empty, set
   sweep_days to 90, and run it.
3. Wait for the "collect" job. REPORT how many issues it filed (the log says
   "Filed N new issue(s)") and their links from the Issues tab (label
   testflight-feedback). It files at most 5 per run; if it says more are
   waiting, run it again after the first finishes.

Finally, give me a summary: every REPORT value except secrets, which steps
succeeded, and anything that needs my attention.
````

### Check it end to end

1. On your phone, open FlightDeck from TestFlight, take a screenshot, tap
   **Share Beta Feedback**, write what's wrong and submit.
2. Within a minute or two, GitHub → **Actions** shows a run of
   "TestFlight feedback → Claude fix", and **Issues** has your report with the
   screenshot.
3. When the run finishes, the issue links a PR. Codemagic's **Compile check**
   builds it; if it's green and the change looks right, merge it.

## When something doesn't happen

| Symptom | Look at |
|---|---|
| No Actions run after submitting feedback | Run **TestFlight webhook setup** with action `deliveries`. `FAILED HTTP 401` → the two `APPLE_WEBHOOK_SECRET`s differ. `HTTP 502` → the relay's `GITHUB_TOKEN` expired or lacks Actions: write. Nothing listed → re-run `register`. |
| Run starts, `collect` fails with 401 | `ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_PRIVATE_KEY` don't belong together, or the key was revoked. |
| `collect` fails with 403 | The key's role can't read TestFlight feedback; make a new key with a higher role. |
| `fix` fails at "Claude fixes it" | Neither `CLAUDE_CODE_OAUTH_TOKEN` nor `ANTHROPIC_API_KEY` is set, or it expired. |
| `fix` fails at "Open the pull request" with 403 | Settings → Actions → General → tick "Allow GitHub Actions to create and approve pull requests". |
| PR opened but no compile check | The Codemagic webhook isn't sending "Pull requests" events (Step 6). |
| Issue says Claude changed nothing | Claude thought the report was unclear or not a bug; its reasoning is in the comment. Reply with detail and re-run, or fix by hand. |

Missed webhooks aren't lost: the daily sweep at 15:41 UTC files anything from
the last three days that has no issue yet.

## Maintenance

- **The relay's GitHub token expires** (Step 2). When it does, the daily sweep
  still catches feedback, a day late. Make a new one and replace
  `GITHUB_TOKEN` in the Worker's settings.
- **Rotating the webhook secret**: change `APPLE_WEBHOOK_SECRET` in both GitHub
  and Cloudflare, then re-run the setup workflow with `register`.
- **Screenshots** are committed to the `testflight-feedback-assets` branch so
  they render in issues. It's never merged; delete old folders whenever.
