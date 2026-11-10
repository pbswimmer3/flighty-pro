# TestFlight feedback → automatic fix

Submit feedback from TestFlight (screenshot or crash) and, a few minutes later,
there's a GitHub issue with your report and a pull request from Claude that
fixes it. Codemagic compile-checks the PR; you merge from your phone; the merge
ships a new TestFlight build. Not quite right? Reply `@claude …` on the issue
or the PR and it goes round again.

```
TestFlight ──webhook──▶ relay (Cloudflare Worker) ──dispatch──▶ GitHub Actions
                                                                │
   collect  App Store Connect → report, screenshots, crash log → issue
   fix      Claude (read-only token, edits FlightDeck/ docs/ .claude/skills/ only) → patch
   publish  fresh checkout of main, applies allowlisted paths only → PR "Fixes #N"
                                                                │
   Codemagic compile check on the PR ──▶ you merge ──▶ TestFlight build
   "@claude …" on the issue or PR ──▶ same pipeline, building on the existing branch
```

| Piece | Where | What it holds |
|---|---|---|
| `relay/` | Cloudflare Worker (free tier) | Webhook secret; a GitHub token that can only start workflows |
| `.github/workflows/testflight-feedback.yml` | GitHub Actions | The three jobs above; daily backstop sweep |
| `.github/workflows/testflight-feedback-followup.yml` | GitHub Actions | `@claude …` comments from you → another round |
| `.github/workflows/testflight-webhook-setup.yml` | GitHub Actions | Registers the webhook with Apple; shows recent deliveries |
| `scripts/testflight_feedback.py` | runs in Actions | App Store Connect calls, issues, the allowlist, the PR |
| `codemagic.yaml` → `compile-check` | Codemagic | Builds every PR into `main` |

## This repository is public

Issues and pull requests are visible to anyone. What gets posted:

| Posted on the issue | Kept out of it |
|---|---|
| Your comment, build number, device model, iOS version, screen size, connection, battery, app uptime, the first 120 lines of a crash log | Screenshots, locale and time zone, tester name and email |

Claude still sees the screenshots, locale and time zone: they travel inside the
workflow run as an artifact kept for one day. (On a public repo, anyone signed
in to GitHub can download a run's artifacts during that day.)

If you'd rather keep feedback private, make the repository private (Settings →
General → Danger Zone → Change visibility). Screenshots then appear in issues
automatically. Private repos get 2,000 free Actions minutes a month. To show
screenshots on a public repo anyway, add a repository variable
`FEEDBACK_PUBLIC_SCREENSHOTS` = `true`.

## Safety rails

- **The job that reads feedback can't write.** Claude runs with a read-only
  GitHub token, no shell, no network, no git, and edit rights only under
  `FlightDeck/`, `docs/` and `.claude/skills/`. Its result leaves the job as a
  patch file.
- **A separate job publishes, from main.** It checks out `main` fresh, applies
  the patch only to allowlisted paths (whole renames are refused if either
  side isn't allowed, and symlinks never), and never runs anything from the
  patch. Dropped paths are listed in the PR.
- **Nothing that looks like a credential leaves.** If Claude's summary or patch
  contains something shaped like a GitHub token, an Anthropic key or a private
  key, the whole result is withheld.
- **Only you can send it back.** `@claude` follow-ups count only from the
  repository owner. Anyone else's comment does nothing.
- **Nothing merges itself.** Every fix is a PR for you to review.
- **Signed webhooks only.** The relay rejects anything without Apple's
  `x-apple-signature` HMAC, and never sees the App Store Connect key.
- **Keep testers to yourself** (internal testing). Anyone who can submit
  feedback can steer what Claude is asked to do.

## Costs

- Cloudflare Workers free tier: 100,000 requests a day. You'll use a handful.
- GitHub Actions: free for public repositories. Each fix is roughly 5–20
  minutes.
- Claude: billed to your Claude subscription (`CLAUDE_CODE_OAUTH_TOKEN`) or API
  key (`ANTHROPIC_API_KEY`), whichever secret you set. A run is capped at 80
  turns, and at most 5 new reports are fixed per run.

---

## One-time setup

First merge the pull request that adds this pipeline into `main`. Then paste
the block below into a browser agent (e.g. Claude in Chrome) on a computer
where you're signed in to GitHub, App Store Connect and Cloudflare. Secrets
never go through the agent's chat: wherever one is needed, the agent opens the
right form and you paste the value yourself.

Before you start, make a **webhook secret**: any long random string (40+
letters and digits — a password generator is fine). Keep it handy for two
forms.

````text
You are setting up an automation for my GitHub repository pbswimmer3/flighty-pro.
I'm signed in to github.com, appstoreconnect.apple.com and dash.cloudflare.com
in this browser. Work through the steps in order. Rules:
- Never type, paste or repeat a secret yourself. When a step says I PASTE, open
  the form, fill in the name, put the cursor in the value field, tell me
  exactly what to paste, and wait for me to say "done" before saving.
- Stop and ask me if a page doesn't match what's described.
- At the end, report every value marked REPORT and anything that failed.

STEP 1 — App Store Connect: API key and app ID
1. Open https://appstoreconnect.apple.com/access/integrations/api (Users and
   Access → Integrations → App Store Connect API → Team Keys).
