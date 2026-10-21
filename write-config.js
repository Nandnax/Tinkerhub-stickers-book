import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname } from 'node:path';

const url = (process.env.SUPABASE_URL || '').trim().replace(/\/+$/, '');
const anonKey = (process.env.SUPABASE_ANON_KEY || '').trim();
const out = process.argv[2] || 'config.js';

function fail(msg) {
  console.error(`write-config: ${msg}`);
  process.exit(1);
}

if (!url || !anonKey) {
  fail('SUPABASE_URL and SUPABASE_ANON_KEY must both be set.');
}

if (!/^https:\/\/[a-z0-9-]+\.supabase\.co$/i.test(url)) {
  fail('SUPABASE_URL must look like https://your-project.supabase.co');
}

if (/^sb_secret_/.test(anonKey)) {
  fail('Use the public anon or publishable key, not a secret key.');
}

if (anonKey.split('.').length === 3) {
  let payload;
  try {
    payload = JSON.parse(
      Buffer.from(anonKey.split('.')[1], 'base64url').toString('utf8')
    );
  } catch {
    fail('Invalid Supabase key.');
  }
  if (payload.role !== 'anon') {
    fail('Use the anon key, not the service_role key.');
  }
} else if (!/^sb_publishable_/.test(anonKey)) {
  fail('Use an anon JWT or an sb_publishable_ key.');
}

mkdirSync(dirname(out), { recursive: true });
writeFileSync(
  out,
  `window.SUPABASE_CONFIG = ${JSON.stringify({ url, anonKey })};\n`
);

console.log('write-config: configuration generated successfully.');
