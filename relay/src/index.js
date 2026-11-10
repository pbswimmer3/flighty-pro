// FlightDeck feedback relay — a Cloudflare Worker.
//
// App Store Connect can POST a webhook the moment a TestFlight tester submits
// feedback, but it can't add the auth header GitHub requires to start a
// workflow. This Worker is the bridge: it checks Apple's signature, pulls the
// feedback ID out of the event, and dispatches the `testflight-feedback.yml`
// workflow with it. Everything else — fetching the feedback, filing the issue,
// running Claude — happens in GitHub Actions, where the App Store Connect key
// lives. The Worker never sees that key; it holds only:
//
//   APPLE_WEBHOOK_SECRET  the secret given to App Store Connect when the
//                         webhook was registered (secret)
//   GITHUB_TOKEN          fine-grained token, this repo only, Actions: write
//                         and nothing else (secret)
//   GITHUB_REPO           "owner/name" (var, wrangler.toml)
//   WORKFLOW_FILE         workflow to dispatch (var)
//   WORKFLOW_REF          branch the workflow runs from (var)
//
// Spec: https://developer.apple.com/documentation/appstoreconnectapi/configuring-webhook-notifications

const FEEDBACK_KINDS = {
  // Apple's event-type enum (WebhookEventType) and the camelCase `data.type`
  // the notification body carries, mapped to the two kinds the workflow knows.
  BETA_FEEDBACK_SCREENSHOT_SUBMISSION_CREATED: "screenshot",
  BETA_FEEDBACK_CRASH_SUBMISSION_CREATED: "crash",
  betaFeedbackScreenshotSubmissionCreated: "screenshot",
  betaFeedbackCrashSubmissionCreated: "crash",
  // Resource types, in case only the instance relationship is telling.
  betaFeedbackScreenshotSubmissions: "screenshot",
  betaFeedbackCrashSubmissions: "crash",
};

// App Store Connect resource IDs are opaque, but they never need more than
// this. Anything else is refused before it reaches a workflow input.
// A leading "-" is refused too, so an id can never be read as a CLI flag.
const ID_PATTERN = /^[A-Za-z0-9_][A-Za-z0-9_-]{0,127}$/;

export default {
  async fetch(request, env) {
    if (request.method !== "POST") {
      return text(405, "FlightDeck feedback relay: POST only.");
    }
    if (!env.APPLE_WEBHOOK_SECRET) {
      return text(500, "Relay is missing APPLE_WEBHOOK_SECRET.");
    }

    // HMAC over the bytes exactly as received, not a re-encoded string.
    const body = new Uint8Array(await request.arrayBuffer());
    const signature = request.headers.get("x-apple-signature") || "";
    if (!(await verifySignature(env.APPLE_WEBHOOK_SECRET, body, signature))) {
      return text(401, "Bad signature.");
    }
    // Checked after the signature so an unauthenticated caller learns nothing
    // about how the relay is configured.
    if (!env.GITHUB_TOKEN || !env.GITHUB_REPO) {
      return text(500, "Relay is missing GITHUB_TOKEN or GITHUB_REPO.");
    }

    let event;
    try {
      event = JSON.parse(new TextDecoder().decode(body));
    } catch {
      return text(400, "Body is not JSON.");
    }

    const feedback = classify(event);
    if (feedback === UNREADABLE) {
      // A feedback event we couldn't get an ID out of. Answer with an error so
      // it shows as FAILED in the setup workflow's `deliveries` list instead
      // of passing silently; the daily sweep still picks the feedback up.
      console.error("Feedback event without a usable instance id", JSON.stringify(event).slice(0, 2000));
      return text(422, "Feedback event, but no usable instance id.");
    }
    if (!feedback) {
      // Pings and any event type we didn't subscribe to: acknowledge, so App
      // Store Connect's "Test Your Webhook" reports success, and do nothing.
      return text(200, "Accepted; not a feedback event.");
    }

    const dispatched = await dispatchWorkflow(env, feedback);
    if (!dispatched.ok) {
      // A non-2xx makes the delivery show as failed in App Store Connect,
      // where it can be redelivered. The daily sweep is the backstop.
      return text(502, `GitHub refused the dispatch (${dispatched.status}).`);
    }
    return text(202, `Dispatched ${feedback.kind} feedback ${feedback.id}.`);
  },
};

/**
 * Apple sends `x-apple-signature: hmacsha256=<hex>`, an HMAC-SHA256 of the raw
 * body keyed with the shared secret. Verified with WebCrypto's `verify`, which
 * compares in constant time.
 */
export async function verifySignature(secret, body, header) {
  const match = /^hmacsha256=([0-9a-fA-F]{64})$/.exec(header.trim());
  if (!match) return false;
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["verify"],
  );
  const bytes = typeof body === "string" ? encoder.encode(body) : body;
  return crypto.subtle.verify("HMAC", key, hexToBytes(match[1]), bytes);
}

/** Returned by `classify` for a feedback event whose id can't be used. */
export const UNREADABLE = Symbol("unreadable feedback event");

/**
 * Pull `{kind, id}` out of a notification: null if it isn't TestFlight
 * feedback, UNREADABLE if it is but carries no id we can safely pass on. Apple's documented shape is
 * `{data: {type, id, attributes, relationships: {instance: {data: {type, id}}}}}`;
 * a few event families put `{type, id}` directly under `instance`, so both are
 * accepted.
 */
export function classify(event) {
  const data = event && typeof event === "object" ? event.data : null;
  if (!data || typeof data !== "object") return null;
  const instance = data.relationships?.instance;
  const target = instance?.data ?? instance ?? {};
  const kind = FEEDBACK_KINDS[data.type] ?? FEEDBACK_KINDS[target.type];
  if (!kind) return null;
  const id = target.id;
  if (typeof id !== "string" || !ID_PATTERN.test(id)) return UNREADABLE;
  return { kind, id };
}

async function dispatchWorkflow(env, feedback) {
  const workflow = env.WORKFLOW_FILE || "testflight-feedback.yml";
  const url = `https://api.github.com/repos/${env.GITHUB_REPO}/actions/workflows/${workflow}/dispatches`;
  const response = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${env.GITHUB_TOKEN}`,
      Accept: "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
      "User-Agent": "flightdeck-feedback-relay",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      ref: env.WORKFLOW_REF || "main",
      inputs: { feedback_kind: feedback.kind, feedback_id: feedback.id },
    }),
  });
  return { ok: response.ok, status: response.status };
}

function hexToBytes(hex) {
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = parseInt(hex.substr(i * 2, 2), 16);
  }
  return bytes;
}

function text(status, message) {
  return new Response(message + "\n", {
    status,
    headers: { "Content-Type": "text/plain; charset=utf-8" },
  });
}
