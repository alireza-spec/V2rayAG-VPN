const MAX_BODY = 512 * 1024;
const MAX_SUB_BYTES = 2 * 1024 * 1024;
const MAX_IMPORT = 100;
const REFRESH_BATCH = 10;
const SUB_PREFIX = "sub:";
const PROFILE_PREFIX = "profile:";
const LEASE_PREFIX = "lease:";
const RATE_PREFIX = "rate:";
const DEVICE_PREFIX = "device:";
const MAX_LEASES_PER_MINUTE = 12;
const MAX_AUTO_ENROLLMENTS_PER_DAY_PER_IP = 20;
const LEASE_TTL_SECONDS = 12 * 60 * 60;
const SUPPORTED_URI = /^(?:vless|vmess|trojan|ss|shadowsocks|hysteria2|wireguard|socks|http):\/\//i;

const ADMIN_HTML = `<!doctype html>
<html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="dark"><title>V2rayAG Pool Admin</title>
<style>
:root{color-scheme:dark;font:16px system-ui,sans-serif;background:#0d111b;color:#edf1fb}body{margin:0 auto;padding:28px;max-width:880px}h1{font-size:24px;margin:0 0 8px}.muted{color:#9ba8c0}.card{background:#151c2b;border:1px solid #2c3650;border-radius:14px;padding:18px;margin:16px 0}label{display:block;margin:12px 0 6px}input,textarea,select{box-sizing:border-box;border:1px solid #34415d;border-radius:9px;background:#0d1422;color:#fff;padding:12px;font:inherit}input,textarea{width:100%}select{max-width:220px}textarea{min-height:190px;resize:vertical}button{background:#4d79ff;color:white;border:0;border-radius:9px;padding:11px 16px;font:600 15px system-ui;cursor:pointer;margin:10px 8px 0 0}button.secondary{background:#27344e}button:disabled{opacity:.55;cursor:wait}.row{display:flex;gap:12px;align-items:center;flex-wrap:wrap}.status{white-space:pre-wrap;min-height:1.4em;color:#b9c7df}.table-wrap{overflow:auto}table{width:100%;border-collapse:collapse;font-size:14px}th,td{text-align:left;padding:10px 8px;border-bottom:1px solid #2c3650;vertical-align:top}th{color:#a9b7d0}.danger{color:#ffb2b2}.hidden{display:none}.pill{color:#b7c9ff}</style>
<body><h1>V2rayAG private pool</h1><p class="muted">Owner-only management. Subscription links and configuration strings are never shown in this panel's list.</p>
<section id="login" class="card"><label for="key">Admin key</label><input id="key" type="password" autocomplete="current-password"><div class="row"><button id="loginBtn">Unlock</button><span id="loginMsg" class="status"></span></div></section>
<main id="panel" class="hidden">
<section class="card"><h2>Add subscriptions</h2><p class="muted">Paste one HTTPS subscription URL per line. Optionally use <code>Name | URL</code>. Keep this page private; never put the links in chat or source code. Maximum 100 entries per import.</p><label for="entries">URLs</label><textarea id="entries" spellcheck="false" placeholder="Europe 1 | https://provider.example/sub/...&#10;https://provider.example/sub/..."></textarea><div class="row"><button id="importBtn">Add subscriptions</button><button id="refreshBtn" class="secondary">Refresh subscription status</button></div><div id="actionMsg" class="status"></div></section>
<section class="card"><div class="row"><h2 style="margin:0">Pool subscriptions</h2><button id="reloadBtn" class="secondary">Reload list</button><button id="deleteAllBtn" class="secondary danger">Delete all</button></div><p class="muted">A subscription is eligible only when its latest refresh includes usable configuration links and has not reported exhausted quota or expiry. Ping is measured by the app on the user's device, not by this panel.</p><div class="row"><input id="search" type="search" placeholder="Search by subscription name"><select id="statusFilter"><option value="">All statuses</option><option value="active">Active</option><option value="pending">Pending</option><option value="fetch_error">Fetch error</option><option value="expired">Expired</option><option value="exhausted">Quota exhausted</option><option value="unknown_quota">Unknown quota</option><option value="no_configs">No configs</option></select><span id="count" class="muted"></span></div><div class="table-wrap"><table><thead><tr><th>Name</th><th>Status</th><th>Configs</th><th>Quota</th><th>Expiry</th><th>Checked</th><th>Actions</th></tr></thead><tbody id="rows"><tr><td colspan="7" class="muted">Unlock to load.</td></tr></tbody></table></div></section>
<section class="card"><h2>App device access</h2><p class="muted">The app can securely enroll itself the first time the user taps Connect; users do not need a key. Review and revoke app installations here when needed. Manual device keys remain available for controlled testing.</p><label for="deviceName">Device label</label><input id="deviceName" maxlength="80" placeholder="e.g. Little Spring phone"><div class="row"><button id="createDeviceBtn">Issue device key</button><span id="deviceMsg" class="status"></span></div><div id="deviceTokenBox" class="hidden"><label for="deviceToken">Copy this key now; it will not be shown again</label><input id="deviceToken" readonly autocomplete="off"><button id="copyDeviceToken" class="secondary">Copy key</button></div><div class="table-wrap"><table><thead><tr><th>Device</th><th>Created</th><th>Last used</th><th>State</th><th>Action</th></tr></thead><tbody id="deviceRows"><tr><td colspan="5" class="muted">Unlock to load.</td></tr></tbody></table></div></section></main>
<script>
const $=s=>document.querySelector(s);let adminKey=sessionStorage.getItem('v2rayag_pool_admin')||'';const headers=()=>({'Authorization':'Bearer '+adminKey,'Content-Type':'application/json'});function status(el,msg){el.textContent=msg;}
async function api(path,body){const r=await fetch('/admin/api/'+path,{method:body?'POST':'GET',headers:headers(),body:body?JSON.stringify(body):undefined});let d={};try{d=await r.json()}catch{}if(!r.ok||d.success===false)throw new Error(d.error||('Request failed ('+r.status+')'));return d;}
async function load(){const d=await api('subscriptions');const all=d.subscriptions||[];const query=$('#search').value.trim().toLowerCase();const filter=$('#statusFilter').value;const visible=all.filter(s=>(!query||String(s.name+' '+(s.domain||'')).toLowerCase().includes(query))&&(!filter||s.status===filter));const body=$('#rows');body.replaceChildren();for(const s of visible){const tr=document.createElement('tr');for(const v of [s.name,s.status,s.configCount,quota(s),expiry(s),when(s.checkedAt)]){const td=document.createElement('td');td.textContent=v;tr.append(td)}const actions=document.createElement('td');const del=document.createElement('button');del.className='secondary danger';del.textContent='Delete';del.onclick=async()=>{if(!confirm('Delete subscription '+s.name+' and its saved configurations?'))return;del.disabled=true;try{const result=await api('delete',{id:s.id});status($('#actionMsg'),'Deleted '+s.name+' and '+result.deletedConfigs+' saved configuration(s).');await load()}catch(e){status($('#actionMsg'),e.message);del.disabled=false}};actions.append(del);tr.append(actions);body.append(tr)}$('#count').textContent=visible.length+' shown / '+all.length+' total';if(!visible.length){const tr=document.createElement('tr');const td=document.createElement('td');td.colSpan=7;td.textContent=all.length?'No subscriptions match this search/filter.':'No subscriptions yet.';tr.append(td);body.append(tr)}}
async function loadDevices(){const d=await api('devices');const body=$('#deviceRows');body.replaceChildren();for(const item of d.devices||[]){const tr=document.createElement('tr');for(const value of [item.name,when(item.createdAt),when(item.lastUsedAt),item.active?'Active':'Revoked']){const td=document.createElement('td');td.textContent=value;tr.append(td)}const actions=document.createElement('td');if(item.active){const revoke=document.createElement('button');revoke.className='secondary danger';revoke.textContent='Revoke';revoke.onclick=async()=>{if(!confirm('Revoke access for '+item.name+'?'))return;revoke.disabled=true;try{await api('devices/revoke',{id:item.id});status($('#deviceMsg'),'Device access revoked.');await loadDevices()}catch(e){status($('#deviceMsg'),e.message);revoke.disabled=false}};actions.append(revoke)}tr.append(actions);body.append(tr)}if(!(d.devices||[]).length){const tr=document.createElement('tr');const td=document.createElement('td');td.colSpan=5;td.textContent='No device keys issued.';tr.append(td);body.append(tr)}}
function quota(s){if(!s.total)return s.total===0&&s.quotaKnown?'No cap':'Unknown';const left=Math.max(0,s.total-(s.upload||0)-(s.download||0));return fmt(left)+' / '+fmt(s.total)}function fmt(n){if(!Number.isFinite(n))return'Unknown';const u=['B','KB','MB','GB','TB'];let i=0;while(n>=1024&&i<u.length-1){n/=1024;i++}return n.toFixed(i?1:0)+' '+u[i]}function expiry(s){return s.expiresAt?new Date(s.expiresAt*1000).toLocaleString():'Unknown'}function when(t){return t?new Date(t).toLocaleString():'Never'}
$('#loginBtn').onclick=async()=>{adminKey=$('#key').value.trim();if(!adminKey)return status($('#loginMsg'),'Enter the admin key.');sessionStorage.setItem('v2rayag_pool_admin',adminKey);try{await load();await loadDevices();$('#login').classList.add('hidden');$('#panel').classList.remove('hidden');status($('#loginMsg'),'')}catch(e){sessionStorage.removeItem('v2rayag_pool_admin');adminKey='';status($('#loginMsg'),e.message)}};
$('#reloadBtn').onclick=async()=>{try{await load();status($('#actionMsg'),'List updated.')}catch(e){status($('#actionMsg'),e.message)}};
$('#search').addEventListener('input',()=>load().catch(e=>status($('#actionMsg'),e.message)));
$('#statusFilter').addEventListener('change',()=>load().catch(e=>status($('#actionMsg'),e.message)));
$('#deleteAllBtn').onclick=async()=>{if(!confirm('Delete ALL pool subscriptions and their saved configurations? This cannot be undone.'))return;const b=$('#deleteAllBtn');b.disabled=true;try{const result=await api('delete-all',{confirm:true});status($('#actionMsg'),'Deleted '+result.deletedSubscriptions+' subscription(s) and '+result.deletedConfigs+' configuration(s).');await load()}catch(e){status($('#actionMsg'),e.message)}finally{b.disabled=false}};
$('#importBtn').onclick=async()=>{const text=$('#entries').value.trim();if(!text)return status($('#actionMsg'),'Paste at least one URL.');const markers=text.match(/Sub\\s+\\d+\\s*\\|\\s*https/gi)||[];const lines=(markers.length>1?text.split(/(?=Sub\\s+\\d+\\s*\\|\\s*https)/i):text.split(/\\r\\n|[\\n\\r\\u2028\\u2029]/)).map(x=>x.trim()).filter(Boolean);if(lines.length>100)return status($('#actionMsg'),'Maximum 100 URLs per import.');$('#importBtn').disabled=true;try{const d=await api('import',{lines});const rejected=d.errors||[];status($('#actionMsg'),'Processed '+lines.length+' input row(s); added '+d.added+' new subscription(s); '+d.duplicates+' duplicate(s) skipped; '+rejected.length+' rejected.'+(rejected.length?' Check input lines: '+rejected.map(x=>x.line).join(', '):'')+' Refresh status when ready.');$('#entries').value='';await load()}catch(e){status($('#actionMsg'),e.message)}finally{$('#importBtn').disabled=false}};
$('#refreshBtn').onclick=async()=>{const b=$('#refreshBtn');b.disabled=true;let cursor=null,done=0;try{do{const d=await api('refresh',{cursor,limit:10});cursor=d.cursor||null;done+=d.checked;status($('#actionMsg'),'Refreshing '+done+' subscription(s)…');await load()}while(cursor);status($('#actionMsg'),'Refresh complete: '+done+' checked. Unknown quota or unreachable subscriptions are not offered to the app.')}catch(e){status($('#actionMsg'),'Stopped after '+done+' checks: '+e.message)}finally{b.disabled=false}};
$('#createDeviceBtn').onclick=async()=>{const name=$('#deviceName').value.trim();if(!name)return status($('#deviceMsg'),'Enter a label for this device.');const b=$('#createDeviceBtn');b.disabled=true;try{const d=await api('devices/create',{name});$('#deviceToken').value=d.token;$('#deviceTokenBox').classList.remove('hidden');$('#deviceName').value='';status($('#deviceMsg'),'Key created. Copy it now; it cannot be recovered later.');await loadDevices()}catch(e){status($('#deviceMsg'),e.message)}finally{b.disabled=false}};
$('#copyDeviceToken').onclick=async()=>{const token=$('#deviceToken').value;if(!token)return;try{await navigator.clipboard.writeText(token);status($('#deviceMsg'),'Key copied. Paste it only into the intended V2rayAG app.')}catch{const field=$('#deviceToken');field.focus();field.select();status($('#deviceMsg'),'Select and copy the key, then paste it into the intended app.')}};
if(adminKey){$('#key').value=adminKey;$('#loginBtn').click()}
</script></body></html>`;

