/**
 * Save 4 Two — desktop inbox API (Cloudflare Worker).
 *
 * POST /v1/link/start     phone creates a short code + phoneToken
 * POST /v1/link/complete  extension redeems code → deviceToken
 * POST /v1/inbox          extension sends { url, title }
 * GET  /v1/inbox          phone lists pending
 * POST /v1/inbox/consume  phone marks saved/dismissed
 * POST /v1/unlink         extension forgets device
 *
 * KV bindings: DEVICES, CODES, INBOX
 */

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS });
    }

    const url = new URL(request.url);
    try {
      if (url.pathname === "/v1/health") {
        return json({ ok: true, app: env.APP_NAME || "Save4Two Desktop API" });
      }
      if (url.pathname === "/v1/link/start" && request.method === "POST") {
        return await linkStart(request, env);
      }
      if (url.pathname === "/v1/link/complete" && request.method === "POST") {
        return await linkComplete(request, env);
      }
      if (url.pathname === "/v1/inbox" && request.method === "POST") {
        return await inboxCreate(request, env);
      }
      if (url.pathname === "/v1/inbox" && request.method === "GET") {
        return await inboxList(request, env);
      }
      if (url.pathname === "/v1/inbox/consume" && request.method === "POST") {
        return await inboxConsume(request, env);
      }
      if (url.pathname === "/v1/unlink" && request.method === "POST") {
        return await unlinkDevice(request, env);
      }
      return json({ error: "not_found" }, 404);
    } catch (err) {
      return json({ error: "server_error", message: String(err?.message || err) }, 500);
    }
  },
};

async function linkStart(request, env) {
  const body = await readJSON(request);
  const pairID = String(body.pairID || "").trim();
  if (!pairID) return json({ error: "pairID_required" }, 400);

  const code = randomDigits(6);
  const phoneToken = randomToken();
  const expiresAt = Date.now() + 10 * 60 * 1000;
  const record = {
    pairID,
    pairLabel: String(body.pairLabel || "").trim(),
    phoneToken,
    expiresAt,
  };
  await env.CODES.put(`code:${code}`, JSON.stringify(record), { expirationTtl: 600 });
  await env.DEVICES.put(
    `phone:${phoneToken}`,
    JSON.stringify({
      pairID,
      pairLabel: record.pairLabel,
      role: "phone",
      createdAt: Date.now(),
    })
  );
  return json({ code, phoneToken, expiresIn: 600 });
}

async function linkComplete(request, env) {
  const body = await readJSON(request);
  const code = String(body.code || "").replace(/\D/g, "");
  if (code.length !== 6) return json({ error: "invalid_code" }, 400);

  const raw = await env.CODES.get(`code:${code}`);
  if (!raw) return json({ error: "code_expired" }, 400);
  const record = JSON.parse(raw);
  if (record.expiresAt < Date.now()) {
    await env.CODES.delete(`code:${code}`);
    return json({ error: "code_expired" }, 400);
  }
  await env.CODES.delete(`code:${code}`);

  const deviceToken = randomToken();
  const clientLabel = String(body.clientLabel || "Browser").trim().slice(0, 80);
  await env.DEVICES.put(
    `device:${deviceToken}`,
    JSON.stringify({
      pairID: record.pairID,
      pairLabel: record.pairLabel,
      phoneToken: record.phoneToken,
      clientLabel,
      role: "desktop",
      createdAt: Date.now(),
    })
  );
  return json({
    deviceToken,
    pairLabel: record.pairLabel || "Save 4 Two",
  });
}

