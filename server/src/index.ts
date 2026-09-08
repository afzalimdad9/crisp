import { serve } from "@hono/node-server";
import { Hono } from "hono";
import { cors } from "hono/cors";
import { env } from "./env.js";
import { makeStore } from "./store.js";
import { issueSessionToken, requireAuth, verifyAppleIdentityToken } from "./auth.js";
import { transcribeAudio } from "./deepgram.js";

const store = makeStore();
await store.init();

type Vars = { Variables: { userId: string } };
const app = new Hono<Vars>();
app.use("*", cors());

app.get("/health", (c) => c.json({ ok: true, store: env.DATABASE_URL ? "postgres" : "memory" }));

// ── Auth ──────────────────────────────────────────────────────────────────────

// Exchange a Sign in with Apple identity token for our session token.
app.post("/v1/auth/apple", async (c) => {
  const body = await c.req.json().catch(() => ({}));
  const idToken = typeof body.identityToken === "string" ? body.identityToken : "";
  if (!idToken) return c.json({ error: "identityToken required" }, 400);

  let apple: { sub: string; email: string | null };
  try {
    apple = await verifyAppleIdentityToken(idToken);
  } catch (e) {
    return c.json({ error: "invalid Apple identity token", detail: String(e) }, 401);
  }

  const { user } = await store.upsertUser(apple.sub, apple.email);
  const token = await issueSessionToken(user.id);
  const balanceMinutes = await store.balanceMinutes(user.id);
  return c.json({ token, account: accountPayload(balanceMinutes) });
});

// Dev-only sign-in (no Apple) for local testing. Disabled unless DEV_AUTH=1.
app.post("/v1/auth/dev", async (c) => {
  if (!env.DEV_AUTH) return c.json({ error: "not found" }, 404);
  const body = await c.req.json().catch(() => ({}));
  const sub = typeof body.sub === "string" && body.sub ? body.sub : "dev-user";
  const { user } = await store.upsertUser(`dev:${sub}`, "dev@example.com");
  const token = await issueSessionToken(user.id);
  const balanceMinutes = await store.balanceMinutes(user.id);
  return c.json({ token, account: accountPayload(balanceMinutes) });
});

// ── Account ─────────────────────────────────────────────────────────────────

app.get("/v1/account", requireAuth, async (c) => {
  const userId = c.get("userId");
  const user = await store.getUser(userId);
  if (!user) return c.json({ error: "user not found" }, 404);
  const balanceMinutes = await store.balanceMinutes(userId);
  return c.json(accountPayload(balanceMinutes));
});

// ── Transcription ─────────────────────────────────────────────────────────────

// multipart/form-data: file=<audio>, durationSec=<number>
app.post("/v1/transcribe", requireAuth, async (c) => {
  const userId = c.get("userId");

  const form = await c.req.parseBody();
  const file = form["file"];
  const durationSec = Number(form["durationSec"]);
  if (!(file instanceof File)) return c.json({ error: "file (audio) required" }, 400);
  if (!Number.isFinite(durationSec) || durationSec <= 0) {
    return c.json({ error: "durationSec required" }, 400);
  }

  const minutesNeeded = durationSec / 60;
  const balance = await store.balanceMinutes(userId);
  if (balance < minutesNeeded) {
    return c.json(
      { error: "insufficient_credits", balanceMinutes: round(balance), minutesNeeded: round(minutesNeeded) },
      402
    );
  }

  const audio = new Uint8Array(await file.arrayBuffer());
  let result;
  try {
    result = await transcribeAudio(audio, file.type || "audio/m4a");
  } catch (e) {
    return c.json({ error: "transcription_failed", detail: String(e) }, 502);
  }

  // Charge actual duration (known up front) and record the job.
  await store.addLedger(userId, -minutesNeeded, "transcription");
  await store.recordJob(userId, durationSec, minutesNeeded, result.provider);

  const balanceMinutes = await store.balanceMinutes(userId);
  return c.json({
    words: result.words,
    provider: result.provider,
    minutesCharged: round(minutesNeeded),
    balanceMinutes: round(balanceMinutes),
  });
});

function accountPayload(balanceMinutes: number) {
  return { plan: "free", balanceMinutes: round(balanceMinutes) };
}
function round(n: number) {
  return Math.round(n * 100) / 100;
}

serve({ fetch: app.fetch, port: env.PORT }, (info) => {
  console.log(`Crisp server listening on :${info.port} (store=${env.DATABASE_URL ? "postgres" : "memory"}, asr=${env.DEEPGRAM_API_KEY ? "deepgram" : "mock"})`);
});
