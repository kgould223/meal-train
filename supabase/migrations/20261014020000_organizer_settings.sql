-- Let the organizer edit the settings from the page by entering their email.
-- Honor-system check: anyone who knows the organizer email can edit.

alter table settings add column organizer_email text not null default '';
update settings set organizer_email = 'brookecramblitt@gmail.com' where id = 1;

-- Same as before, but never send organizer_email to the page.
create or replace function get_schedule()
returns json
language sql stable security definer set search_path = public as $$
  select json_build_object(
    'settings', (select to_jsonb(s) - 'organizer_email' from settings s where s.id = 1),
    'signups', coalesce((select json_agg(json_build_object(
        'id', id, 'meal_date', meal_date, 'name', name, 'meal', meal, 'notes', notes
      ) order by meal_date) from signups), '[]'::json)
  );
$$;

create function is_organizer(p_email text)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from settings
    where id = 1 and organizer_email <> '' and organizer_email = lower(trim(coalesce(p_email, ''))));
$$;

create function update_settings(
  p_email text, p_headline text, p_message text, p_address text, p_dropoff_window text,
  p_dietary_notes text, p_start_date date, p_end_date date, p_meal_days int[]
) returns void
language plpgsql security definer set search_path = public as $$
declare stranded int;
begin
  if not is_organizer(p_email) then raise exception 'Only the organizer can edit these details'; end if;
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

revoke all on function is_organizer, update_settings from public;
grant execute on function is_organizer, update_settings to anon, authenticated;
