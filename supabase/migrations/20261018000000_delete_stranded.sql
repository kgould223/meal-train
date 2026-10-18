-- Let the organizer change dates even when upcoming signups fall outside them:
-- the page previews the affected signups, and on confirmation they're deleted.
-- Past signups never block a change (they already happened) and are kept.

create function organizer_stranded(p_token uuid, p_ranges jsonb, p_meal_days int[])
returns table (id uuid, meal_date date, name text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_organizer_session(p_token) then raise exception 'Please log in again'; end if;
  return query select s.id, s.meal_date, s.name from signups s
    where s.meal_date >= current_date and not in_schedule(s.meal_date, p_ranges, p_meal_days)
    order by s.meal_date;
end $$;

drop function update_settings(uuid, text, text, text, text, text, jsonb, int[]);

create function update_settings(
  p_token uuid, p_headline text, p_message text, p_address text, p_dropoff_window text,
  p_dietary_notes text, p_ranges jsonb, p_meal_days int[], p_delete_stranded boolean default false
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
  if p_delete_stranded then
    delete from signups where meal_date >= current_date and not in_schedule(meal_date, p_ranges, p_meal_days);
  else
    select count(*) into stranded from signups
    where meal_date >= current_date and not in_schedule(meal_date, p_ranges, p_meal_days);
    if stranded > 0 then
      raise exception '% upcoming signup(s) fall outside these dates/days.', stranded;
    end if;
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

revoke all on function organizer_stranded, update_settings from public;
grant execute on function organizer_stranded, update_settings to anon, authenticated;
