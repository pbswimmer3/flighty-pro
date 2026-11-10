// Run with `npm test` (Node 20+): exercises the Worker exactly as Cloudflare
// would call it, with GitHub's API replaced by a stub.
import { test } from "node:test";
import assert from "node:assert/strict";
import worker, { verifySignature, classify } from "../src/index.js";

const SECRET = "s3cret-for-tests";
const env = {
  APPLE_WEBHOOK_SECRET: SECRET,
  GITHUB_TOKEN: "github_pat_test",
  GITHUB_REPO: "pbswimmer3/flighty-pro",
  WORKFLOW_FILE: "testflight-feedback.yml",
  WORKFLOW_REF: "main",
};

async function sign(secret, body) {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey("raw", enc.encode(secret),
    { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", key, enc.encode(body)));
  return "hmacsha256=" + [...mac].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function feedbackEvent(type, instanceType, id) {
  return JSON.stringify({
    data: {
      type,
      id: "7c813492-9516-4c79-903e-224effdd57ac",
      version: 1,
      attributes: { timestamp: "2026-11-10T05:00:52.745Z" },
      relationships: { instance: { data: { type: instanceType, id } } },
    },
  });
}

function withStubbedFetch(status, run) {
  const calls = [];
  const original = globalThis.fetch;
  globalThis.fetch = async (url, init) => {
    calls.push({ url, init });
    return new Response(null, { status });
  };
  return run(calls).finally(() => { globalThis.fetch = original; });
}

async function post(body, signature) {
  const headers = { "Content-Type": "application/json" };
  if (signature !== undefined) headers["x-apple-signature"] = signature;
  return worker.fetch(new Request("https://relay.example/", { method: "POST", headers, body }), env);
}

test("matches Apple's documented signature example", async () => {
  // From "Configuring and parsing App Store Connect API webhook notifications".
  const header = "hmacsha256=7f062172b01cb00b53ca068614674a3d982a34062a0f5d37687d5e3377e54657";
  assert.equal(await verifySignature("This is my secret", "Hello, World!", header), true);
  assert.equal(await verifySignature("This is my secret", "Hello, World?", header), false);
  assert.equal(await verifySignature("wrong", "Hello, World!", header), false);
});

test("rejects missing or malformed signatures", async () => {
  assert.equal(await verifySignature(SECRET, "{}", ""), false);
  assert.equal(await verifySignature(SECRET, "{}", "sha256=abcd"), false);
  assert.equal(await verifySignature(SECRET, "{}", "hmacsha256=zz"), false);
});

test("screenshot feedback dispatches the workflow with kind and id", async () => {
  const body = feedbackEvent("betaFeedbackScreenshotSubmissionCreated",
    "betaFeedbackScreenshotSubmissions", "ABC123-def_456");
  await withStubbedFetch(204, async (calls) => {
    const res = await post(body, await sign(SECRET, body));
    assert.equal(res.status, 202);
    assert.equal(calls.length, 1);
    assert.equal(calls[0].url,
      "https://api.github.com/repos/pbswimmer3/flighty-pro/actions/workflows/testflight-feedback.yml/dispatches");
    assert.equal(calls[0].init.headers.Authorization, "Bearer github_pat_test");
    assert.deepEqual(JSON.parse(calls[0].init.body), {
      ref: "main",
      inputs: { feedback_kind: "screenshot", feedback_id: "ABC123-def_456" },
    });
  });
});

test("crash feedback is recognised from the instance type alone", async () => {
  const body = feedbackEvent("somethingNew", "betaFeedbackCrashSubmissions", "CRASH1");
  await withStubbedFetch(204, async (calls) => {
    const res = await post(body, await sign(SECRET, body));
    assert.equal(res.status, 202);
    assert.equal(JSON.parse(calls[0].init.body).inputs.feedback_kind, "crash");
  });
});

test("unsigned or forged requests never reach GitHub", async () => {
  const body = feedbackEvent("betaFeedbackScreenshotSubmissionCreated",
    "betaFeedbackScreenshotSubmissions", "X1");
  await withStubbedFetch(204, async (calls) => {
    assert.equal((await post(body)).status, 401);
    assert.equal((await post(body, await sign("not-the-secret", body))).status, 401);
    assert.equal(calls.length, 0);
  });
});

test("pings and other events are acknowledged and ignored", async () => {
  const ping = JSON.stringify({ data: { type: "webhookPingCreated", id: "p1" } });
  const other = feedbackEvent("appStoreVersionAppVersionStateUpdated", "appStoreVersions", "v1");
  await withStubbedFetch(204, async (calls) => {
    assert.equal((await post(ping, await sign(SECRET, ping))).status, 200);
    assert.equal((await post(other, await sign(SECRET, other))).status, 200);
    assert.equal(calls.length, 0);
  });
});

test("ids that aren't plain tokens are refused", () => {
  const evil = { data: { type: "betaFeedbackCrashSubmissionCreated",
    relationships: { instance: { data: { id: "x; rm -rf /" } } } } };
  assert.equal(classify(evil), null);
  assert.deepEqual(classify({ data: { type: "betaFeedbackCrashSubmissionCreated",
    relationships: { instance: { type: "betaFeedbackCrashSubmissions", id: "OK1" } } } }),
    { kind: "crash", id: "OK1" });
});

test("a GitHub failure surfaces as 502 so Apple marks the delivery failed", async () => {
  const body = feedbackEvent("betaFeedbackScreenshotSubmissionCreated",
    "betaFeedbackScreenshotSubmissions", "X2");
  await withStubbedFetch(401, async () => {
    assert.equal((await post(body, await sign(SECRET, body))).status, 502);
  });
});

test("non-POST is refused without touching GitHub", async () => {
  await withStubbedFetch(204, async (calls) => {
    const res = await worker.fetch(new Request("https://relay.example/"), env);
    assert.equal(res.status, 405);
    assert.equal(calls.length, 0);
  });
});
