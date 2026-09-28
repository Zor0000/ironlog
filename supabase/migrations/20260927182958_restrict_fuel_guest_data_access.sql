-- Fuel Buddy guests receive anonymous Auth sessions in a separate client.
-- They may read the shared exercise library but cannot modify it. Workout
-- tables retain their existing user_id ownership policies.
drop policy if exists "Authenticated users can create exercises" on public.exercises;
create policy "Named users can create exercises"
on public.exercises for insert to authenticated
with check (
  char_length(trim(name)) > 0
  and (select auth.jwt() ->> 'is_anonymous') is distinct from 'true'
);
