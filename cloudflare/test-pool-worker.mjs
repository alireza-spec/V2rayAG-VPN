import assert from 'node:assert/strict';
import worker from './v2rayag-pool-worker.mjs';

class MockKV {
  data = new Map(); puts = 0;
  async get(key, type) { const value = this.data.get(key); return value == null ? null : type === 'json' ? JSON.parse(value) : value; }
  async put(key, value) { this.puts++; this.data.set(key, String(value)); }
  async delete(key) { this.data.delete(key); }
  async list({ prefix = '', limit = 1000 } = {}) {
    const keys = [...this.data.keys()].filter(k => k.startsWith(prefix)).slice(0, limit).map(name => ({ name }));
    return { keys, list_complete: true, cursor: '' };
  }
}
class MockD1 {
  devices = new Map(); leases = new Map(); profiles = new Map(); states = new Map(); locks = new Map(); subscriptions = new Map(); meta = new Map();
  prepare(sql) { return new MockStatement(this, sql.replace(/\s+/g, ' ').trim()); }
  async batch(statements) { const results=[]; for(const statement of statements)results.push(await statement.run()); return results; }
}
class MockStatement {
  constructor(db, sql) { this.db = db; this.sql = sql; this.values = []; }
  bind(...values) { this.values = values; return this; }
  async first() {
    const v = this.values, s = this.sql, d = this.db;
    if (s.startsWith('SELECT value FROM app_meta WHERE key = ?')) { const value=d.meta.get(v[0]); return value == null ? null : {value}; }
    if (s.startsWith('SELECT sub_id FROM pool_subscriptions WHERE sub_id = ?')) return d.subscriptions.has(v[0]) ? {sub_id:v[0]} : null;
    if (s.startsWith('SELECT record_json FROM pool_subscriptions WHERE sub_id = ?')) { const record_json=d.subscriptions.get(v[0]); return record_json ? {record_json} : null; }
    if (s.startsWith('SELECT record_json FROM app_devices WHERE device_hash = ?')) { const row = d.devices.get(v[0]); return row ? { record_json:row.record_json } : null; }
    if (s.startsWith('SELECT state_json, checked_at FROM pool_subscription_state WHERE sub_id = ?')) return d.states.get(v[0]) || null;
    if (s.startsWith('SELECT profile_id, sub_id, uri FROM pool_profiles WHERE profile_id = ?')) return d.profiles.get(v[0]) || null;
    if (s.startsWith('SELECT device_hash FROM app_leases WHERE lease_id = ?')) { const row=d.leases.get(v[0]); return row && row.expires_at>v[1] ? {device_hash:row.device_hash} : null; }
    throw new Error('MockD1 unsupported first: '+s);
  }
  async all() {
    const s=this.sql,d=this.db;
    if (s.startsWith('SELECT sub_id, record_json FROM pool_subscriptions')) return {results:[...d.subscriptions].map(([sub_id,record_json])=>({sub_id,record_json}))};
    if (s.startsWith('SELECT sub_id, state_json, checked_at FROM pool_subscription_state')) return {results:[...d.states].map(([sub_id,row])=>({sub_id,...row}))};
    if (s.startsWith('SELECT device_hash, record_json FROM app_devices')) return {results:[...d.devices].map(([device_hash,row])=>({device_hash,...row}))};
    throw new Error('MockD1 unsupported all: '+s);
  }
  async run() {
    const v=this.values,s=this.sql,d=this.db;
    if (s.startsWith('INSERT INTO app_meta')) { d.meta.set(v[0],v[1]); return {meta:{changes:1}}; }
    if (s.startsWith('INSERT OR IGNORE INTO pool_subscriptions')) { if(d.subscriptions.has(v[0]))return {meta:{changes:0}}; d.subscriptions.set(v[0],v[1]); return {meta:{changes:1}}; }
    if (s.startsWith('INSERT INTO pool_subscriptions')) { d.subscriptions.set(v[0],v[1]); return {meta:{changes:1}}; }
    if (s.startsWith('DELETE FROM pool_subscriptions WHERE sub_id = ?')) { const n=d.subscriptions.delete(v[0]); return {meta:{changes:Number(n)}}; }
    if (s==='DELETE FROM pool_subscriptions') { const n=d.subscriptions.size; d.subscriptions.clear(); return {meta:{changes:n}}; }
    if (s.startsWith('INSERT INTO app_devices')) { if(d.devices.has(v[0])) throw new Error('unique device'); d.devices.set(v[0],{record_json:v[1],created_at:v[2],active:1}); return {meta:{changes:1}}; }
    if (s.startsWith('UPDATE app_devices')) { const row=d.devices.get(v[1]); if(!row)return {meta:{changes:0}}; d.devices.set(v[1],{...row,record_json:v[0],active:v[2]}); return {meta:{changes:1}}; }
    if (s.startsWith('INSERT OR IGNORE INTO pool_profiles')) { if(d.profiles.has(v[0]))return {meta:{changes:0}}; d.profiles.set(v[0],{profile_id:v[0],sub_id:v[1],uri:v[2]}); return {meta:{changes:1}}; }
    if (s.startsWith('INSERT INTO pool_subscription_state')) { d.states.set(v[0],{state_json:v[1],checked_at:v[2]}); return {meta:{changes:1}}; }
    if (s.startsWith('INSERT INTO pool_refresh_locks')) { const prev=d.locks.get(v[0]); if(prev && prev>v[2])return {meta:{changes:0}}; d.locks.set(v[0],v[1]); return {meta:{changes:1}}; }
    if (s.startsWith('DELETE FROM pool_refresh_locks WHERE sub_id = ?')) { const n=d.locks.delete(v[0]); return {meta:{changes:Number(n)}}; }
    if (s.startsWith('INSERT INTO app_leases')) { d.leases.set(v[0],{lease_id:v[0],sub_id:v[1],profile_id:v[2],device_hash:v[3],created_at:v[4],expires_at:v[5]}); return {meta:{changes:1}}; }
    if (s.startsWith('DELETE FROM app_leases WHERE expires_at <= ?')) { let n=0; for(const [k,row] of d.leases)if(row.expires_at<=v[0]){d.leases.delete(k);n++} return {meta:{changes:n}}; }
    if (s.startsWith('DELETE FROM app_leases WHERE lease_id = ?')) { const n=d.leases.delete(v[0]); return {meta:{changes:Number(n)}}; }
    if (s.startsWith('DELETE FROM app_leases WHERE device_hash = ?')) return this.deleteWhere(d.leases,row=>row.device_hash===v[0]);
    if (s.startsWith('DELETE FROM app_leases WHERE sub_id = ?')) return this.deleteWhere(d.leases,row=>row.sub_id===v[0]);
    for (const table of ['pool_profiles','pool_subscription_state','pool_refresh_locks','app_leases']) {
      if (s===`DELETE FROM ${table}`) { const map={pool_profiles:d.profiles,pool_subscription_state:d.states,pool_refresh_locks:d.locks,app_leases:d.leases}[table]; const n=map.size; map.clear(); return {meta:{changes:n}}; }
      if (s.startsWith(`DELETE FROM ${table} WHERE sub_id = ?`)) { const map={pool_profiles:d.profiles,pool_subscription_state:d.states,pool_refresh_locks:d.locks,app_leases:d.leases}[table]; return this.deleteWhere(map,row=>row.sub_id===v[0]); }
    }
    throw new Error('MockD1 unsupported run: '+s);
  }
  deleteWhere(map,predicate) { let n=0; for(const [k,row] of map)if(predicate(row)){map.delete(k);n++} return {meta:{changes:n}}; }
}
const env = { POOL: new MockKV(), APP_DB:new MockD1(), ADMIN_KEY: 'test-admin-key' };
const call = (path, method = 'GET', body, headers = {}) => worker.fetch(new Request('https://pool.test' + path, { method, headers, body: body == null ? undefined : JSON.stringify(body) }), env);
const legacyEnv={POOL:new MockKV(),APP_DB:new MockD1(),ADMIN_KEY:'test-admin-key'};
await legacyEnv.POOL.put('sub:0123456789abcdef01234567',JSON.stringify({id:'0123456789abcdef01234567',name:'Legacy',url:'https://legacy.example/sub',status:'active',candidateIds:[],createdAt:1}));
const migrated=await worker.fetch(new Request('https://pool.test/admin/api/subscriptions',{headers:{authorization:'Bearer test-admin-key'}}),legacyEnv);
assert.equal(migrated.status,200); assert.equal((await migrated.json()).subscriptions[0].name,'Legacy');
assert.equal(legacyEnv.APP_DB.subscriptions.size,1); assert.ok(legacyEnv.POOL.data.has('sub:0123456789abcdef01234567'),'legacy KV source remains intact for rollback');
let r = await call('/healthz'); assert.equal(r.status, 200); assert.equal((await r.json()).version, 5);
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

