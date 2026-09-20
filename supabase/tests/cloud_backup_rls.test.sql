begin;

select plan(12);

select ok(
  not has_table_privilege('anon', 'public.exercises', 'select,insert,update,delete'),
  'anon cannot access the shared exercise catalogue'
);
select ok(
  not has_table_privilege('anon', 'public.sessions', 'select,insert,update,delete'),
  'anon cannot access sessions'
);
select ok(
  not has_table_privilege('anon', 'public.session_sets', 'select,insert,update,delete'),
  'anon cannot access session sets'
);
select ok(
  not has_table_privilege('anon', 'public.personal_records', 'select,insert,update,delete'),
  'anon cannot access personal records'
);
select ok(
  not has_table_privilege('anon', 'public.routines', 'select,insert,update,delete'),
  'anon cannot access routines'
);

select ok(
  has_table_privilege('authenticated', 'public.exercises', 'select,insert'),
  'authenticated users can read and add exercises'
);
select ok(
  not has_table_privilege('authenticated', 'public.exercises', 'update,delete'),
  'clients cannot rewrite the shared exercise catalogue'
);
select ok(
  has_table_privilege('authenticated', 'public.sessions', 'select,insert,update,delete'),
  'authenticated users have the session operations the app needs'
);
select ok(
  has_table_privilege('authenticated', 'public.session_sets', 'select,insert,update,delete'),
  'authenticated users have the session-set operations the app needs'
);
select ok(
  has_table_privilege('authenticated', 'public.personal_records', 'select,insert,update,delete'),
  'authenticated users have the personal-record operations the app needs'
);
select ok(
  has_table_privilege('authenticated', 'public.routines', 'select,insert,update,delete'),
  'authenticated users have the routine operations the app needs'
);
select ok(
  (select count(*) = 18 from pg_policies
   where schemaname = 'public'
     and tablename in ('exercises', 'sessions', 'session_sets', 'personal_records', 'routines')),
  'all cloud-backup tables use explicit per-operation RLS policies'
);

select * from finish();
rollback;
