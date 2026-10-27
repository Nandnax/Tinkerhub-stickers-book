-- =====================================================================
-- TinkerHub Sticker Book — Supabase schema
-- Run once in Supabase: Dashboard → SQL Editor → New query → paste → Run.
-- Safe to re-run: it uses IF NOT EXISTS / OR REPLACE / ON CONFLICT.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Sticker catalogue: the only sticker IDs a collection may contain.
--    These are the 37 stickers currently on the site (same IDs as index.html).
-- ---------------------------------------------------------------------
create table if not exists public.stickers (
  id    text primary key check (id ~ '^[a-z0-9_]{1,40}$'),
  title text not null check (char_length(title) between 1 and 120)
);

insert into public.stickers (id, title) values
  ('3_533', 'Skills Pay the Bills!'),
  ('3_534', 'For Those We Never Meet'),
  ('3_545', 'Always Learn to Learn'),
  ('3_598', 'Dream Team!'),
  ('3_604', 'Change Starts With You'),
  ('3_614', 'Get Your Hands Dirty'),
  ('3_615', 'Be Kind, Be Curious'),
  ('3_639', 'The Coolest Stuff'),
  ('3_655', 'Fortune Favours the Daring'),
  ('3_675', 'You Can Be Anything'),
  ('3_681', 'Ditch Your Comfort Zone!'),
  ('3_791', 'I See a Diva'),
  ('3_908', 'Skills Pay the Bills (cash edition)'),
  ('3_1064', 'Making Is the New Aesthetic'),
  ('new_hard', 'What, Like It''s Hard?'),
  ('3_1089', 'Never Give Up!!'),
  ('3_1297', 'Pay It Forward'),
  ('3_1306', 'Just Keep Swimming'),
  ('3_1312', 'Be Kind'),
  ('3_1409', 'Coding Is My Superpower'),
  ('3_1485', 'Get Your Hands Dirty!'),
  ('3_1504', 'Bazinga! My Code Works!'),
  ('3_1505', 'Skills Pay the Bills'),
  ('3_1506', 'TinkerHub'),
  ('3_1507', 'We Love TinkerHub'),
  ('3_1508', 'Community Is My Spinach'),
  ('3_2997', 'Maker Vibes'),
  ('3_3077', 'ഇവിടെ CHILL ആണ്'),
  ('3_3593', 'Build & Break'),
  ('3_3601', 'Found My Cloud'),
  ('3_3872', 'The Coder Card'),
  ('3_3873', 'Don''t Look (ink)'),
  ('3_3874', 'The Spark'),
  ('3_3875', 'Becoming a Coder'),
  ('3_3876', 'Don''t Look (colour)'),
  ('3_3877', 'In Code We Trust'),
  ('3_3878', 'Moving Further')
  ('up_weird', 'Nothing Is Too Weird to Build')
  ('up_together', 'Together, We Make It Better')
  ('up_never', 'Never Give Up')
  ('up_hands', 'Get Your Hands Dirty')
  ('ts_mindset', 'Making Is the New Mindset')
  ('ts_build', 'Build Cool Stuff!')

on conflict (id) do update set title = excluded.title;

-- ---------------------------------------------------------------------
-- 2. Name normalisation: one collection per normalised name.
--    "  Asha  K ", "asha k" and "ＡＳＨＡ K" all map to "asha k".
-- ---------------------------------------------------------------------
create or replace function public.clean_display_name(p text)
returns text language sql immutable
as $$ select btrim(regexp_replace(normalize(coalesce(p, ''), NFKC), '\s+', ' ', 'g')) $$;

create or replace function public.normalize_name(p text)
returns text language sql immutable
as $$ select lower(public.clean_display_name(p)) $$;

-- ---------------------------------------------------------------------
-- 3. Collections: one row per person (per normalised name).
--    sticker_ids is de-duplicated and sticker_count is DERIVED by a trigger,
--    so a client can never submit its own total.
-- ---------------------------------------------------------------------
create table if not exists public.collections (
  id            uuid primary key default gen_random_uuid(),
  display_name  text not null,
  name_key      text not null,
  sticker_ids   text[] not null default '{}',
  sticker_count integer not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  constraint collections_name_key_unique unique (name_key),
  constraint collections_display_name_len check (char_length(display_name) between 1 and 32),
  constraint collections_name_no_control check (display_name !~ '[[:cntrl:]]'),
  constraint collections_count_matches check (sticker_count = cardinality(sticker_ids)),
  constraint collections_max_stickers check (cardinality(sticker_ids) <= 200)
);

