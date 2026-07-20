-- Phase 9a — production schema + RLS for the Supabase/Postgres backend
-- migration (docs/supabase-migration-plan.md, ROADMAP.md Phase 9).
--
-- Run this once, in full, in the Supabase SQL editor for the existing
-- CloudSyncSpike project. It DROPS the spike's throwaway `match_records`
-- test table (id/owner_id/note/created_at, per CloudSyncSpike's
-- SpikeTestRecord) along with any ad-hoc `players`/`profiles` tables from
-- the spike walkthrough — those only ever held disposable test rows — and
-- replaces them with the real schema below. CloudSyncSpike's Swift code is
-- untouched by this file; its "Send test record"/"Fetch records" buttons
-- will simply start reading/writing the real `match_records` shape
-- (id/owner_id/payload jsonb/updated_at) afterward, which is fine since
-- SpikeTestRecord already only ever inserted disposable rows.
--
-- Scope: 9a is schema + RLS only, no app code. Two deliberate
-- simplifications vs. the design doc's original sketch, both because the
-- data they'd cover isn't wired up until a later slice:
--   1. No `friend_shares` junction table. Friend-visibility policies on
--      players/match_records/settings/profiles are deferred to 9e (Friends
--      graph cutover) — they'll be added as extra SELECT policies keyed off
--      `friend_requests.status = 'accepted'` plus the existing per-field
--      share toggles already present in a user's `settings.payload` (e.g.
--      `shareHistoryWithFriends`), no separate table needed.
--   2. Club-scoped players/match_records/challenges write policies are
--      zone-wide permissive (any club member can write any row tagged with
--      that club) — this is not a new decision, it's carrying forward
--      CloudKit's current documented behavior (see ROADMAP.md Phase 5:
--      "any club participant can already write any field of any record in
--      a shared zone"). Reactions are the one exception: each reaction has
--      its own author, so only the author can edit/delete their own.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- Drop spike-era scaffolding (test data only — safe to discard)
-- ---------------------------------------------------------------------

drop table if exists public.match_records cascade;
drop table if exists public.players cascade;
drop table if exists public.profiles cascade;

-- ---------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------