2. Note the "Issuer ID" shown above the keys table. REPORT it as ASC_ISSUER_ID.
3. Click "+" (Generate API Key). Name: "FlightDeck feedback". Access: "App
   Manager". Generate. REPORT the new key's "Key ID" as ASC_KEY_ID.
4. Click "Download" on that key (only possible once). Tell me the file
   AuthKey_<KEYID>.p8 is in my Downloads folder; I'll need it in Step 3.
5. Open https://appstoreconnect.apple.com/apps, open "Prad's Flight Deck",
   then General → App Information. REPORT the numeric "Apple ID" as ASC_APP_ID.

STEP 2 — GitHub: a token the relay can use to start the workflow
1. Open https://github.com/settings/personal-access-tokens/new
2. Token name: "FlightDeck feedback relay". Expiration: 1 year (or the longest
   offered). Resource owner: pbswimmer3.
3. Repository access: "Only select repositories" → pbswimmer3/flighty-pro.
4. Permissions → Repository permissions → "Actions": Read and write. Leave
   every other permission at No access (Metadata: Read-only is automatic).
5. Generate the token. Leave this tab open; it's needed in Step 4.3 and is
   shown only once. REPORT the expiry date.

STEP 3 — GitHub: repository settings and secrets
1. Open https://github.com/pbswimmer3/flighty-pro/settings/actions
   Under "Workflow permissions", tick "Allow GitHub Actions to create and
   approve pull requests" and Save. Leave the rest as it is.
2. Open https://github.com/pbswimmer3/flighty-pro/settings and, under "Pull
   Requests", tick "Automatically delete head branches". Save if asked.
3. Open https://github.com/pbswimmer3/flighty-pro/settings/secrets/actions and
   create these repository secrets ("New repository secret" for each):
     ASC_KEY_ID       — you type it: the Key ID from Step 1.3
     ASC_ISSUER_ID    — you type it: the Issuer ID from Step 1.2
     ASC_APP_ID       — you type it: the Apple ID from Step 1.5
     ASC_PRIVATE_KEY  — I PASTE: the whole contents of the .p8 file, opened in
                        Notepad, from -----BEGIN PRIVATE KEY----- to
                        -----END PRIVATE KEY-----
     APPLE_WEBHOOK_SECRET — I PASTE: my webhook secret
4. Claude access — ask me which I have:
   a) Claude Pro/Max subscription: I'll run `claude setup-token` in a terminal.
      Create secret CLAUDE_CODE_OAUTH_TOKEN — I PASTE the token.
   b) API key: open https://console.anthropic.com/settings/keys, create a key
      named "FlightDeck feedback" (leave the page showing it), then create
      secret ANTHROPIC_API_KEY — I PASTE the key.
   Only one of the two is needed.

STEP 4 — Cloudflare: deploy the relay
1. Open https://dash.cloudflare.com → Workers & Pages → Create → Workers tab →
   "Import a repository" (Continue with GitHub). If asked, install the
   Cloudflare Workers and Pages GitHub app with access to ONLY
   pbswimmer3/flighty-pro.
