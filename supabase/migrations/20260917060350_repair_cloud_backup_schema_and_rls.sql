-- Keep the deployed schema aligned with RemoteSessionInsert and
-- RemoteSetInsert, then replace broad RLS policies with explicit operations.

alter table public.sessions
  add column elevation_gain_m integer,
  add column terrain text,
  add column calories integer,
  add constraint sessions_elevation_gain_m_check
    check (elevation_gain_m is null or elevation_gain_m >= 0),
  add constraint sessions_terrain_check
    check (terrain is null or terrain in ('road', 'trail', 'treadmill', 'track')),
  add constraint sessions_calories_check
    check (calories is null or calories >= 0);

alter table public.session_sets
  drop constraint session_sets_set_type_check,
  add constraint session_sets_set_type_check
    check (
      set_type is null
      or set_type in ('warmup', 'drop', 'failure', 'restPause', 'repsInReserve')
      or set_type like 'ironlog:v1:%'
    );

revoke all on table
  public.exercises,
  public.sessions,
  public.session_sets,
  public.personal_records,
  public.routines
from public, anon, authenticated;

grant select, insert on table public.exercises to authenticated;
grant select, insert, update, delete on table
  public.sessions,
  public.session_sets,
  public.personal_records,
  public.routines
to authenticated;

drop policy if exists "Anyone can read exercises" on public.exercises;
drop policy if exists "Anyone can insert exercises" on public.exercises;
drop policy if exists "Users manage own sessions" on public.sessions;
drop policy if exists "Users manage own session sets" on public.session_sets;
drop policy if exists "Users manage own PRs" on public.personal_records;
drop policy if exists "Users manage own routines" on public.routines;

create policy "Authenticated users can read exercises"
on public.exercises for select to authenticated
using (true);

create policy "Authenticated users can create exercises"
on public.exercises for insert to authenticated
with check (char_length(trim(name)) > 0);

create policy "Users can read own sessions"
on public.sessions for select to authenticated
using ((select auth.uid()) = user_id);

create policy "Users can create own sessions"
on public.sessions for insert to authenticated
with check ((select auth.uid()) = user_id);

create policy "Users can update own sessions"
on public.sessions for update to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

create policy "Users can delete own sessions"
on public.sessions for delete to authenticated
using ((select auth.uid()) = user_id);

create policy "Users can read own session sets"
on public.session_sets for select to authenticated
using (exists (
  select 1 from public.sessions s
  where s.id = session_sets.session_id and s.user_id = (select auth.uid())
));

create policy "Users can create own session sets"
on public.session_sets for insert to authenticated
with check (exists (
  select 1 from public.sessions s
  where s.id = session_sets.session_id and s.user_id = (select auth.uid())
));

create policy "Users can update own session sets"
on public.session_sets for update to authenticated
using (exists (
  select 1 from public.sessions s
  where s.id = session_sets.session_id and s.user_id = (select auth.uid())
))
with check (exists (
  select 1 from public.sessions s
  where s.id = session_sets.session_id and s.user_id = (select auth.uid())
));

create policy "Users can delete own session sets"
on public.session_sets for delete to authenticated
using (exists (
  select 1 from public.sessions s
  where s.id = session_sets.session_id and s.user_id = (select auth.uid())
));

create policy "Users can read own personal records"
on public.personal_records for select to authenticated
using ((select auth.uid()) = user_id);

create policy "Users can create own personal records"
on public.personal_records for insert to authenticated
with check ((select auth.uid()) = user_id);

create policy "Users can update own personal records"
on public.personal_records for update to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

create policy "Users can delete own personal records"
on public.personal_records for delete to authenticated
using ((select auth.uid()) = user_id);

create policy "Users can read own routines"
on public.routines for select to authenticated
using ((select auth.uid()) = user_id);

create policy "Users can create own routines"
on public.routines for insert to authenticated
with check ((select auth.uid()) = user_id);

create policy "Users can update own routines"
on public.routines for update to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

create policy "Users can delete own routines"
on public.routines for delete to authenticated
using ((select auth.uid()) = user_id);
