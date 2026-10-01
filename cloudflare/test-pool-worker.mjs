import assert from 'node:assert/strict';
import worker from './v2rayag-pool-worker.mjs';

class MockKV {
  data = new Map();
  async get(key, type) { const value = this.data.get(key); return value == null ? null : type === 'json' ? JSON.parse(value) : value; }
  async put(key, value) { this.data.set(key, String(value)); }
  async delete(key) { this.data.delete(key); }
  async list({ prefix = '', limit = 1000 } = {}) {
    const keys = [...this.data.keys()].filter(k => k.startsWith(prefix)).slice(0, limit).map(name => ({ name }));
    return { keys, list_complete: true, cursor: '' };
  }
}
const env = { POOL: new MockKV(), ADMIN_KEY: 'test-admin-key' };
const call = (path, method = 'GET', body, headers = {}) => worker.fetch(new Request('https://pool.test' + path, { method, headers, body: body == null ? undefined : JSON.stringify(body) }), env);
let r = await call('/healthz'); assert.equal(r.status, 200); assert.equal((await r.json()).version, 4);
r = await call('/admin/api/subscriptions'); assert.equal(r.status, 401);
r = await call('/admin/api/subscriptions', 'GET', null, { authorization: 'Bearer test-admin-key' }); assert.equal(r.status, 200); assert.deepEqual((await r.json()).subscriptions, []);
r = await call('/admin/api/import', 'POST', { lines: ['http://not-secure.example/sub/a'] }, { authorization: 'Bearer test-admin-key', 'content-type': 'application/json' }); assert.equal(r.status, 200); assert.equal((await r.json()).errors.length, 1);
r = await call('/admin/api/import', 'POST', { lines: ['Test A | https://example.com/sub/a', 'https://example.com/sub/a'] }, { authorization: 'Bearer test-admin-key', 'content-type': 'application/json' }); assert.equal(r.status, 200); let d = await r.json(); assert.equal(d.added, 1); assert.equal(d.duplicates, 1);
r = await call('/admin/api/subscriptions', 'GET', null, { authorization: 'Bearer test-admin-key' }); d = await r.json(); assert.equal(d.subscriptions.length, 1); assert.equal(d.subscriptions[0].name, 'Test A'); assert.equal('url' in d.subscriptions[0], false);
const subId = d.subscriptions[0].id;
await env.POOL.put('profile:test-profile-000000000000', JSON.stringify({ id:'test-profile', subId, uri:'vless://secret-example' }));
r = await call('/admin/api/delete', 'POST', { id:subId }, { authorization:'Bearer test-admin-key', 'content-type':'application/json' }); assert.equal(r.status,200); d = await r.json(); assert.equal(d.deletedSubscriptions,1); assert.equal(d.deletedConfigs,1);
r = await call('/admin/api/import', 'POST', { lines:['Bulk A | https://example.com/sub/a','Bulk B | https://example.com/sub/b'] }, { authorization:'Bearer test-admin-key', 'content-type':'application/json' }); assert.equal(r.status,200); d = await r.json(); assert.equal(d.added,2);
const subs = await (await call('/admin/api/subscriptions','GET',null,{authorization:'Bearer test-admin-key'})).json();
for (const s of subs.subscriptions) await env.POOL.put('profile:test-'+s.id, JSON.stringify({id:'test',subId:s.id,uri:'vless://secret-example'}));
r = await call('/admin/api/delete-all','POST',{confirm:false},{authorization:'Bearer test-admin-key','content-type':'application/json'}); assert.equal(r.status,400);
r = await call('/admin/api/delete-all','POST',{confirm:true},{authorization:'Bearer test-admin-key','content-type':'application/json'}); assert.equal(r.status,200); d=await r.json(); assert.equal(d.deletedSubscriptions,2); assert.equal(d.deletedConfigs,2);

