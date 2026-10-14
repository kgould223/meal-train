-- Let the organizer skip individual days inside the start/end range
-- (e.g. a week when family is in town).

alter table settings add column skip_dates date[] not null default '{}';

create or replace function check_signup(p_date date, p_name text, p_email text, p_phone text)
returns void
language plpgsql stable set search_path = public as $$
declare s settings;
begin
  select * into s from settings where settings.id = 1;
  if p_date < s.start_date or p_date > s.end_date
     or not (extract(dow from p_date)::int = any (s.meal_days))
     or p_date = any (s.skip_dates) then
    raise exception 'That day is not part of the meal train';
  end if;
  if length(trim(coalesce(p_name, ''))) = 0 then raise exception 'Please enter your name'; end if;
  if trim(coalesce(p_email, '')) !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Please enter a valid email'; end if;
  if length(trim(coalesce(p_phone, ''))) = 0 then raise exception 'Please enter your phone number'; end if;
end $$;

create function set_day_skipped(p_token uuid, p_date date, p_skipped boolean)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_organizer_session(p_token) then raise exception 'Please log in again'; end if;
  if p_skipped then
    if exists (select 1 from signups where meal_date = p_date) then
      raise exception 'Someone is signed up that day. Ask them to move first.';
    end if;
    update settings set skip_dates = array(select distinct unnest(skip_dates || p_date) order by 1) where id = 1;
  else
    update settings set skip_dates = array_remove(skip_dates, p_date) where id = 1;
  end if;
end $$;

revoke all on function set_day_skipped from public;
grant execute on function set_day_skipped to anon, authenticated;
