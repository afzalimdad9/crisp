# Crisp server

Backend for Crisp's optional **cloud transcription** tier. The macOS app sends an
audio file; the server authenticates the user (Sign in with Apple), checks their
credit balance, runs transcription via **Deepgram**, charges minutes, and returns
word-timestamped text. Audio is processed in-memory and never stored.

## Stack
- **Hono** (HTTP) on Node 20+, run with **tsx** (no build step)
- **Postgres** for users / credit ledger / jobs (in-memory fallback for local dev)
- **Deepgram** for speech-to-text (deterministic mock when no key)
- **jose** for Apple identity-token verification + our session JWTs

## Endpoints
| Method | Path | Auth | Purpose |
|---|---|---|---|
| GET | `/health` | – | liveness |
| POST | `/v1/auth/apple` | – | exchange Apple identity token → session token + account |
| POST | `/v1/auth/dev` | – | local-only sign-in (needs `DEV_AUTH=1`) |
| GET | `/v1/account` | Bearer | plan + credit balance (minutes) |
| POST | `/v1/transcribe` | Bearer | multipart `file` + `durationSec` → words + minutes charged |

## Local dev
```bash
cd server
cp .env.example .env      # leave DATABASE_URL and DEEPGRAM_API_KEY empty, set DEV_AUTH=1
npm install
npm start                 # in-memory store + mock ASR, listens on :8787
```
Smoke test:
```bash
curl localhost:8787/health
TOKEN=$(curl -s -XPOST localhost:8787/v1/auth/dev -d '{}' | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')
curl -s localhost:8787/v1/account -H "Authorization: Bearer $TOKEN"
curl -s -XPOST localhost:8787/v1/transcribe -H "Authorization: Bearer $TOKEN" \
  -F "file=@../WiseEditTests/Fixtures/sample.m4a;type=audio/m4a" -F "durationSec=12"
```

## Deploy to Vercel
1. Create a project + add the **Postgres** plugin.
2. Add this `server/` as a service (root directory `server`). Vercel auto-runs
   `npm install` then `npm start`.
3. Set env vars on the service:
   - `DATABASE_URL` → from the Postgres plugin
   - `APPLE_BUNDLE_ID` → `com.wisedt.WiseEdit`
   - `JWT_SECRET` → a long random string
   - `DEEPGRAM_API_KEY` → from your Deepgram account
   - `FREE_MINUTES` → e.g. `10`
   - `DEV_AUTH` → `0` (must be off in prod)
4. Point `crisp-api-afzalimdad9.vercel.app` at the service's domain.
