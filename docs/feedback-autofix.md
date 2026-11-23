# TestFlight feedback → automatic Claude fix

When a tester submits feedback in TestFlight (a screenshot with a note, or a
crash), it becomes a GitHub issue within about a minute, followed by a pull
request from Claude that fixes it. To send a fix back for another round, the
repository owner replies on the issue or the PR with a comment that **starts
with** `@claude`. Any other comment is ignored.

```
TestFlight ─webhook→ relay/ (Cloudflare Worker) ─dispatch→ .github/workflows/testflight-feedback.yml
  collect  App Store Connect feedback API → issue (label testflight-feedback)
  fix      Claude, edit tools limited to the "editable" folders, read-only token → patch
  publish  fresh checkout of main → applies only allowed paths → PR "Fixes #N"
  alert    only when collect fails → comment on the "pipeline needs attention" issue
"@claude …" (owner only) → testflight-feedback-followup.yml → same pipeline on the same branch
A daily sweep catches anything the webhook missed (GitHub runs it some hours after 15:41 UTC).
```

Nothing merges by itself. Every pull request is a draft of a fix written
without building the app: read it, check its check, and try it on a phone.

Installed, updated and verified by the `set-up-auto-testflight` Claude skill
(`/set-up-auto-testflight` in the repo). This repo's settings are in
`.github/testflight-feedback.json`:

| Key | Meaning |
|---|---|
| `editable` | The only folders a feedback fix may change. Everything else in a patch is dropped and named in the PR |
| `protected` | Extra paths that are never changed. CI, signing, build config, lockfiles, `CLAUDE.md`, `.mcp.json`, nested `.claude/` folders and the pipeline itself always are |
| `app_skill` | A file the fix reads first (the app's own skill or architecture notes). A file path, not a skill name |
| `verify_workflow` | The CI workflow started on each fix branch (empty when Codemagic checks PRs) |
| `stack` | `expo` or `native`. In an Expo app a fix that touches native code is flagged on the PR, because no check compiles it |
| `build_note`, `check_note` | What the fix is told it cannot run, and what the PR tells you to check |
| `bundle_id`, `relay_name`, `pipeline_version` | Used by setup |

## Secrets (repository → Settings → Secrets → Actions)

`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY`, `ASC_APP_ID`,
`APPLE_WEBHOOK_SECRET` (the same value as the relay's), and either
`CLAUDE_CODE_OAUTH_TOKEN` or `ANTHROPIC_API_KEY`. The relay Worker holds
`APPLE_WEBHOOK_SECRET` and `GITHUB_TOKEN` (a fine-grained token with only
Actions: read and write on this repo; it expires after a year).

## Safety

- The job that reads tester-written text never holds a token that can write.
- The publish job runs the code on `main`, never code from a fix branch, and refuses
  symlinks, submodules, renames out of protected paths, and anything shaped like a
  credential.
- Public repos: screenshots stay out of issues unless `FEEDBACK_PUBLIC_SCREENSHOTS=true`
  is set as a repository variable. Tester identity, locale and time zone are never posted.

## When something doesn't happen

Fastest check of every part at once: `/set-up-auto-testflight` and ask it to
verify, or `python <skill>/scripts/provision.py --repo-dir . --steps verify`.

| Symptom | Look at |
|---|---|
| An issue titled "TestFlight feedback pipeline needs attention" | Its newest comment names the cause. Close it once a run succeeds |
| No run after submitting feedback | Run **TestFlight webhook setup** with `deliveries`. 401 → the two `APPLE_WEBHOOK_SECRET`s differ; 502 → the relay's `GITHUB_TOKEN` expired or lacks Actions: write on this repo |
| `collect` fails 401/403 | ASC key, issuer and private key don't belong together; an Apple agreement is waiting to be accepted; or the key's role can't read TestFlight feedback |
| Your comment did nothing | It must start with `@claude` and come from the repository owner |
| The issue says Claude couldn't sign in | The Claude token secret is wrong (often a space where a terminal wrapped it), expired, or the plan's usage limit is used up |
| `publish` fails 403 | Settings → Actions → General → allow GitHub Actions to create and approve pull requests |
| PR has no check | See `verify_workflow` above, or the Codemagic webhook and its `pull_request` trigger |
| Issue says Claude changed nothing | Its reasoning and its question are in the comment; reply `@claude` with the answer |