create table public.profiles (
    id uuid primary key references auth.users (id) on delete cascade,
    display_name text not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table public.clubs (
    id uuid primary key default gen_random_uuid(),
    owner_id uuid not null references auth.users (id) on delete cascade,
    payload jsonb not null,
    updated_at timestamptz not null default now()
);

create table public.club_members (
    club_id uuid not null references public.clubs (id) on delete cascade,
    user_id uuid not null references auth.users (id) on delete cascade,
    role text not null default 'member' check (role in ('owner', 'member')),
    joined_at timestamptz not null default now(),
    primary key (club_id, user_id)
);

create table public.club_invites (
    id uuid primary key default gen_random_uuid(),
    club_id uuid not null references public.clubs (id) on delete cascade,
    created_by uuid not null references auth.users (id) on delete cascade,
    expires_at timestamptz,
    max_uses integer,
    use_count integer not null default 0,
    created_at timestamptz not null default now()
);

create table public.players (
    id uuid primary key default gen_random_uuid(),
    owner_id uuid not null references auth.users (id) on delete cascade,
    club_id uuid references public.clubs (id) on delete set null,
    payload jsonb not null,
    updated_at timestamptz not null default now()
);

create table public.match_records (
    id uuid primary key default gen_random_uuid(),
    owner_id uuid not null references auth.users (id) on delete cascade,
    club_id uuid references public.clubs (id) on delete set null,
    payload jsonb not null,
    updated_at timestamptz not null default now()
);

-- Phase 9c-5: Realtime subscriptions filter DELETE events by owner_id, but
-- Postgres's default REPLICA IDENTITY only logs primary-key columns (id) in
-- a DELETE's old-row image — owner_id isn't part of the primary key on
-- either table, so without FULL, delete events would silently fail to match
-- the filter and never reach subscribers. (settings needs no such statement
-- since owner_id already is its primary key.)
alter table public.players replica identity full;
alter table public.match_records replica identity full;

create table public.settings (
    owner_id uuid primary key references auth.users (id) on delete cascade,
    payload jsonb not null,
    updated_at timestamptz not null default now()
);

create table public.challenges (
    id uuid primary key default gen_random_uuid(),
    club_id uuid not null references public.clubs (id) on delete cascade,
    from_participant_id uuid not null references auth.users (id) on delete cascade,
    to_participant_id uuid not null references auth.users (id) on delete cascade,
    payload jsonb not null,
    updated_at timestamptz not null default now()
);

create table public.reactions (
    id uuid primary key default gen_random_uuid(),
    club_id uuid not null references public.clubs (id) on delete cascade,
    match_id uuid not null,
    author_id uuid not null references auth.users (id) on delete cascade,
    payload jsonb not null,
    created_at timestamptz not null default now()
);

create table public.friend_requests (
    id uuid primary key default gen_random_uuid(),
    from_participant_id uuid not null references auth.users (id) on delete cascade,
    to_participant_id uuid not null references auth.users (id) on delete cascade,
    status text not null default 'pending' check (status in ('pending', 'accepted', 'declined')),
    payload jsonb not null default '{}'::jsonb,
    updated_at timestamptz not null default now(),
    unique (from_participant_id, to_participant_id)
);

create index players_owner_id_idx on public.players (owner_id);
create index players_club_id_idx on public.players (club_id);
create index match_records_owner_id_idx on public.match_records (owner_id);
create index match_records_club_id_idx on public.match_records (club_id);
create index club_members_user_id_idx on public.club_members (user_id);
create index challenges_club_id_idx on public.challenges (club_id);
create index reactions_club_id_idx on public.reactions (club_id);
create index reactions_match_id_idx on public.reactions (match_id);
create index friend_requests_to_participant_id_idx on public.friend_requests (to_participant_id);
create index friend_requests_from_participant_id_idx on public.friend_requests (from_participant_id);

-- ---------------------------------------------------------------------
-- Helper functions (SECURITY DEFINER to avoid RLS self-recursion on
-- club_members — the standard Supabase pattern for membership checks)
-- ---------------------------------------------------------------------

create or replace function public.is_club_member(target_club_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
    select exists (
        select 1 from public.club_members
        where club_id = target_club_id and user_id = auth.uid()
    );
$$;

grant execute on function public.is_club_member (uuid) to authenticated;

create or replace function public.is_club_owner(target_club_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
    select exists (
        select 1 from public.clubs
        where id = target_club_id and owner_id = auth.uid()
    );
$$;

grant execute on function public.is_club_owner (uuid) to authenticated;

-- Auto-add a club's creator as its first (owner) member — mirrors
-- CloudKit's implicit "creating a zone makes you its first participant".
create or replace function public.handle_new_club()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    insert into public.club_members (club_id, user_id, role)
    values (new.id, new.owner_id, 'owner');
    return new;
end;
$$;

create trigger on_club_created
after insert on public.clubs
for each row execute function public.handle_new_club();

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

create trigger trg_profiles_updated_at before update on public.profiles
    for each row execute function public.set_updated_at();
create trigger trg_clubs_updated_at before update on public.clubs
    for each row execute function public.set_updated_at();
create trigger trg_players_updated_at before update on public.players
    for each row execute function public.set_updated_at();
create trigger trg_match_records_updated_at before update on public.match_records
    for each row execute function public.set_updated_at();
create trigger trg_settings_updated_at before update on public.settings
    for each row execute function public.set_updated_at();
create trigger trg_challenges_updated_at before update on public.challenges
    for each row execute function public.set_updated_at();
create trigger trg_friend_requests_updated_at before update on public.friend_requests
    for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.clubs enable row level security;
alter table public.club_members enable row level security;
alter table public.club_invites enable row level security;
alter table public.players enable row level security;
alter table public.match_records enable row level security;
alter table public.settings enable row level security;
alter table public.challenges enable row level security;
alter table public.reactions enable row level security;
alter table public.friend_requests enable row level security;

-- profiles: readable by any signed-in user (friend-code lookup needs to
-- resolve a profile with no prior relationship, same as CloudKit's public
-- FriendProfile), writable only by its owner.
create policy profiles_select on public.profiles
    for select to authenticated using (true);
create policy profiles_insert on public.profiles
    for insert to authenticated with check (id = auth.uid());
create policy profiles_update on public.profiles
    for update to authenticated using (id = auth.uid());

-- clubs: visible to the owner and any member; only the owner can create,
-- rename, or delete.
create policy clubs_select on public.clubs
    for select to authenticated
    using (owner_id = auth.uid() or public.is_club_member(id));
create policy clubs_insert on public.clubs
    for insert to authenticated with check (owner_id = auth.uid());
create policy clubs_update on public.clubs
    for update to authenticated using (owner_id = auth.uid());
create policy clubs_delete on public.clubs
    for delete to authenticated using (owner_id = auth.uid());

-- club_members: a member can see their own club's roster; a member can
-- remove themselves (leave), the owner can remove anyone (kick). Row
-- creation happens via handle_new_club() (owner) or a future invite-
-- redemption RPC (9d) — no direct insert policy needed yet.
create policy club_members_select on public.club_members
    for select to authenticated
    using (user_id = auth.uid() or public.is_club_member(club_id));
create policy club_members_delete on public.club_members
    for delete to authenticated
    using (user_id = auth.uid() or public.is_club_owner(club_id));

-- club_invites: owner-only, matching the owner-gated invite flow on
-- ClubDetailView today.
create policy club_invites_select on public.club_invites
    for select to authenticated using (public.is_club_owner(club_id));
create policy club_invites_insert on public.club_invites
    for insert to authenticated
    with check (created_by = auth.uid() and public.is_club_owner(club_id));
create policy club_invites_delete on public.club_invites
    for delete to authenticated using (public.is_club_owner(club_id));

-- players / match_records: personal rows are owner-only; club rows are
-- zone-wide readable/writable by any member of that club (see file header).
create policy players_select on public.players
    for select to authenticated
    using (owner_id = auth.uid() or (club_id is not null and public.is_club_member(club_id)));
create policy players_write on public.players
    for all to authenticated
    using (owner_id = auth.uid() or (club_id is not null and public.is_club_member(club_id)))
    with check (owner_id = auth.uid() or (club_id is not null and public.is_club_member(club_id)));

create policy match_records_select on public.match_records
    for select to authenticated
    using (owner_id = auth.uid() or (club_id is not null and public.is_club_member(club_id)));
create policy match_records_write on public.match_records
    for all to authenticated
    using (owner_id = auth.uid() or (club_id is not null and public.is_club_member(club_id)))
    with check (owner_id = auth.uid() or (club_id is not null and public.is_club_member(club_id)));

-- settings: strictly personal, one row per user.
create policy settings_all on public.settings
    for all to authenticated
    using (owner_id = auth.uid())
    with check (owner_id = auth.uid());

-- challenges: club-scoped, zone-wide like players/match_records (see file
-- header caveat about CloudKit's existing permissive zone model), but a
-- challenge can only be created in your own name.
create policy challenges_select on public.challenges
    for select to authenticated using (public.is_club_member(club_id));
create policy challenges_insert on public.challenges
    for insert to authenticated
    with check (from_participant_id = auth.uid() and public.is_club_member(club_id));
create policy challenges_update on public.challenges
    for update to authenticated using (public.is_club_member(club_id));
create policy challenges_delete on public.challenges
    for delete to authenticated using (public.is_club_member(club_id));

-- reactions: club-scoped for reads; only the author can write/edit/delete
-- their own reaction (unlike players/challenges, each row has a real author).
create policy reactions_select on public.reactions
    for select to authenticated using (public.is_club_member(club_id));
create policy reactions_insert on public.reactions
    for insert to authenticated
    with check (author_id = auth.uid() and public.is_club_member(club_id));
create policy reactions_update on public.reactions
    for update to authenticated using (author_id = auth.uid());
create policy reactions_delete on public.reactions
    for delete to authenticated using (author_id = auth.uid());

-- friend_requests: visible to either side of the request; only the sender
-- can create one (can't send as someone else); either side can update
-- (recipient accepts/declines, sender cancels). Delete is symmetric (either
-- side can remove the row, same self-or-owner shape as club_members_delete)
-- rather than sender-only, so a full erase-all-data teardown (Phase 9e-4)
-- can clean up requests where this account is only the recipient.
create policy friend_requests_select on public.friend_requests
    for select to authenticated
    using (from_participant_id = auth.uid() or to_participant_id = auth.uid());
create policy friend_requests_insert on public.friend_requests
    for insert to authenticated with check (from_participant_id = auth.uid());
create policy friend_requests_update on public.friend_requests
    for update to authenticated
    using (from_participant_id = auth.uid() or to_participant_id = auth.uid());
create policy friend_requests_delete on public.friend_requests
    for delete to authenticated
    using (from_participant_id = auth.uid() or to_participant_id = auth.uid());

-- ---------------------------------------------------------------------
-- Realtime (Phase 9c-6): enable logical replication for the personal
-- tier so SupabaseSyncManager.startRealtimeSync (9c-5) actually receives
-- INSERT/UPDATE/DELETE events. Without this, a table's changes never
-- enter the replication stream that Postgres Changes reads from, no
-- matter how a client subscribes or filters.
-- ---------------------------------------------------------------------

alter publication supabase_realtime add table public.players, public.match_records, public.settings;

-- Phase 9d: clubs/challenges/reactions join Realtime now that their
-- push/pull sync is wired up (SupabaseSyncEngine.enqueueClubChanges/
-- enqueueChallengeChanges/enqueueReactionChanges + pullInitialState/
-- handleRemoteChange).
alter publication supabase_realtime add table public.clubs, public.challenges, public.reactions;

-- Realtime authorizes delivery of a DELETE event using the table's RLS
-- SELECT policy evaluated against the old-row image, which under the
-- default REPLICA IDENTITY only contains primary-key columns (`id`).
-- `clubs_select`'s `is_club_member(id)` branch needs only the row's own
-- PK, so `clubs` works fine without FULL. `challenges_select`/
-- `reactions_select` need `club_id` (and reactions' own delete policy
-- needs `author_id`) — neither is part of either table's primary key, so
-- without FULL those columns are absent from a DELETE's old-row image,
-- `is_club_member(NULL)` evaluates false for every user, and the event
-- fails RLS for everyone (including the club member who should see it) —
-- the same REPLICA IDENTITY gap 9c-5 found and fixed for
-- players/match_records, rediscovered here during 9d-1's /code-review.
-- There is no fallback: fetchAllRows never reports .delete, so without
-- this a deleted challenge/reaction would never sync at all.
alter table public.challenges replica identity full;
alter table public.reactions replica identity full;

-- ---------------------------------------------------------------------
-- Invite redemption (Phase 9d-2): club_members has no direct INSERT
-- policy (see its RLS comment above) — the only way to join a club you
-- don't own is through this SECURITY DEFINER function, which validates a
-- club_invites row (existence/expiry/max_uses) and inserts the caller
-- into club_members itself, bypassing the caller's own (nonexistent)
-- insert privilege the same way handle_new_club() already does for the
-- owner. `for update` row-locks the invite for the duration of the
-- check-and-increment so two concurrent redemptions of a max_uses:1
-- invite can't both pass the check before either increments use_count.
-- use_count only increments when the insert actually adds a new member
-- (checked via `get diagnostics`) — an already-a-member caller re-opening
-- the same link (a real scenario: re-tapping an old link out of
-- confusion, or a retry after a dropped response from a first successful
-- call) hits `on conflict do nothing` and must not burn down a limited
-- invite's remaining uses when nobody new actually joined.
-- ---------------------------------------------------------------------

create or replace function public.redeem_club_invite(invite_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    target_club_id uuid;
    inserted_count int;
begin
    select club_id into target_club_id
    from public.club_invites
    where id = invite_id
      and (expires_at is null or expires_at > now())
      and (max_uses is null or use_count < max_uses)
    for update;

    if target_club_id is null then
        raise exception 'invite not found, expired, or fully used';
    end if;

    insert into public.club_members (club_id, user_id, role)
    values (target_club_id, auth.uid(), 'member')
    on conflict do nothing;

    get diagnostics inserted_count = row_count;

    if inserted_count > 0 then
        update public.club_invites set use_count = use_count + 1 where id = invite_id;
    end if;

    return target_club_id;
end;
$$;

grant execute on function public.redeem_club_invite (uuid) to authenticated;

-- ---------------------------------------------------------------------
-- Friends graph (Phase 9e-1): friend_requests joins Realtime now that its
-- push/pull sync is wired up (SupabaseSyncEngine.refreshFriendRequests via
-- pullInitialState/handleRemoteChange). Same REPLICA IDENTITY gap as
-- challenges/reactions (9d-1) and players/match_records (9c-5):
-- friend_requests_select/_delete need from_participant_id/to_participant_id,
-- neither the primary key, so a DELETE's old-row image is missing them
-- under the default identity and the event fails RLS for everyone.
-- ---------------------------------------------------------------------

alter table public.friend_requests replica identity full;
alter publication supabase_realtime add table public.friend_requests;

-- ---------------------------------------------------------------------
-- Friend identity + stats sharing (Phase 9e-2): two new, narrow, one-row-
-- per-owner tables — NOT RLS granted directly on `settings`. `settings`'s
-- single `payload jsonb` blob holds every unrelated scalar setting
-- (pointsToWin, courtTheme, ...) alongside the four identity fields and
-- derived stats a user might want to share with friends; RLS can only
-- grant or deny a whole row, not individual jsonb keys, so granting a
-- friend SELECT there would leak everything, not just what they toggled
-- on. Each is `id`+`payload jsonb`, the same shape every other Phase 9
-- table uses (`id` doubles as the owner's participant id here, same as
-- `settings.owner_id` already does) — this reuses SupabaseSyncManager's
-- existing generic fetchAllRows/startRealtimeSync/upsertRows machinery
-- unchanged rather than needing bespoke per-column decode logic. The
-- payload itself mirrors CloudKitSyncManager's own
-- currentFriendIdentitySnapshot()/currentFriendStatsSnapshot() shape:
-- derived, precomputed by the owner client-side, with each field left null
-- whenever its share toggle is off — never written at all, not just
-- RLS-hidden, same defense-in-depth CloudKit's FriendIdentitySnapshot
-- already has.
-- ---------------------------------------------------------------------

create table public.friend_identity_snapshots (
    id uuid primary key references auth.users (id) on delete cascade,
    payload jsonb not null,
    updated_at timestamptz not null default now()
);

create table public.friend_stats_snapshots (
    id uuid primary key references auth.users (id) on delete cascade,
    payload jsonb not null,
    updated_at timestamptz not null default now()
);

create trigger trg_friend_identity_snapshots_updated_at before update on public.friend_identity_snapshots
    for each row execute function public.set_updated_at();
create trigger trg_friend_stats_snapshots_updated_at before update on public.friend_stats_snapshots
    for each row execute function public.set_updated_at();

-- SECURITY DEFINER to avoid RLS self-recursion on friend_requests, mirroring
-- is_club_member's role for club_members.
create or replace function public.is_accepted_friend(other_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
    select exists (
        select 1 from public.friend_requests
        where status = 'accepted'
          and ((from_participant_id = auth.uid() and to_participant_id = other_id)
            or (to_participant_id = auth.uid() and from_participant_id = other_id))
    );
$$;

grant execute on function public.is_accepted_friend (uuid) to authenticated;

alter table public.friend_identity_snapshots enable row level security;
alter table public.friend_stats_snapshots enable row level security;

-- Readable by the owner and any accepted friend; writable only by the
-- owner. Neither table needs REPLICA IDENTITY FULL — is_accepted_friend(id)
-- only needs the row's own primary key, same reasoning that exempted
-- `clubs` (is_club_member(id)) from the fix challenges/reactions needed.
create policy friend_identity_snapshots_select on public.friend_identity_snapshots
    for select to authenticated
    using (id = auth.uid() or public.is_accepted_friend(id));
create policy friend_identity_snapshots_write on public.friend_identity_snapshots
    for all to authenticated
    using (id = auth.uid())
    with check (id = auth.uid());

create policy friend_stats_snapshots_select on public.friend_stats_snapshots
    for select to authenticated
    using (id = auth.uid() or public.is_accepted_friend(id));
create policy friend_stats_snapshots_write on public.friend_stats_snapshots
    for all to authenticated
    using (id = auth.uid())
    with check (id = auth.uid());

alter publication supabase_realtime add table public.friend_identity_snapshots, public.friend_stats_snapshots;
