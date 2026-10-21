# TinkerHub Sticker Book

Every TinkerHub sticker on one 3D laptop. Visitors count the stickers they own, rate stickers, and appear on a live leaderboard backed by Supabase.

```
index.html                     the whole site (design, 37 stickers, interactions)
supabase/schema.sql            database tables, validation, security, realtime
scripts/write-config.mjs       writes config.js at deploy time; rejects secret keys
.github/workflows/deploy.yml   builds and deploys to GitHub Pages on every push to main
config.example.js              template for local testing (config.js is git-ignored)
```

## 1. Supabase

1. Create a project at <https://supabase.com/dashboard>.
2. **SQL Editor → New query**: paste all of `supabase/schema.sql` and click **Run**. It is safe to run again later (for example after adding stickers).
3. Check Realtime is on for the two public tables: **Database → Publications → `supabase_realtime`** should list `collections` and `sticker_rating_stats`. The schema adds them; if either is missing, toggle it on there.
4. Copy two values:
   - **Project URL**: Project Settings → Data API (looks like `https://abcd1234.supabase.co`).
   - **anon public key**: Project Settings → API Keys → *Legacy API keys* → `anon` `public`.
     Do **not** use the `service_role` key or any `sb_secret_…` key. The deploy step refuses them, and so does the page.

## 2. GitHub Pages

1. Push these files to your repository's `main` branch.
2. **Settings → Secrets and variables → Actions → Variables → New repository variable**, twice:

   | Name | Value |
   | --- | --- |
   | `SUPABASE_URL` | your Project URL |
   | `SUPABASE_ANON_KEY` | your anon public key |

3. **Settings → Pages → Build and deployment → Source: GitHub Actions.**
4. Push any commit (or run **Actions → Deploy to GitHub Pages → Run workflow**). Every later push to `main` redeploys automatically.

## 3. Check it works (do this once after deploying)

1. Open the site, open **Menu → Leaderboard**. The dot next to the title should say **Live** within a few seconds. "Updating" means Realtime didn't connect and the page is polling every 15 seconds instead; see step 3 above.
2. Type a new name, tick three stickers. The status should say "Saved: 3 stickers for …", and you should appear on the board.
3. Open the site in a second browser or a private window and type the same name with different spacing or capitals. Your three stickers should load.
4. Untick one in the second window. The first window's leaderboard should change to 2 without reloading.
5. In Supabase **Table Editor → collections**, confirm one row with `sticker_count = 2`.

## How the data is protected

- The browser only has the public anon key. Tables are read-only to it (`raw ratings` are not readable at all); there are no insert/update/delete policies.
- All writes go through database functions that validate input: names 1–32 characters with no control characters, at most 200 sticker IDs, and every ID must exist in the `stickers` table.
- `sticker_count` is calculated in the database from the de-duplicated sticker list. The browser never sends a total.
- Names are normalised (Unicode NFKC, whitespace collapsed, lower-cased), and `name_key` is unique, so there is one collection per person-name.

## Known limitation: name-only editing

There are no accounts. **Anyone who types a name can see and change that name's collection**, the same way anyone can write on a name tag. It cannot stop someone from editing another person's entry, or from adding made-up names. It's fine for a friendly community leaderboard; it is not suitable for prizes or anything people would want to cheat at. Supabase also has no built-in per-visitor rate limit for these functions. If that becomes a problem: add Supabase Auth (for example magic-link email) and tie each collection to `auth.uid()`, or issue a secret edit code per name.

Ratings use a random ID stored in each browser, so people can't change each other's ratings, but clearing browser data (or using another device) lets someone rate again.

## Editing content

- Sticker text, designers and links: in `index.html`, search for `const STICKERS =`.
- Adding a sticker: add it to `index.html`, then add its ID to the `insert into public.stickers` list in `supabase/schema.sql` and re-run the schema. Saves that include an unknown ID are rejected until you do.

## Local testing

```bash
cp config.example.js config.js     # fill in your URL and anon key
python3 -m http.server 8000         # then open http://localhost:8000
```