2. Pick the flighty-pro repository. Project name: flightdeck-feedback-relay.
   In the build settings:
     Root directory: relay
     Build command: (leave empty)   Deploy command: npx wrangler deploy
     Production branch: main
     Non-production branch builds: OFF (untick "Builds for non-production
       branches" if shown)
     Build watch paths: include relay/* only (if the option is shown)
   Click Create and deploy, and wait for it to finish. If Cloudflare asks you
   to choose a workers.dev subdomain, pick any name.
3. In the Worker: Settings → Variables and Secrets → Add, twice:
     Type Secret, name GITHUB_TOKEN — I PASTE the token still showing in the
       GitHub tab from Step 2
     Type Secret, name APPLE_WEBHOOK_SECRET — I PASTE my webhook secret
   Save / Deploy.
4. REPORT the Worker's URL as RELAY_URL
   (https://flightdeck-feedback-relay.<something>.workers.dev, shown under
   Domains & Routes or on the overview).
5. Open RELAY_URL in a new tab. It should say "FlightDeck feedback relay: POST
   only." If it doesn't, stop and tell me what it says.

STEP 5 — Register the webhook with Apple (a workflow does it)
1. Open https://github.com/pbswimmer3/flighty-pro/actions/workflows/testflight-webhook-setup.yml
2. Click "Run workflow". Action: register. relay_url: RELAY_URL. Run.
3. Open the run and wait (about a minute). Success ends with "The relay
   answered the ping. Setup is complete." REPORT the last 15 lines of the log.
   If it failed with HTTP 403, tell me — the key from Step 1 may need the
   Admin role. If it says the ping failed with HTTP 401, the two webhook
   secrets (Step 3.3 and Step 4.3) differ.

STEP 6 — Check Codemagic will compile the PRs
1. Open https://github.com/pbswimmer3/flighty-pro/settings/hooks. If there is
   a webhook whose URL starts with https://api.codemagic.io/hooks/, open it and
   make sure "Pull requests" is among the selected events (as well as Pushes);
   if not, tick it and "Update webhook".
2. If there's no such webhook, open
   https://github.com/pbswimmer3/flighty-pro/settings/installations and check
   that Codemagic is listed there instead; if it is, skip this step. If neither,
   tell me.

STEP 7 — Fix the feedback that's already there
1. Open https://github.com/pbswimmer3/flighty-pro/actions/workflows/testflight-feedback.yml
2. Click "Run workflow". Leave feedback_kind, feedback_id and issue empty, set
   sweep_days to 30, and run it.
3. Wait for the "collect" job. REPORT how many issues it filed (the log says
   "Filed N new issue(s)") and their links from the Issues tab (label
   testflight-feedback). It files at most 5 per run; if the log says more are
   waiting, run it again after the first one finishes.

Finally, give me a summary: every REPORT value, which steps succeeded, and
anything that needs my attention.
````

### Check it end to end

1. On your phone, open FlightDeck from TestFlight, take a screenshot, tap
   **Share Beta Feedback**, write what's wrong and submit.
2. Within a minute or two, GitHub → **Actions** shows a run of
   "TestFlight feedback → Claude fix", and **Issues** has your report.
3. When the run finishes, the issue links a PR. Codemagic's **Compile check**
   builds it; if it's green and the change looks right, merge it.

### Sending a fix back

Comment on the issue or on Claude's PR, starting with `@claude`:

- `@claude the caption is still wrong on the Ground tab`
- `@claude it was AS 2187 on Nov 10, the flight that departed SNA`
- `@claude try again` (after a run that failed or ran out of turns)

A 👀 reaction means it was picked up. Claude gets the original report plus
every comment you've made on the issue and the PR, starts from the existing
fix branch, and pushes another commit to the same PR. You can also start this
by hand: **Run workflow** with `issue` set to the issue number.

## When something doesn't happen

| Symptom | Look at |
|---|---|
| No Actions run after submitting feedback | Run **TestFlight webhook setup** with action `deliveries`. `FAILED HTTP 401` → the two `APPLE_WEBHOOK_SECRET`s differ. `HTTP 502` → the relay's `GITHUB_TOKEN` expired or lacks Actions: write. `HTTP 422` → Apple sent a feedback event the relay couldn't read (the Worker's Observability logs show it; the daily sweep still picks it up). Nothing listed → re-run `register`. |
| `collect` fails with 401 | `ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_PRIVATE_KEY` don't belong together, or the key was revoked. |
| `collect` fails with 403 | The key's role can't read TestFlight feedback; make a new key with the Admin role. |
| `fix` fails at "Claude fixes it" | Neither `CLAUDE_CODE_OAUTH_TOKEN` nor `ANTHROPIC_API_KEY` is set, it expired, or the subscription hit its usage limit. The issue says so; reply `@claude try again` later. |
| `publish` fails with 403 | Settings → Actions → General → tick "Allow GitHub Actions to create and approve pull requests". |
| PR opened but no compile check | The Codemagic webhook isn't sending "Pull requests" events (Step 6). |
| Issue says Claude changed nothing | Claude thought the report was unclear or not a bug; its reasoning is in the comment. Reply `@claude` with the missing detail. |
| `@claude` comment does nothing | It must start with `@claude` and come from the repository owner's account, on an issue labelled `testflight-feedback` or on Claude's PR. |

Missed webhooks aren't lost: the daily sweep at 15:41 UTC files anything from
the last three days that has no issue yet.

## Maintenance

- **The relay's GitHub token expires** (Step 2). Until it's replaced, the
  daily sweep still catches feedback, a day late. Make a new one and replace
  `GITHUB_TOKEN` in the Worker's settings.
- **Rotating the webhook secret**: change `APPLE_WEBHOOK_SECRET` in both GitHub
  and Cloudflare, then re-run the setup workflow with `register`.
- **Codemagic and forks**: this repo is public, so a pull request from someone
  else's fork can start a compile check (build minutes only; no secrets are
  involved). If that becomes a nuisance, turn off fork builds in Codemagic's
  app settings.
