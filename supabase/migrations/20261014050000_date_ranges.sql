-- Replace the single start/end date with a list of date ranges, so the train
-- can have gaps: [{"start": "2026-10-14", "end": "2026-10-25"}, ...]
-- Per-day skip_dates stay for one-off days off.

alter table settings add column ranges jsonb not null default '[]';
update settings set ranges = jsonb_build_array(jsonb_build_object('start', start_date, 'end', end_date));

drop function update_settings(uuid, text, text, text, text, text, date, date, int[]);
alter table settings drop column start_date, drop column end_date;

create function in_schedule(p_date date, p_ranges jsonb, p_days int[])
returns boolean
language sql immutable as $$
  select extract(dow from p_date)::int = any (p_days)
     and exists (select 1 from jsonb_array_elements(p_ranges) r
                 where p_date between (r->>'start')::date and (r->>'end')::date);
$$;

create or replace function check_signup(p_date date, p_name text, p_email text, p_phone text)
returns void
language plpgsql stable set search_path = public as $$
declare s settings;
begin
  select * into s from settings where settings.id = 1;
  if not in_schedule(p_date, s.ranges, s.meal_days) or p_date = any (s.skip_dates) then
    raise exception 'That day is not part of the meal train';
  end if;
  if length(trim(coalesce(p_name, ''))) = 0 then raise exception 'Please enter your name'; end if;
  if trim(coalesce(p_email, '')) !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Please enter a valid email'; end if;
  if length(trim(coalesce(p_phone, ''))) = 0 then raise exception 'Please enter your phone number'; end if;
end $$;

create function update_settings(
  p_token uuid, p_headline text, p_message text, p_address text, p_dropoff_window text,
  p_dietary_notes text, p_ranges jsonb, p_meal_days int[]
) returns void
language plpgsql security definer set search_path = public as $$
declare stranded int; r jsonb;
begin
  if not is_organizer_session(p_token) then raise exception 'Please log in again'; end if;
  if jsonb_typeof(p_ranges) <> 'array' or jsonb_array_length(p_ranges) = 0 then
    raise exception 'Add at least one date range';
  end if;
  for r in select * from jsonb_array_elements(p_ranges) loop
    if (r->>'start') is null or (r->>'end') is null then raise exception 'Every range needs a start and end date'; end if;
    if (r->>'end')::date < (r->>'start')::date then raise exception 'Each range must end on or after its start date'; end if;
  end loop;
  if coalesce(cardinality(p_meal_days), 0) = 0 then raise exception 'Pick at least one meal day'; end if;
  -- Don't silently hide meals people already signed up for.
  select count(*) into stranded from signups where not in_schedule(meal_date, p_ranges, p_meal_days);
  if stranded > 0 then
    raise exception '% signup(s) would fall outside these dates/days. Ask them to move first.', stranded;
  end if;
  update settings set
    headline = coalesce(nullif(trim(p_headline), ''), 'Meal Train'),
    message = coalesce(p_message, ''), address = coalesce(p_address, ''),
    dropoff_window = coalesce(p_dropoff_window, ''), dietary_notes = coalesce(p_dietary_notes, ''),
    ranges = (select jsonb_agg(jsonb_build_object('start', (x->>'start')::date, 'end', (x->>'end')::date)
                               order by (x->>'start')::date) from jsonb_array_elements(p_ranges) x),
    meal_days = p_meal_days
  where id = 1;
end $$;

revoke all on function update_settings from public;
grant execute on function update_settings to anon, authenticated;
revoke all on function in_schedule from public, anon, authenticated;