// Without APP_DB, enrollment fails safely with JSON rather than a Worker 1101 page.
const noDb=await worker.fetch(new Request('https://pool.test/v1/app/devices/enroll',{method:'POST',headers:{'content-type':'application/json'},body:'{}'}),{POOL:new MockKV(),ADMIN_KEY:'test-admin-key'});
assert.equal(noDb.status,503); assert.equal((await noDb.json()).success,false);

// Enrollment writes only to D1; there is no daily/IP quota in app code.
let appToken;
const beforeEnrollmentKvWrites=env.POOL.puts;
for(let i=0;i<25;i++){
  r=await call('/v1/app/devices/enroll','POST',{platform:'android'},{'content-type':'application/json','cf-connecting-ip':'192.0.2.99'});
  assert.equal(r.status,200); d=await r.json(); assert.equal(d.success,true); assert.match(d.token,/^[0-9a-f]{64}$/); appToken=d.token;
}
assert.equal(env.POOL.puts,beforeEnrollmentKvWrites);
assert.equal(env.APP_DB.devices.size,25);

r = await call('/v1/pool/candidates'); assert.equal(r.status,410); // Never publish an enumerable batch endpoint.
await call('/admin/api/import', 'POST', { lines:['Candidate metadata | https://example.com/sub/candidate'] }, { authorization:'Bearer test-admin-key', 'content-type':'application/json' });
const poolSub = (await (await call('/admin/api/subscriptions','GET',null,{authorization:'Bearer test-admin-key'})).json()).subscriptions[0];
const realFetch = globalThis.fetch; let upstreamCalls=0;
globalThis.fetch = async () => { upstreamCalls++; return new Response('vless://user@example.com:443?security=tls#Node-A', { status:200, headers:{ 'subscription-userinfo':'upload=100; download=200; total=1000; expire=2000000000' } }); };
try {
  const beforeHotPathKvWrites=env.POOL.puts;
  r = await call('/v1/pool/leases', 'POST', { exclude:[] }, { 'content-type':'application/json', 'cf-connecting-ip':'192.0.2.10', authorization:'Bearer '+appToken });
  assert.equal(r.status, 200); d=await r.json();
  assert.match(d.leaseId,/^[0-9a-f]{64}$/); assert.equal(d.candidate.id.length,24);
  assert.equal(d.candidate.subscriptionName,poolSub.name); assert.equal(d.candidate.total,1000); assert.equal(d.candidate.upload,100);
  assert.equal('url' in d.candidate,false); assert.equal('candidates' in d,false);
  assert.equal(env.APP_DB.leases.get(d.leaseId).sub_id,poolSub.id);
  assert.equal([...env.APP_DB.profiles.values()].some(p=>p.sub_id===poolSub.id),true);
  const firstFetchCount=upstreamCalls;
  const leaseId=d.leaseId;
  r = await call('/v1/pool/leases/release','POST',{leaseId},{'content-type':'application/json', authorization:'Bearer '+appToken}); assert.equal(r.status,200); assert.equal((await r.json()).released,true);
  assert.equal(env.APP_DB.leases.has(leaseId),false);
  const candidateId=d.candidate.id;
  const longExcludeList=Array.from({length:150},()=> 'f'.repeat(24)); longExcludeList.push(candidateId);
  r = await call('/v1/pool/leases','POST',{exclude:longExcludeList},{'content-type':'application/json','cf-connecting-ip':'192.0.2.11', authorization:'Bearer '+appToken}); assert.equal(r.status,503);
  assert.equal(upstreamCalls,firstFetchCount,'fresh D1 pool state must avoid another provider refresh');
  for(let i=0;i<25;i++){
    r=await call('/v1/pool/leases','POST',{exclude:[]},{'content-type':'application/json','cf-connecting-ip':'192.0.2.12', authorization:'Bearer '+appToken});
    assert.equal(r.status,200,`lease attempt ${i+1} must not be rate-limited`); const repeated=await r.json();
    r=await call('/v1/pool/leases/release','POST',{leaseId:repeated.leaseId},{'content-type':'application/json',authorization:'Bearer '+appToken}); assert.equal(r.status,200);
  }
  assert.equal(upstreamCalls,firstFetchCount,'connections within the five-minute cache window must not rewrite pool state');
  assert.equal(env.POOL.puts,beforeHotPathKvWrites,'app enrollment/lease flow must not write KV');

  const devices=await (await call('/admin/api/devices','GET',null,{authorization:'Bearer test-admin-key'})).json();
  assert.ok(devices.devices.some(item=>item.active&&item.name==='V2rayAG app (automatic)'));
  const tokenHash=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(appToken)))).map(b=>b.toString(16).padStart(2,'0')).join('');
  r=await call('/admin/api/devices/revoke','POST',{id:tokenHash},{authorization:'Bearer test-admin-key','content-type':'application/json'}); assert.equal(r.status,200);
  r=await call('/v1/pool/leases','POST',{exclude:[]},{'content-type':'application/json',authorization:'Bearer '+appToken}); assert.equal(r.status,401);
} finally { globalThis.fetch = realFetch; }
r = await call('/admin'); assert.equal(r.status, 200); const html=await r.text(); assert.match(html,/V2rayAG private pool/); const inline=html.match(/<script>([\s\S]*?)<\/script>/)?.[1]; assert.ok(inline); new Function(inline); assert.match(inline,/delete-all/); assert.match(inline,/statusFilter/); assert.match(inline,/markers=text.match/);
const pasted='Sub 0001 | https://one.example/aSub 0002 | https://two.example/b'; const markers=pasted.match(/Sub\s+\d+\s*\|\s*https/gi)||[]; const parsed=(markers.length>1?pasted.split(/(?=Sub\s+\d+\s*\|\s*https)/i):pasted.split(/\r\n|[\n\r\u2028\u2029]/)).map(x=>x.trim()).filter(Boolean); assert.equal(parsed.length,2); assert.match(parsed[1],/^Sub 0002/);
console.log('Worker admin, D1 enrollment/profile/state/lease storage, five-minute refresh caching, safe missing-binding handling, legacy KV profile compatibility, revocation, import, and deletion tests passed.');