async function inboxCreate(request, env) {
  const body = await readJSON(request);
  const deviceToken = String(body.deviceToken || "").trim();
  if (!deviceToken) return json({ error: "deviceToken_required" }, 400);

  const deviceRaw = await env.DEVICES.get(`device:${deviceToken}`);
  if (!deviceRaw) return json({ error: "unauthorized" }, 401);
  const device = JSON.parse(deviceRaw);

  let urlString = String(body.url || "").trim();
  if (!/^https?:\/\//i.test(urlString)) {
    return json({ error: "url_required" }, 400);
  }
  try {
    const u = new URL(urlString);
    if (u.protocol !== "http:" && u.protocol !== "https:") {
      return json({ error: "url_invalid" }, 400);
    }
    urlString = u.toString();
  } catch {
    return json({ error: "url_invalid" }, 400);
  }

  const inboxID = crypto.randomUUID();
  const item = {
    inboxID,
    pairID: device.pairID,
    url: urlString,
    title: String(body.title || "").trim().slice(0, 200),
    source: String(body.source || "desktop").trim().slice(0, 40),
    status: "pending",
    createdAt: Date.now(),
  };
  await env.INBOX.put(`item:${inboxID}`, JSON.stringify(item));
  await appendPairIndex(env, device.pairID, inboxID);
  return json({ ok: true, inboxID });
}

async function inboxList(request, env) {
  const url = new URL(request.url);
  const phoneToken =
    bearer(request) || String(url.searchParams.get("phoneToken") || "").trim();
  if (!phoneToken) return json({ error: "unauthorized" }, 401);

  const phoneRaw = await env.DEVICES.get(`phone:${phoneToken}`);
  if (!phoneRaw) return json({ error: "unauthorized" }, 401);
  const phone = JSON.parse(phoneRaw);

  const ids = await readPairIndex(env, phone.pairID);
  const pending = [];
  for (const id of ids) {
    const raw = await env.INBOX.get(`item:${id}`);
    if (!raw) continue;
    const item = JSON.parse(raw);
    if (item.status !== "pending") continue;
    if (item.pairID !== phone.pairID) continue;
    pending.push(item);
  }
  pending.sort((a, b) => b.createdAt - a.createdAt);
  return json({ items: pending });
}

async function inboxConsume(request, env) {
  const body = await readJSON(request);
  const phoneToken = bearer(request) || String(body.phoneToken || "").trim();
  const inboxID = String(body.inboxID || "").trim();
  if (!phoneToken || !inboxID) return json({ error: "bad_request" }, 400);

  const phoneRaw = await env.DEVICES.get(`phone:${phoneToken}`);
  if (!phoneRaw) return json({ error: "unauthorized" }, 401);
  const phone = JSON.parse(phoneRaw);

  const key = `item:${inboxID}`;
  const raw = await env.INBOX.get(key);
  if (!raw) return json({ ok: true });
  const item = JSON.parse(raw);
  if (item.pairID !== phone.pairID) return json({ error: "forbidden" }, 403);
  item.status = "consumed";
  item.consumedAt = Date.now();
  await env.INBOX.put(key, JSON.stringify(item));
  return json({ ok: true });
}

async function unlinkDevice(request, env) {
  const body = await readJSON(request);
  const deviceToken = String(body.deviceToken || "").trim();
  if (!deviceToken) return json({ error: "deviceToken_required" }, 400);
  await env.DEVICES.delete(`device:${deviceToken}`);
  return json({ ok: true });
}

async function appendPairIndex(env, pairID, inboxID) {
  const key = `pair:${pairID}`;
  const raw = await env.INBOX.get(key);
  let ids = [];
  if (raw) {
    try {
      ids = JSON.parse(raw);
    } catch {
      ids = [];
    }
  }
  if (!ids.includes(inboxID)) ids.push(inboxID);
  // Keep last 100 ids
  if (ids.length > 100) ids = ids.slice(-100);
  await env.INBOX.put(key, JSON.stringify(ids));
}

async function readPairIndex(env, pairID) {
  const raw = await env.INBOX.get(`pair:${pairID}`);
  if (!raw) return [];
  try {
    const ids = JSON.parse(raw);
    return Array.isArray(ids) ? ids : [];
  } catch {
    return [];
  }
}

function bearer(request) {
  const h = request.headers.get("Authorization") || "";
  const m = /^Bearer\s+(.+)$/i.exec(h);
  return m ? m[1].trim() : "";
}

async function readJSON(request) {
  try {
    return await request.json();
  } catch {
    return {};
  }
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", ...CORS },
  });
}

function randomDigits(n) {
  let s = "";
  const bytes = crypto.getRandomValues(new Uint8Array(n));
  for (let i = 0; i < n; i++) s += String(bytes[i] % 10);
  return s;
}

function randomToken() {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
}
