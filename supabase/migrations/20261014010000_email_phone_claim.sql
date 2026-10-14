-- Separate required email + phone, and let people reclaim edit access on a new
-- device by entering the email they signed up with.

alter table signups drop column contact;
alter table signups
  add column email text not null default '' check (length(email) <= 200),
  add column phone text not null default '' check (length(phone) <= 50),
  add column failed_claims int not null default 0;
alter table signups alter column email drop default, alter column phone drop default;

drop function create_signup(date, text, text, text, text);
drop function get_my_signup(uuid, uuid);
drop function update_signup(uuid, uuid, date, text, text, text, text);

create function check_signup(p_date date, p_name text, p_email text, p_phone text)
returns void
language plpgsql stable set search_path = public as $$
declare s settings;
begin
  select * into s from settings where settings.id = 1;
  if p_date < s.start_date or p_date > s.end_date
     or not (extract(dow from p_date)::int = any (s.meal_days)) then
    raise exception 'That day is not part of the meal train';
  end if;
  if length(trim(coalesce(p_name, ''))) = 0 then raise exception 'Please enter your name'; end if;
  if trim(coalesce(p_email, '')) !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Please enter a valid email'; end if;
  if length(trim(coalesce(p_phone, ''))) = 0 then raise exception 'Please enter your phone number'; end if;
end $$;

create function create_signup(p_date date, p_name text, p_email text, p_phone text, p_meal text, p_notes text)
returns table (id uuid, edit_token uuid)
language plpgsql security definer set search_path = public as $$
begin
  perform check_signup(p_date, p_name, p_email, p_phone);
  return query
    insert into signups (meal_date, name, email, phone, meal, notes)
    values (p_date, trim(p_name), lower(trim(p_email)), trim(p_phone), coalesce(p_meal, ''), coalesce(p_notes, ''))
    returning signups.id, signups.edit_token;
exception when unique_violation then
  raise exception 'Sorry, someone just took that day';
end $$;

create function get_my_signup(p_id uuid, p_token uuid)
returns table (id uuid, meal_date date, name text, email text, phone text, meal text, notes text)
language sql security definer set search_path = public as $$
  select id, meal_date, name, email, phone, meal, notes from signups
  where signups.id = p_id and edit_token = p_token;
$$;

create function update_signup(p_id uuid, p_token uuid, p_date date, p_name text, p_email text, p_phone text, p_meal text, p_notes text)
returns void
language plpgsql security definer set search_path = public as $$
begin
  perform check_signup(p_date, p_name, p_email, p_phone);
  update signups set meal_date = p_date, name = trim(p_name), email = lower(trim(p_email)), phone = trim(p_phone),
    meal = coalesce(p_meal, ''), notes = coalesce(p_notes, ''), updated_at = now()
  where signups.id = p_id and edit_token = p_token;
  if not found then raise exception 'Could not find your signup'; end if;
exception when unique_violation then
  raise exception 'Sorry, someone already has that day';
end $$;

-- Returns {"token": ...} on a match, otherwise {"error": ...}. Returns instead of
-- raising so the failed-attempt counter isn't rolled back.
create function claim_signup(p_id uuid, p_email text)
returns json
language plpgsql security definer set search_path = public as $$
declare r signups;
begin
  select * into r from signups where signups.id = p_id for update;
  if not found then return json_build_object('error', 'That signup no longer exists'); end if;
  if r.failed_claims >= 10 then
    return json_build_object('error', 'Too many tries. Please ask the organizer for help.');
  end if;
  if r.email = lower(trim(coalesce(p_email, ''))) then
    update signups set failed_claims = 0 where signups.id = p_id;
    return json_build_object('token', r.edit_token);
  end if;
  update signups set failed_claims = failed_claims + 1 where signups.id = p_id;
  return json_build_object('error', 'That email doesn''t match this signup');
end $$;

revoke all on function check_signup, create_signup, get_my_signup, update_signup, claim_signup from public;
-- Supabase grants new functions to anon by default; check_signup is internal only.
revoke all on function check_signup from anon, authenticated;
grant execute on function create_signup, get_my_signup, update_signup, claim_signup to anon, authenticated;