create index if not exists collections_leaderboard_idx
  on public.collections (sticker_count desc, name_key);

create or replace function public.collections_derive()
returns trigger language plpgsql
set search_path = public
as $$
declare bad text;
begin
  new.display_name := public.clean_display_name(new.display_name);
  new.name_key     := public.normalize_name(new.display_name);

  -- unique, sorted sticker IDs; NULLs dropped
  select coalesce(array_agg(distinct s order by s), '{}')
    into new.sticker_ids
    from unnest(coalesce(new.sticker_ids, '{}')) as s
   where s is not null;

  -- every ID must exist in the catalogue
  select s into bad
    from unnest(new.sticker_ids) as s
   where not exists (select 1 from public.stickers st where st.id = s)
   limit 1;
  if bad is not null then
    raise exception 'Unknown sticker id: %', bad using errcode = '22023';
  end if;

  new.sticker_count := cardinality(new.sticker_ids);   -- the server's own count
  new.updated_at    := now();
  if tg_op = 'UPDATE' then new.created_at := old.created_at; new.id := old.id; end if;
  return new;
end $$;

drop trigger if exists collections_derive_trg on public.collections;
create trigger collections_derive_trg
  before insert or update on public.collections
  for each row execute function public.collections_derive();

-- ---------------------------------------------------------------------
-- 4. Ratings (keeps the site's existing star ratings working).
--    voter_id is a random UUID kept in each browser's localStorage.
--    The raw ratings table is NOT readable by visitors, so nobody can see
--    (and reuse) someone else's voter_id. Visitors read the aggregate table.
-- ---------------------------------------------------------------------
create table if not exists public.ratings (
  voter_id   uuid not null,
  sticker_id text not null references public.stickers(id) on delete cascade,
  stars      smallint not null check (stars between 1 and 5),
  updated_at timestamptz not null default now(),
  primary key (voter_id, sticker_id)
);

create table if not exists public.sticker_rating_stats (
  sticker_id   text primary key references public.stickers(id) on delete cascade,
  rating_sum   integer not null default 0,
  rating_count integer not null default 0
);

create or replace function public.ratings_refresh_stats()
returns trigger language plpgsql security definer
set search_path = public
as $$
declare sid text := coalesce(new.sticker_id, old.sticker_id);
begin
  insert into public.sticker_rating_stats (sticker_id, rating_sum, rating_count)
  select sid, coalesce(sum(stars), 0), count(*) from public.ratings where sticker_id = sid
  on conflict (sticker_id) do update
    set rating_sum = excluded.rating_sum, rating_count = excluded.rating_count;
  if tg_op = 'UPDATE' and old.sticker_id is distinct from new.sticker_id then
    insert into public.sticker_rating_stats (sticker_id, rating_sum, rating_count)
    select old.sticker_id, coalesce(sum(stars), 0), count(*) from public.ratings where sticker_id = old.sticker_id
    on conflict (sticker_id) do update
      set rating_sum = excluded.rating_sum, rating_count = excluded.rating_count;
  end if;
  return null;
end $$;

drop trigger if exists ratings_refresh_stats_trg on public.ratings;
create trigger ratings_refresh_stats_trg
  after insert or update or delete on public.ratings
  for each row execute function public.ratings_refresh_stats();

-- ---------------------------------------------------------------------
-- 5. The ONLY write paths visitors get: these functions.
--    They validate input; tables themselves are read-only (or unreadable)
--    to the public "anon" key.
-- ---------------------------------------------------------------------
create or replace function public.get_collection(p_name text)
returns table (display_name text, sticker_ids text[], sticker_count integer)
language sql stable security definer
set search_path = public
as $$
  select c.display_name, c.sticker_ids, c.sticker_count
    from public.collections c
   where c.name_key = public.normalize_name(p_name)
$$;

create or replace function public.save_collection(p_name text, p_sticker_ids text[])
returns table (display_name text, sticker_ids text[], sticker_count integer)
language plpgsql volatile security definer
set search_path = public
as $$
declare clean text := public.clean_display_name(p_name);
begin
  if char_length(clean) < 1 or char_length(clean) > 32 then
    raise exception 'Name must be 1–32 characters' using errcode = '22023';
  end if;
  if clean ~ '[[:cntrl:]]' then
    raise exception 'Name contains invalid characters' using errcode = '22023';
  end if;
  if p_sticker_ids is null or cardinality(p_sticker_ids) > 200 then
    raise exception 'Invalid sticker list' using errcode = '22023';
  end if;

  -- the trigger de-duplicates, validates IDs and computes sticker_count
  insert into public.collections as c (display_name, name_key, sticker_ids)
  values (clean, public.normalize_name(clean), p_sticker_ids)
  on conflict (name_key) do update
    set sticker_ids = excluded.sticker_ids;      -- keep the display name exactly as first saved

  return query
    select c.display_name, c.sticker_ids, c.sticker_count
      from public.collections c
     where c.name_key = public.normalize_name(clean);
end $$;

create or replace function public.rate_sticker(p_voter uuid, p_sticker text, p_stars integer)
returns void
language plpgsql volatile security definer
set search_path = public
as $$
begin
  if p_voter is null then raise exception 'Missing voter id' using errcode = '22023'; end if;
  if not exists (select 1 from public.stickers where id = p_sticker) then
    raise exception 'Unknown sticker id' using errcode = '22023';
  end if;
  if p_stars is null or p_stars = 0 then
    delete from public.ratings where voter_id = p_voter and sticker_id = p_sticker;
  elsif p_stars between 1 and 5 then
    insert into public.ratings (voter_id, sticker_id, stars) values (p_voter, p_sticker, p_stars)
    on conflict (voter_id, sticker_id) do update set stars = excluded.stars, updated_at = now();
  else
    raise exception 'Stars must be 1–5' using errcode = '22023';
  end if;
end $$;

create or replace function public.get_my_ratings(p_voter uuid)
returns table (sticker_id text, stars smallint)
language sql stable security definer
set search_path = public
as $$ select r.sticker_id, r.stars from public.ratings r where r.voter_id = p_voter $$;

-- ---------------------------------------------------------------------
-- 6. Row Level Security + privileges.
--    Supabase grants table privileges to anon/authenticated by default,
--    so we revoke writes explicitly and rely on RLS for reads.
-- ---------------------------------------------------------------------
alter table public.stickers             enable row level security;
alter table public.collections          enable row level security;
alter table public.ratings              enable row level security;
alter table public.sticker_rating_stats enable row level security;

revoke all on public.stickers, public.collections, public.ratings, public.sticker_rating_stats
  from anon, authenticated;
grant select on public.stickers, public.collections, public.sticker_rating_stats to anon, authenticated;
-- (no grant at all on public.ratings)

drop policy if exists "stickers are public"    on public.stickers;
drop policy if exists "collections are public" on public.collections;
drop policy if exists "rating stats are public" on public.sticker_rating_stats;
create policy "stickers are public"     on public.stickers             for select to anon, authenticated using (true);
create policy "collections are public"  on public.collections          for select to anon, authenticated using (true);
create policy "rating stats are public" on public.sticker_rating_stats for select to anon, authenticated using (true);
-- No INSERT/UPDATE/DELETE policies anywhere: direct table writes are refused.

revoke all on function public.get_collection(text), public.save_collection(text, text[]),
  public.rate_sticker(uuid, text, integer), public.get_my_ratings(uuid),
  public.collections_derive(), public.ratings_refresh_stats(),
  public.clean_display_name(text), public.normalize_name(text)
  from public;
grant execute on function public.get_collection(text), public.save_collection(text, text[]),
  public.rate_sticker(uuid, text, integer), public.get_my_ratings(uuid),
  public.clean_display_name(text), public.normalize_name(text)
  to anon, authenticated;

-- ---------------------------------------------------------------------
-- 7. Realtime: broadcast changes so every open leaderboard updates.
-- ---------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin
      alter publication supabase_realtime add table public.collections;
    exception when duplicate_object then null; end;
    begin
      alter publication supabase_realtime add table public.sticker_rating_stats;
    exception when duplicate_object then null; end;
  end if;
end $$;