function json(data, status = 200, headers = {}) {
  return new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", "access-control-allow-origin": "*", "access-control-allow-methods": "GET,POST,OPTIONS", "access-control-allow-headers": "authorization,content-type", ...headers } });
}
function randomInt(max) { return Math.floor(Math.random() * max); }
function shuffle(array) { for (let i = array.length - 1; i > 0; i--) { const j = randomInt(i + 1); [array[i], array[j]] = [array[j], array[i]]; } return array; }
async function digest(text) { const bytes = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text)); return [...new Uint8Array(bytes)].map(x => x.toString(16).padStart(2, "0")).join("").slice(0, 24); }
async function sha256Hex(text) { const bytes = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text)); return [...new Uint8Array(bytes)].map(x => x.toString(16).padStart(2, "0")).join(""); }
function randomToken() { const bytes = crypto.getRandomValues(new Uint8Array(32)); return [...bytes].map(x => x.toString(16).padStart(2, "0")).join(""); }
async function authenticateDevice(request, env) {
  const authorization = request.headers.get("authorization") || "";
  const token = authorization.startsWith("Bearer ") ? authorization.slice(7).trim() : "";
  if (!/^[0-9a-f]{64}$/i.test(token)) return null;
  const hash = await sha256Hex(token.toLowerCase());
  const record = await env.POOL.get(DEVICE_PREFIX + hash, "json");
  return record?.active === true ? { hash, record } : null;
}
async function allowAutoEnrollment(request, env) {
  const ip = request.headers.get("cf-connecting-ip");
  if (!ip) return false;
  const day = Math.floor(Date.now() / 86400000);
  const key = RATE_PREFIX + "enroll:" + await digest(`${ip}\n${day}`);
  const count = Number(await env.POOL.get(key) || 0);
  if (!Number.isFinite(count) || count >= MAX_AUTO_ENROLLMENTS_PER_DAY_PER_IP) return false;
  await env.POOL.put(key, String(count + 1), { expirationTtl: 172800 });
  return true;
}
async function enrollAppDevice(request, env) {
  if (!(await allowAutoEnrollment(request, env))) {
    return json({ success:false, error:"Too many new app setups from this network today. Try again tomorrow." }, 429);
  }
  await parseBody(request); // Require a small JSON POST; do not accept enrollment via navigation or GET.
  const token = randomToken();
  const hash = await sha256Hex(token);
  await env.POOL.put(DEVICE_PREFIX + hash, JSON.stringify({
    name:"V2rayAG app (automatic)", active:true, autoProvisioned:true,
    createdAt:Date.now(), lastUsedAt:null,
  }));
  return json({ success:true, token });
}
async function allowLeaseRequest(request, env, deviceHash) {
  const ip = request.headers.get("cf-connecting-ip") || "unknown";
  const bucket = Math.floor(Date.now() / 60000);
  const key = RATE_PREFIX + await digest(`${deviceHash}\n${ip}\n${bucket}`);
  const count = Number(await env.POOL.get(key) || 0);
  if (!Number.isFinite(count) || count >= MAX_LEASES_PER_MINUTE) return false;
  await env.POOL.put(key, String(count + 1), { expirationTtl: 120 });
  return true;
}
function constantTimeEqual(a, b) { if (a.length !== b.length) return false; let diff = 0; for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i); return diff === 0; }
function adminOK(request, env) { const key = request.headers.get("authorization") || ""; const expected = env.ADMIN_KEY ? `Bearer ${env.ADMIN_KEY}` : ""; return Boolean(expected && constantTimeEqual(key, expected)); }
function validPublicHttps(raw) {
  try {
    const u = new URL(raw);
    if (u.protocol !== "https:" || u.username || u.password || u.hostname.length > 253) return false;
    const h = u.hostname.toLowerCase().replace(/^\[|\]$/g, "");
    if (!h.includes(".") || h.includes(":") || h === "localhost" || h.endsWith(".localhost") || h.endsWith(".local")) return false;
    if (/^\d{1,3}(?:\.\d{1,3}){3}$/.test(h)) return false;
    return true;
  } catch { return false; }
}
async function readLimited(response, cap = MAX_SUB_BYTES) {
  const length = Number(response.headers.get("content-length") || 0);
  if (length > cap) throw new Error("Subscription response is too large");
  if (!response.body) return "";
  const reader = response.body.getReader(); const chunks = []; let size = 0;
  try { while (true) { const { value, done } = await reader.read(); if (done) break; size += value.byteLength; if (size > cap) { await reader.cancel(); throw new Error("Subscription response is too large"); } chunks.push(value); } }
  finally { try { reader.releaseLock(); } catch {} }
  const all = new Uint8Array(size); let offset = 0; for (const chunk of chunks) { all.set(chunk, offset); offset += chunk.length; }
  return new TextDecoder().decode(all);
}
function decodeSubscription(text) {
  const raw = text.trim();
  if (SUPPORTED_URI.test(raw) || raw.split(/\r?\n/).some(line => SUPPORTED_URI.test(line.trim()))) return raw;
  let compact = raw.replace(/\s+/g, "").replace(/-/g, "+").replace(/_/g, "/"); compact += "=".repeat((4 - compact.length % 4) % 4);
  try { const bin = atob(compact); const bytes = Uint8Array.from(bin, c => c.charCodeAt(0)); return new TextDecoder().decode(bytes); } catch { return raw; }
}
function parseUserInfo(headers) {
  const raw = headers.get("subscription-userinfo") || headers.get("subscription-info") || "";
  const values = {};
  for (const part of raw.split(/[;,\s]+/)) { const m = part.match(/^(upload|download|total|expire)=(\d+)$/i); if (m) values[m[1].toLowerCase()] = Number(m[2]); }
  const totalPresent = Object.prototype.hasOwnProperty.call(values, "total");
  const used = (values.upload || 0) + (values.download || 0);
  const expired = Boolean(values.expire && values.expire * 1000 <= Date.now());
  const exhausted = totalPresent && values.total > 0 && used >= values.total;
  const quotaKnown = totalPresent;
  return { upload: values.upload || 0, download: values.download || 0, total: totalPresent ? values.total : null, quotaKnown, expiresAt: values.expire || null, expired, exhausted };
}
function extractUris(text) {
  const decoded = decodeSubscription(text);
  const lines = decoded.split(/\r?\n/).map(x => x.trim()).filter(Boolean);
  const found = new Set();
  for (const line of lines) {
    const m = line.match(/(?:^|\s)((?:vless|vmess|trojan|ss|shadowsocks|socks|http|https|hysteria|hysteria2|tuic|wireguard|socks5):\/\/[^\s"'<>]+)/i);
    if (m && SUPPORTED_URI.test(m[1])) found.add(m[1]);
  }
  return [...found];
}
async function fetchSubscription(url) {
  let current = new URL(url); let response;
  for (let hop = 0; hop <= 3; hop++) {
    if (!validPublicHttps(current.href)) throw new Error("Unsafe subscription URL or redirect");
    response = await fetch(current.href, { method: "GET", redirect: "manual", headers: { "accept": "text/plain, */*" }, signal: AbortSignal.timeout(9000) });
    if (![301,302,303,307,308].includes(response.status)) break;
    const location = response.headers.get("location"); if (!location || hop === 3) throw new Error("Too many or invalid redirects");
    current = new URL(location, current);
  }
  if (!response || !response.ok) throw new Error(`Subscription returned HTTP ${response?.status || 0}`);
  const text = await readLimited(response);
  const usage = parseUserInfo(response.headers);
  const uris = extractUris(text);
  const status = usage.expired ? "expired" : usage.exhausted ? "exhausted" : !usage.quotaKnown ? "unknown_quota" : uris.length ? "active" : "no_configs";
  return { usage, uris, status };
}
async function refreshRecord(env, rec) {
  try {
    const result = await fetchSubscription(rec.url);
    const previousIds = new Set(rec.candidateIds || []); const ids = [];
    for (const uri of result.uris) {
      const id = await digest(`${rec.id}\n${uri}`);
      ids.push(id);
      if (!previousIds.has(id)) await env.POOL.put(PROFILE_PREFIX + id, JSON.stringify({ id, subId: rec.id, uri }));
    }
    const { error: _oldError, ...cleanRec } = rec;
    const next = { ...cleanRec, candidateIds: ids, configCount: ids.length, status: result.status, upload: result.usage.upload, download: result.usage.download, total: result.usage.total, quotaKnown: result.usage.quotaKnown, expiresAt: result.usage.expiresAt, checkedAt: Date.now(), domain: new URL(rec.url).hostname };
    await env.POOL.put(SUB_PREFIX + rec.id, JSON.stringify(next));
    return next;
  } catch (error) {
    const next = { ...rec, status: "fetch_error", checkedAt: Date.now(), error: String(error?.message || "fetch failed").slice(0, 120) };
    await env.POOL.put(SUB_PREFIX + rec.id, JSON.stringify(next));
    return next;
  }
}
async function listSubscriptions(env) {
  const page = await env.POOL.list({ prefix: SUB_PREFIX, limit: 1000 });
  const items = await Promise.all(page.keys.map(k => env.POOL.get(k.name, "json")));
  return items.filter(Boolean);
}
async function deleteKeysByPrefix(env, prefix) {
  let deleted = 0;
  while (true) {
    const page = await env.POOL.list({ prefix, limit: 1000 });
    if (!page.keys.length) break;
    for (let i = 0; i < page.keys.length; i += 50) {
      await Promise.all(page.keys.slice(i, i + 50).map(k => env.POOL.delete(k.name)));
    }
    deleted += page.keys.length;
    if (page.list_complete) break;
  }
  return deleted;
}
async function deleteProfilesForSub(env, subId) {
  let cursor;
  let deleted = 0;
  do {
    const page = await env.POOL.list({ prefix: PROFILE_PREFIX, limit: 1000, ...(cursor ? { cursor } : {}) });
    const records = await Promise.all(page.keys.map(k => env.POOL.get(k.name, "json")));
    const names = page.keys.filter((_, i) => records[i]?.subId === subId).map(k => k.name);
    for (let i = 0; i < names.length; i += 50) {
      await Promise.all(names.slice(i, i + 50).map(name => env.POOL.delete(name)));
    }
    deleted += names.length;
    if (page.list_complete) break;
    cursor = page.cursor || undefined;
  } while (cursor);
  return deleted;
}
async function deleteLeasesForSub(env, subId) {
  const page = await env.POOL.list({ prefix: LEASE_PREFIX, limit: 1000 });
  const records = await Promise.all(page.keys.map(k => env.POOL.get(k.name, "json")));
  const names = page.keys.filter((_, i) => records[i]?.subId === subId).map(k => k.name);
  await Promise.all(names.map(name => env.POOL.delete(name)));
  return names.length;
}
async function deleteLeasesForDevice(env, deviceHash) {
  const page = await env.POOL.list({ prefix: LEASE_PREFIX, limit: 1000 });
  const records = await Promise.all(page.keys.map(k => env.POOL.get(k.name, "json")));
  const names = page.keys.filter((_, i) => records[i]?.deviceHash === deviceHash).map(k => k.name);
  await Promise.all(names.map(name => env.POOL.delete(name)));
  return names.length;
}
function adminSummary(rec) {
  return { id: rec.id, name: rec.name, domain: rec.domain || (rec.url ? new URL(rec.url).hostname : ""), status: rec.status || "pending", configCount: rec.configCount || 0, upload: rec.upload || 0, download: rec.download || 0, total: rec.total, quotaKnown: Boolean(rec.quotaKnown), expiresAt: rec.expiresAt || null, checkedAt: rec.checkedAt || null };
}
async function parseBody(request) {
  const text = await readLimited(request, MAX_BODY);
  try { return JSON.parse(text || "{}"); } catch { throw new Error("Invalid JSON request"); }
}
async function adminApi(request, env, path) {
  if (!adminOK(request, env)) return json({ success:false, error: env.ADMIN_KEY ? "Unauthorized" : "Admin key has not been configured" }, env.ADMIN_KEY ? 401 : 503);
  if (request.method === "GET" && path === "/admin/api/devices") {
    const page = await env.POOL.list({ prefix: DEVICE_PREFIX, limit: 1000 });
    const items = await Promise.all(page.keys.map(async key => {
      const record = await env.POOL.get(key.name, "json");
      if (!record) return null;
      return { id: key.name.slice(DEVICE_PREFIX.length), name: record.name, active: record.active === true, createdAt: record.createdAt || null, lastUsedAt: record.lastUsedAt || null };
    }));
    return json({ success:true, devices:items.filter(Boolean).sort((a,b)=>(b.createdAt||0)-(a.createdAt||0)) });
  }
  if (request.method === "POST" && path === "/admin/api/devices/create") {
    const body = await parseBody(request);
    const name = String(body.name || "").replace(/[\x00-\x1F\x7F]/g, " ").trim().slice(0, 80);
    if (!name) return json({ success:false, error:"A device label is required" }, 400);
    const page = await env.POOL.list({ prefix:DEVICE_PREFIX, limit:1000 });
    const records = await Promise.all(page.keys.map(key => env.POOL.get(key.name, "json")));
    if (records.filter(record => record?.active === true && record?.autoProvisioned !== true).length >= 100) return json({ success:false, error:"Maximum 100 active manually issued device keys" }, 400);
    const token = randomToken();
    const id = await sha256Hex(token);
    await env.POOL.put(DEVICE_PREFIX + id, JSON.stringify({ name, active:true, createdAt:Date.now(), lastUsedAt:null }));
    return json({ success:true, id, name, token });
  }
  if (request.method === "POST" && path === "/admin/api/devices/revoke") {
    const body = await parseBody(request);
    const id = String(body.id || "");
    if (!/^[0-9a-f]{64}$/.test(id)) return json({ success:false, error:"Invalid device id" }, 400);
    const key = DEVICE_PREFIX + id;
    const record = await env.POOL.get(key, "json");
    if (!record) return json({ success:false, error:"Device not found" }, 404);
    await env.POOL.put(key, JSON.stringify({ ...record, active:false, revokedAt:Date.now() }));
    const deletedLeases = await deleteLeasesForDevice(env, id);
    return json({ success:true, revoked:true, deletedLeases });
  }
  if (request.method === "GET" && path === "/admin/api/subscriptions") {
    const subs = await listSubscriptions(env);
    return json({ success:true, subscriptions: subs.map(adminSummary).sort((a,b)=>a.name.localeCompare(b.name)) });
  }
  if (request.method === "POST" && path === "/admin/api/delete") {
    const body = await parseBody(request);
    const id = String(body.id || "");
    if (!/^[0-9a-f]{24}$/.test(id)) return json({ success:false, error:"Invalid subscription id" }, 400);
    const key = SUB_PREFIX + id;
    const rec = await env.POOL.get(key, "json");
    if (!rec) return json({ success:false, error:"Subscription not found" }, 404);
    const deletedConfigs = await deleteProfilesForSub(env, id);
    await deleteLeasesForSub(env, id);
    await env.POOL.delete(key);
    return json({ success:true, deletedSubscriptions:1, deletedConfigs });
  }
  if (request.method === "POST" && path === "/admin/api/delete-all") {
    const body = await parseBody(request);
    if (body.confirm !== true) return json({ success:false, error:"Explicit confirmation is required" }, 400);
    const deletedConfigs = await deleteKeysByPrefix(env, PROFILE_PREFIX);
    const deletedSubscriptions = await deleteKeysByPrefix(env, SUB_PREFIX);
    await deleteKeysByPrefix(env, LEASE_PREFIX);
    return json({ success:true, deletedSubscriptions, deletedConfigs });
  }
  if (request.method === "POST" && path === "/admin/api/import") {
    const body = await parseBody(request); const lines = Array.isArray(body.lines) ? body.lines : [];
    if (!lines.length || lines.length > MAX_IMPORT) return json({ success:false, error:`Provide 1-${MAX_IMPORT} URL lines per import` }, 400);
    let added = 0, duplicates = 0; const errors = [];
    for (let i=0;i<lines.length;i++) {
      const line = String(lines[i] || "").trim(); if (!line) continue;
      const sep = line.indexOf("|"); const name = (sep >= 0 ? line.slice(0,sep) : "").trim(); const url = (sep >= 0 ? line.slice(sep+1) : line).trim();
      if (!validPublicHttps(url)) { errors.push({ line:i+1, message:"Only public HTTPS subscription URLs are allowed" }); continue; }
      const id = await digest(url); const key = SUB_PREFIX + id; const existing = await env.POOL.get(key, "json");
      if (existing) { duplicates++; continue; }
      const rec = { id, name: name.slice(0,80) || `${new URL(url).hostname} ${id.slice(0,6)}`, domain:new URL(url).hostname, url, status:"pending", candidateIds:[], configCount:0, createdAt:Date.now() };
      await env.POOL.put(key, JSON.stringify(rec)); added++;
    }
    return json({ success:true, added, duplicates, errors });
  }
  if (request.method === "POST" && path === "/admin/api/refresh") {
    const body = await parseBody(request); const cursor = typeof body.cursor === "string" ? body.cursor : undefined; const limit = Math.max(1, Math.min(REFRESH_BATCH, Number(body.limit)||REFRESH_BATCH));
    const page = await env.POOL.list({ prefix:SUB_PREFIX, limit, ...(cursor ? {cursor} : {}) });
    const recs = await Promise.all(page.keys.map(k=>env.POOL.get(k.name,"json")));
    const refreshed = await Promise.all(recs.filter(Boolean).map(r=>refreshRecord(env,r)));
    return json({ success:true, checked:refreshed.length, eligible:refreshed.filter(r=>r.status==="active").length, cursor:page.list_complete?null:page.cursor||null, listComplete:Boolean(page.list_complete) });
  }
  return json({ success:false, error:"Not found" }, 404);
}
async function acquirePoolLease(request, env) {
  const device = await authenticateDevice(request, env);
  if (!device) return json({ success:false, error:"This app installation is not authorized. Contact support if the problem persists." }, 401);
  if (!(await allowLeaseRequest(request, env, device.hash))) {
    return json({ success:false, error:"Connection attempts are temporarily limited. Please wait a minute and try again." }, 429);
  }
  await env.POOL.put(DEVICE_PREFIX + device.hash, JSON.stringify({ ...device.record, lastUsedAt:Date.now() }));
  const body = await parseBody(request);
  const excluded = new Set(Array.isArray(body.exclude)
    ? body.exclude.filter(id => typeof id === "string" && /^[0-9a-f]{24}$/.test(id)).slice(0, 100)
    : []);
  const subs = await listSubscriptions(env);
  if (!subs.length) return json({ success:false, error:"No available server is configured yet." }, 503);
  // Refresh a bounded randomized slice. The API returns one lease only, never a catalog or batch of URIs.
  const fresh = await Promise.all(shuffle(subs).slice(0, REFRESH_BATCH).map(rec => refreshRecord(env, rec)));
  const active = fresh.filter(r => r.status === "active" && r.quotaKnown && r.candidateIds?.length && (!r.expiresAt || r.expiresAt * 1000 > Date.now()));
  const byId = new Map(active.map(rec => [rec.id, rec]));
  const ids = shuffle(active.flatMap(r => r.candidateIds)).filter(id => !excluded.has(id));
  for (const id of ids) {
    const profile = await env.POOL.get(PROFILE_PREFIX + id, "json");
    const sub = profile?.subId ? byId.get(profile.subId) : null;
    if (!profile?.uri || !sub) continue;
    const leaseId = randomToken();
    const lease = { subId: sub.id, profileId: id, deviceHash:device.hash, createdAt: Date.now() };
    await env.POOL.put(LEASE_PREFIX + leaseId, JSON.stringify(lease), { expirationTtl: LEASE_TTL_SECONDS });
    return json({
      success:true,
      leaseId,
      candidate:{
        id,
        uri:profile.uri,
        subscriptionName:sub.name,
        expiresAt:sub.expiresAt||null,
        quotaKnown:Boolean(sub.quotaKnown),
        upload:sub.upload||0,
        download:sub.download||0,
        total:sub.total,
      },
      leaseExpiresInSeconds:LEASE_TTL_SECONDS,
    });
  }
  return json({ success:false, error:"No refreshed subscription currently has usable quota and configurations." }, 503);
}
async function releasePoolLease(request, env) {
  const device = await authenticateDevice(request, env);
  if (!device) return json({ success:false, error:"Unauthorized" }, 401);
  const body = await parseBody(request);
  const leaseId = typeof body.leaseId === "string" ? body.leaseId : "";
  if (!/^[0-9a-f]{64}$/.test(leaseId)) return json({ success:false, error:"Invalid lease token." }, 400);
  const key = LEASE_PREFIX + leaseId;
  const existing = await env.POOL.get(key, "json");
  if (existing && existing.deviceHash !== device.hash) return json({ success:false, error:"Lease not found" }, 404);
  if (existing) await env.POOL.delete(key);
  return json({ success:true, released:Boolean(existing) });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url); const path = url.pathname.replace(/\/$/, "") || "/";
    if (request.method === "OPTIONS") return new Response(null,{status:204,headers:{"access-control-allow-origin":"*","access-control-allow-methods":"GET,POST,OPTIONS","access-control-allow-headers":"authorization,content-type","access-control-max-age":"600"}});
    if (path === "/healthz" && request.method === "GET") return json({ ok:true, service:"V2rayAG private pool", version:4 });
    if (path === "/admin" && request.method === "GET") return new Response(ADMIN_HTML,{headers:{"content-type":"text/html; charset=utf-8","cache-control":"no-store","x-content-type-options":"nosniff","content-security-policy":"default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'self'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'"}});
    if (path.startsWith("/admin/api/")) {
      if (request.method !== "GET" && request.method !== "POST") return json({success:false,error:"Method not allowed"},405);
      return adminApi(request,env,path);
    }
    if (path === "/v1/app/devices/enroll" && request.method === "POST") return enrollAppDevice(request,env);
    if (path === "/v1/pool/candidates") return json({success:false,error:"This endpoint has been retired."},410);
    if (path === "/v1/pool/leases" && request.method === "POST") return acquirePoolLease(request,env);
    if (path === "/v1/pool/leases/release" && request.method === "POST") return releasePoolLease(request,env);
    return json({success:false,error:"Not found"},404);
  }
};
