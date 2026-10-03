# save4two-desktop-api

Cloudflare Worker for desktop → phone inbox.

```bash
npx wrangler kv namespace create S42_DEVICES
npx wrangler kv namespace create S42_CODES
npx wrangler kv namespace create S42_INBOX
# update wrangler.toml ids, then:
npx wrangler deploy
```

See `docs/desktop-inbox.md`.
