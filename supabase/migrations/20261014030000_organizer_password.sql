-- Replace the organizer email check with a password. Logging in returns a
-- session token the browser keeps; it unlocks editing details and seeing
-- everyone's email/phone. The password itself is set outside of migrations:
--   update settings set organizer_password_hash = extensions.crypt('<pw>', extensions.gen_salt('bf'));

create extension if not exists pgcrypto with schema extensions;

drop function update_settings(text, text, text, text, text, text, date, date, int[]);
drop function is_organizer(text);
alter table settings drop column organizer_email;
alter table settings add column organizer_password_hash text not null default '';

create table organizer_sessions (
  token uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now()
);
create table organizer_failed_logins (at timestamptz not null default now());
alter table organizer_sessions enable row level security;
alter table organizer_failed_logins enable row level security;

create or replace function get_schedule()
returns json
language sql stable security definer set search_path = public as $$
  select json_build_object(
    'settings', (select to_jsonb(s) - 'organizer_password_hash' from settings s where s.id = 1),
    'signups', coalesce((select json_agg(json_build_object(
        'id', id, 'meal_date', meal_date, 'name', name, 'meal', meal, 'notes', notes
      ) order by meal_date) from signups), '[]'::json)
  );
$$;

-- Returns {"token": ...} or {"error": ...}. Returns instead of raising so failed
-- attempts are recorded. Throttled to 10 failures per 15 minutes.
create function organizer_login(p_password text)
returns json
language plpgsql security definer set search_path = public as $$
declare h text; t uuid;
begin
  if (select count(*) from organizer_failed_logins where at > now() - interval '15 minutes') >= 10 then
    return json_build_object('error', 'Too many tries. Wait 15 minutes and try again.');
  end if;
  select organizer_password_hash into h from settings where id = 1;
  if h <> '' and extensions.crypt(coalesce(p_password, ''), h) = h then
    delete from organizer_sessions where created_at < now() - interval '1 year';
    insert into organizer_sessions default values returning token into t;
    return json_build_object('token', t);
  end if;
  delete from organizer_failed_logins where at < now() - interval '1 day';
  insert into organizer_failed_logins default values;
  return json_build_object('error', 'Wrong password');
end $$;

create function is_organizer_session(p_token uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from organizer_sessions where token = p_token);
$$;

create function organizer_logout(p_token uuid)
returns void
language sql security definer set search_path = public as $$
  delete from organizer_sessions where token = p_token;
$$;

create function organizer_contacts(p_token uuid)
returns table (id uuid, meal_date date, name text, email text, phone text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_organizer_session(p_token) then raise exception 'Please log in again'; end if;
  return query select s.id, s.meal_date, s.name, s.email, s.phone from signups s order by s.meal_date;
end $$;

create function update_settings(
  p_token uuid, p_headline text, p_message text, p_address text, p_dropoff_window text,
  p_dietary_notes text, p_start_date date, p_end_date date, p_meal_days int[]
) returns void
language plpgsql security definer set search_path = public as $$
declare stranded int;
begin
  if not is_organizer_session(p_token) then raise exception 'Please log in again'; end if;
  if p_start_date is null or p_end_date is null or p_end_date < p_start_date then
    raise exception 'The end date must be on or after the start date';
  end if;
  if coalesce(cardinality(p_meal_days), 0) = 0 then raise exception 'Pick at least one meal day'; end if;
  -- Don't silently hide meals people already signed up for.
  select count(*) into stranded from signups
  where meal_date < p_start_date or meal_date > p_end_date
     or not (extract(dow from meal_date)::int = any (p_meal_days));
  if stranded > 0 then
    raise exception '% signup(s) would fall outside these dates/days. Ask them to move first.', stranded;
  end if;
  update settings set
    headline = coalesce(nullif(trim(p_headline), ''), 'Meal Train'),
    message = coalesce(p_message, ''), address = coalesce(p_address, ''),
    dropoff_window = coalesce(p_dropoff_window, ''), dietary_notes = coalesce(p_dietary_notes, ''),
    start_date = p_start_date, end_date = p_end_date, meal_days = p_meal_days
  where id = 1;
end $$;

revoke all on function organizer_login, is_organizer_session, organizer_logout, organizer_contacts, update_settings from public;
grant execute on function organizer_login, is_organizer_session, organizer_logout, organizer_contacts, update_settings to anon, authenticated;
