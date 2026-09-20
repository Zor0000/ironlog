-- Cover foreign keys used when resolving records and workout sets by exercise.
-- These indexes remove the database advisor's unindexed-FK findings without
-- changing the ownership model enforced by RLS.
create index if not exists personal_records_exercise_id_idx
  on public.personal_records (exercise_id);

create index if not exists session_sets_exercise_id_idx
  on public.session_sets (exercise_id);
