-- Meal train: one settings row + one signup per day.
-- The public (anon key) can read the schedule but can only write through the
-- functions below. Each signup gets a secret edit_token that the browser keeps,
-- so whoever signed up can edit/cancel without needing an account.

create table settings (
  id int primary key default 1 check (id = 1),
  recipient text not null default 'Our friends',
  headline text not null default 'Meal Train',
  message text not null default '',
  address text not null default '',
  dropoff_window text not null default '5:00 – 6:00 pm',
  dietary_notes text not null default '',
  start_date date not null default current_date,
  end_date date not null default current_date + 28,
  -- 0 = Sunday … 6 = Saturday
  meal_days int[] not null default '{0,1,2,3,4,5,6}'
);
insert into settings default values;

create table signups (
  id uuid primary key default gen_random_uuid(),
  meal_date date not null unique,
  name text not null check (length(trim(name)) between 1 and 100),
  contact text not null default '' check (length(contact) <= 200),
  meal text not null default '' check (length(meal) <= 300),
  notes text not null default '' check (length(notes) <= 1000),
  edit_token uuid not null default gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table settings enable row level security;
alter table signups enable row level security;

-- No policies: direct table access is denied. Everything goes through the functions below.

-- Everything the page needs in one round trip. Hides edit tokens and contact info.
create function get_schedule()
returns json
language sql stable security definer set search_path = public as $$
  select json_build_object(
    'settings', (select row_to_json(s) from settings s where s.id = 1),
    'signups', coalesce((select json_agg(json_build_object(
        'id', id, 'meal_date', meal_date, 'name', name, 'meal', meal, 'notes', notes
      ) order by meal_date) from signups), '[]'::json)
  );
$$;

create function create_signup(p_date date, p_name text, p_contact text, p_meal text, p_notes text)
returns table (id uuid, edit_token uuid)
language plpgsql security definer set search_path = public as $$
declare s settings;
begin
  select * into s from settings where settings.id = 1;
  if p_date < s.start_date or p_date > s.end_date
     or not (extract(dow from p_date)::int = any (s.meal_days)) then
    raise exception 'That day is not part of the meal train';
  end if;
  return query
    insert into signups (meal_date, name, contact, meal, notes)
    values (p_date, trim(p_name), coalesce(p_contact, ''), coalesce(p_meal, ''), coalesce(p_notes, ''))
    returning signups.id, signups.edit_token;
exception when unique_violation then
  raise exception 'Sorry, someone just took that day';
end $$;

create function get_my_signup(p_id uuid, p_token uuid)
returns table (id uuid, meal_date date, name text, contact text, meal text, notes text)
language sql security definer set search_path = public as $$
  select id, meal_date, name, contact, meal, notes from signups
  where signups.id = p_id and edit_token = p_token;
$$;

create function update_signup(p_id uuid, p_token uuid, p_date date, p_name text, p_contact text, p_meal text, p_notes text)
returns void
language plpgsql security definer set search_path = public as $$
declare s settings;
begin
  select * into s from settings where settings.id = 1;
  if p_date < s.start_date or p_date > s.end_date
     or not (extract(dow from p_date)::int = any (s.meal_days)) then
    raise exception 'That day is not part of the meal train';
  end if;
  update signups set meal_date = p_date, name = trim(p_name), contact = coalesce(p_contact, ''),
    meal = coalesce(p_meal, ''), notes = coalesce(p_notes, ''), updated_at = now()
  where signups.id = p_id and edit_token = p_token;
  if not found then raise exception 'Could not find your signup'; end if;
exception when unique_violation then
  raise exception 'Sorry, someone already has that day';
end $$;

create function delete_signup(p_id uuid, p_token uuid)
returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from signups where signups.id = p_id and edit_token = p_token;
  if not found then raise exception 'Could not find your signup'; end if;
end $$;

revoke all on function get_schedule, create_signup, get_my_signup, update_signup, delete_signup from public;
grant execute on function get_schedule, create_signup, get_my_signup, update_signup, delete_signup to anon, authenticated;