// Auto-enrollment must remain usable for users behind carrier-grade NAT; no per-IP/day cap.
let appToken;
for (let i=0;i<25;i++) {
  r = await call('/v1/app/devices/enroll','POST',{platform:'android'},{'content-type':'application/json','cf-connecting-ip':'192.0.2.99'});
  assert.equal(r.status,200);
  d = await r.json();
  assert.equal(d.success,true);
  assert.match(d.token,/^[0-9a-f]{64}$/);
  appToken = d.token;
}
assert.equal([...env.POOL.data.keys()].some(k=>k.startsWith('rate:enroll:')),false);

r = await call('/v1/pool/candidates'); assert.equal(r.status,410); // Never publish an enumerable batch endpoint.

await call('/admin/api/import', 'POST', { lines:['Candidate metadata | https://example.com/sub/candidate'] }, { authorization:'Bearer test-admin-key', 'content-type':'application/json' });
const poolSub = (await (await call('/admin/api/subscriptions','GET',null,{authorization:'Bearer test-admin-key'})).json()).subscriptions[0];
const realFetch = globalThis.fetch;
globalThis.fetch = async () => new Response('vless://user@example.com:443?security=tls#Node-A', { status:200, headers:{ 'subscription-userinfo':'upload=100; download=200; total=1000; expire=2000000000' } });
try {
  r = await call('/v1/pool/leases', 'POST', { exclude:[] }, { 'content-type':'application/json', 'cf-connecting-ip':'192.0.2.10', authorization:'Bearer '+appToken });
  assert.equal(r.status, 200); d=await r.json();
  assert.match(d.leaseId,/^[0-9a-f]{64}$/); assert.equal(d.candidate.id.length,24);
  assert.equal(d.candidate.subscriptionName,poolSub.name); assert.equal(d.candidate.total,1000); assert.equal(d.candidate.upload,100);
  assert.equal('url' in d.candidate,false); assert.equal('candidates' in d,false);
  assert.equal((await env.POOL.get('lease:'+d.leaseId,'json')).subId,poolSub.id);
  const leaseId=d.leaseId;
  r = await call('/v1/pool/leases/release','POST',{leaseId},{'content-type':'application/json', authorization:'Bearer '+appToken}); assert.equal(r.status,200); assert.equal((await r.json()).released,true);
  assert.equal(await env.POOL.get('lease:'+leaseId),null);
  r = await call('/v1/pool/leases','POST',{exclude:[d.candidate.id]},{'content-type':'application/json','cf-connecting-ip':'192.0.2.11', authorization:'Bearer '+appToken}); assert.equal(r.status,503);
  for (let i=0;i<12;i++) { r=await call('/v1/pool/leases','POST',{exclude:[]},{'content-type':'application/json','cf-connecting-ip':'192.0.2.12', authorization:'Bearer '+appToken}); assert.equal(r.status,200); }
  r=await call('/v1/pool/leases','POST',{exclude:[]},{'content-type':'application/json','cf-connecting-ip':'192.0.2.12', authorization:'Bearer '+appToken}); assert.equal(r.status,429);
} finally { globalThis.fetch = realFetch; }
r = await call('/admin'); assert.equal(r.status, 200); const html=await r.text(); assert.match(html,/V2rayAG private pool/); const inline=html.match(/<script>([\s\S]*?)<\/script>/)?.[1]; assert.ok(inline); new Function(inline); assert.match(inline,/delete-all/); assert.match(inline,/statusFilter/); assert.match(inline,/markers=text.match/);
const pasted='Sub 0001 | https://one.example/aSub 0002 | https://two.example/b'; const markers=pasted.match(/Sub\s+\d+\s*\|\s*https/gi)||[]; const parsed=(markers.length>1?pasted.split(/(?=Sub\s+\d+\s*\|\s*https)/i):pasted.split(/\r\n|[\n\r\u2028\u2029]/)).map(x=>x.trim()).filter(Boolean); assert.equal(parsed.length,2); assert.match(parsed[1],/^Sub 0002/);
console.log('Worker admin, flattened import, unlimited app enrollment, one-profile lease throttling, release, and deletion tests passed.');
