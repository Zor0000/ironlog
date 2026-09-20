-- Recovered on 2026-09-17 from the deployed database. The original migration
-- source was not committed, so this is a squashed baseline for new local
-- environments. The two following historical versions remain as no-ops to
-- preserve the exact deployed migration history.

create extension if not exists "uuid-ossp" with schema extensions;

create table public.exercises (
  id uuid primary key default uuid_generate_v4(),
  name text not null unique,
  created_at timestamptz default now()
);

create table public.sessions (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users(id) on delete cascade,
  muscle_group text,
  split_type text,
  note text,
  created_at timestamptz default now(),
  activity_type text,
  distance_m numeric,
  duration_s integer,
  route jsonb,
  constraint sessions_activity_type_check
    check (activity_type is null or activity_type in ('run', 'walk', 'cycle'))
);

create table public.session_sets (
  id uuid primary key default uuid_generate_v4(),
  session_id uuid not null references public.sessions(id) on delete cascade,
  exercise_id uuid not null references public.exercises(id) on delete cascade,
  weight_kg numeric,
  reps numeric,
  created_at timestamptz default now(),
  set_index integer,
  bodyweight boolean,
  timed boolean,
  uses_minutes boolean,
  set_type text,
  constraint session_sets_set_type_check
    check (set_type is null or set_type in ('warmup', 'drop', 'failure', 'restPause'))
);

create table public.personal_records (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users(id) on delete cascade,
  exercise_id uuid not null references public.exercises(id) on delete cascade,
  weight_kg numeric not null,
  reps numeric not null,
  achieved_at timestamptz default now(),
  unique (user_id, exercise_id)
);

create table public.routines (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  exercises jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index idx_sessions_user_id on public.sessions(user_id);
create index idx_sessions_created_at on public.sessions(created_at desc);
create index idx_session_sets_session on public.session_sets(session_id);
create index idx_pr_user on public.personal_records(user_id);
create index routines_user_id_idx on public.routines(user_id);

alter table public.exercises enable row level security;
alter table public.sessions enable row level security;
alter table public.session_sets enable row level security;
alter table public.personal_records enable row level security;
alter table public.routines enable row level security;

-- These deployed policies are superseded by the explicit per-operation rules
-- in 20260917060350_repair_cloud_backup_schema_and_rls.sql.
create policy "Anyone can read exercises"
on public.exercises for select
using (auth.role() = 'authenticated');

create policy "Anyone can insert exercises"
on public.exercises for insert
with check (auth.role() = 'authenticated');

create policy "Users manage own sessions"
on public.sessions for all
using (auth.uid() = user_id);

create policy "Users manage own session sets"
on public.session_sets for all
using (exists (
  select 1 from public.sessions s
  where s.id = session_sets.session_id and s.user_id = auth.uid()
));

create policy "Users manage own PRs"
on public.personal_records for all
using (auth.uid() = user_id);

create policy "Users manage own routines"
on public.routines for all
using (auth.uid() = user_id)
with check (auth.uid() = user_id);
