# Desktop → phone inbox

Send a URL from Chrome/Safari to Save 4 Two. Phone shows a **From desktop** badge on Add only when something is pending.

## Pieces

| Path | Role |
|------|------|
| `desktop-api/` | Cloudflare Worker (`api.save4two.com`) |
| `desktop-extension/chrome/` | Chrome MV3 extension |
| `ToDo42/DesktopInbox*.swift` | Phone inbox + Pair “Link desktop” |

## Deploy API (Cloudflare)

```bash
cd desktop-api
npx wrangler login
npx wrangler kv namespace create S42_DEVICES
npx wrangler kv namespace create S42_CODES
npx wrangler kv namespace create S42_INBOX
# paste the ids into wrangler.toml
npx wrangler deploy
# DNS: CNAME api.save4two.com → workers.dev route, or workers custom domain
```

Health check: `https://api.save4two.com/v1/health`

## Link flow

1. Phone paired → Pair → **Link desktop** → **Create desktop code**
2. Chrome extension → Options → enter code → Link
3. Toolbar **S42** / popup **Send to phone**
4. Phone **+** → badge **From desktop (N)** → pick → edit/save

## Load Chrome extension (dev)

`chrome://extensions` → Developer mode → Load unpacked → `desktop-extension/chrome`

## Safari

Convert the same JS later with `xcrun safari-web-extension-converter` (Phase 4).

## Notes

- Inbox is stored in Worker KV (not CloudKit) for v1 so deploy is simple.
- Metadata fetch still runs on the phone when you open a pending link.
- Badge is omitted when pending count is 0.
