// Writes config.js for the browser from environment variables.
// Fails the build if a secret (service_role / sb_secret_) key is supplied.
import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname } from 'node:path';

const url = (process.env.SUPABASE_URL || '').trim().replace(/\/+$/, '');
const anonKey = (process.env.SUPABASE_ANON_KEY || '').trim();
const out = process.argv[2] || 'config.js';

function fail(msg) { console.error(`write-config: ${msg}`); process.exit(1); }

if (!url || !anonKey) fail('SUPABASE_URL and SUPABASE_ANON_KEY must both be set.');
if (!/^https:\/\/[a-z0-9-]+\.supabase\.co$/i.test(url) && !process.env.ALLOW_CUSTOM_SUPABASE_URL)
  fail(`SUPABASE_URL should look like https://<project-ref>.supabase.co (got "${url}").`);
if (/^sb_secret_/.test(anonKey)) fail('That is a SECRET key. Use the publishable/anon key.');
if (anonKey.split('.').length === 3) {
  let payload;
  try { payload = JSON.parse(Buffer.from(anonKey.split('.')[1], 'base64url').toString('utf8')); }
  catch { fail('SUPABASE_ANON_KEY is not a valid key.'); }
  if (payload.role !== 'anon') fail(`That key has role "${payload.role}". Use the anon key.`);
} else if (!/^sb_publishable_/.test(anonKey)) {
  fail('SUPABASE_ANON_KEY should be the anon JWT or an sb_publishable_ key.');
}

mkdirSync(dirname(out), { recursive: true });
writeFileSync(out, `window.SUPABASE_CONFIG = ${JSON.stringify({ url, anonKey })};\n`);
console.log(`write-config: wrote ${out}`);
