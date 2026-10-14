-- One-time setup for attendance share links. Run in Supabase: SQL Editor > New query > paste > Run.
-- Safe to run again. It only adds new tables and functions; your "records" table is not changed.

create table if not exists shares (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users on delete cascade,
  class_id text not null,
  token_hash text not null unique,
  label text,
  expires_at timestamptz not null,
  revoked boolean not null default false,
  created_at timestamptz not null default now()
);
alter table shares enable row level security;
drop policy if exists "own shares" on shares;
create policy "own shares" on shares for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Marks made through a link. Your app merges them into your records the next time it syncs.
create table if not exists share_marks (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users on delete cascade,
  class_id text not null,
  learner_id text not null,
  day date not null,
  status text not null check (status in ('','p','x','t','c')),
  updated_at timestamptz not null default now(),
  merged_at timestamptz,
  unique (user_id, class_id, learner_id, day)
);
alter table share_marks enable row level security;
drop policy if exists "own marks" on share_marks;
create policy "own marks" on share_marks for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Internal: finds a valid, active link from its secret. Not callable from the browser.
create or replace function _share_row(p_token text) returns shares
language plpgsql security definer set search_path = public as $$
declare s shares;
begin
  select * into s from shares
   where token_hash = encode(sha256(convert_to(coalesce(p_token, ''), 'UTF8')), 'hex')
     and not revoked and expires_at > now();
  if not found then raise exception 'invalid_link'; end if;
  return s;
end $$;
revoke all on function _share_row(text) from public, anon, authenticated;

-- Roster for the link's class plus TODAY's status only (Philippine date). No LRN, birth date, QR or grades.
create or replace function share_open(p_token text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  s shares; v_data jsonb; v_cls jsonb; v_att jsonb; v_closed text := null;
  v_day date := (now() at time zone 'Asia/Manila')::date;
  v_ym text; v_d text;
begin
  s := _share_row(p_token);
  v_ym := to_char(v_day, 'YYYY-MM');
  v_d := extract(day from v_day)::int::text;
  select data into v_data from records where user_id = s.user_id;
  select c into v_cls from jsonb_array_elements(coalesce(v_data->'classes', '[]'::jsonb)) c
   where c->>'id' = s.class_id limit 1;
  if v_cls is null then raise exception 'class_not_found'; end if;
  v_att := coalesce(v_cls->'att'->v_ym, '{}'::jsonb);
  if extract(isodow from v_day) in (6, 7) then v_closed := 'weekend';
  elsif v_att->'_nc'->>v_d is not null then v_closed := 'noclass'; end if;
  return jsonb_build_object(
    'date', to_char(v_day, 'YYYY-MM-DD'),
    'school', v_data->'p'->>'school',
    'class', v_cls->>'name',
    'closed', v_closed,
    'learners', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', l->>'id', 'first', l->>'first', 'last', l->>'last', 'sex', l->>'sex', 'photo', l->'photo',
        'st', coalesce(
          (select m.status from share_marks m
            where m.user_id = s.user_id and m.class_id = s.class_id
              and m.learner_id = l->>'id' and m.day = v_day and m.merged_at is null),
          v_att->(l->>'id')->>v_d, '')
      ) order by ord)
      from jsonb_array_elements(coalesce(v_cls->'learners', '[]'::jsonb)) with ordinality as t(l, ord)
    ), '[]'::jsonb)
  );
end $$;

-- Looks up a scanned QR token inside the link's class only. Returns the student's name and today's status.
create or replace function share_scan(p_token text, p_qr text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  s shares; v_l jsonb; v_st text;
  v_day date := (now() at time zone 'Asia/Manila')::date;
begin
  s := _share_row(p_token);
  select l into v_l from records r,
         jsonb_array_elements(r.data->'classes') c,
         jsonb_array_elements(c->'learners') l
   where r.user_id = s.user_id and c->>'id' = s.class_id and l->>'qr' = p_qr limit 1;
  if v_l is null then return jsonb_build_object('found', false); end if;
  v_st := coalesce(
    (select m.status from share_marks m
      where m.user_id = s.user_id and m.class_id = s.class_id
        and m.learner_id = v_l->>'id' and m.day = v_day and m.merged_at is null),
    (select c->'att'->to_char(v_day, 'YYYY-MM')->(v_l->>'id')->>(extract(day from v_day)::int::text)
       from records r, jsonb_array_elements(r.data->'classes') c
      where r.user_id = s.user_id and c->>'id' = s.class_id limit 1),
    '');
  return jsonb_build_object('found', true, 'id', v_l->>'id', 'first', v_l->>'first', 'last', v_l->>'last', 'st', v_st);
end $$;

-- Records one status for TODAY only. p_day must equal today's Philippine date, so an old page cannot write to another day.
create or replace function share_mark(p_token text, p_learner text, p_status text, p_day text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  s shares; v_ok boolean;
  v_day date := (now() at time zone 'Asia/Manila')::date;
  v_ym text; v_d text;
begin
  s := _share_row(p_token);
  if p_status is null or p_status not in ('', 'p', 'x', 't', 'c') then raise exception 'bad_status'; end if;
  if p_day is distinct from to_char(v_day, 'YYYY-MM-DD') then raise exception 'wrong_day'; end if;
  if extract(isodow from v_day) in (6, 7) then raise exception 'closed'; end if;
  v_ym := to_char(v_day, 'YYYY-MM');
  v_d := extract(day from v_day)::int::text;
  select exists (select 1 from records r,
                        jsonb_array_elements(r.data->'classes') c,
                        jsonb_array_elements(c->'learners') l
                  where r.user_id = s.user_id and c->>'id' = s.class_id and l->>'id' = p_learner)
    into v_ok;
  if not v_ok then raise exception 'unknown_learner'; end if;
  if exists (select 1 from records r, jsonb_array_elements(r.data->'classes') c
              where r.user_id = s.user_id and c->>'id' = s.class_id
                and c->'att'->v_ym->'_nc'->>v_d is not null) then
    raise exception 'closed';
  end if;
  insert into share_marks (user_id, class_id, learner_id, day, status)
  values (s.user_id, s.class_id, p_learner, v_day, p_status)
  on conflict (user_id, class_id, learner_id, day)
  do update set status = excluded.status, updated_at = now(), merged_at = null;
  return jsonb_build_object('date', to_char(v_day, 'YYYY-MM-DD'), 'id', p_learner, 'st', p_status);
end $$;

revoke all on function share_open(text), share_scan(text, text), share_mark(text, text, text, text) from public;
grant execute on function share_open(text), share_scan(text, text), share_mark(text, text, text, text) to anon, authenticated;
