create table if not exists public.appointments (
  id uuid primary key default gen_random_uuid(),
  customer_name text not null check (char_length(customer_name) between 2 and 100),
  customer_phone text not null check (customer_phone ~ '^[0-9]{10}$'),
  service text not null check (char_length(service) between 2 and 120),
  appointment_date date not null,
  appointment_time text not null check (
    appointment_time in (
      '11:00 AM – 1:00 PM',
      '1:00 PM – 3:00 PM',
      '3:00 PM – 5:00 PM',
      '5:00 PM – 7:00 PM',
      '7:00 PM – 9:00 PM'
    )
  ),
  notes text not null default '' check (char_length(notes) <= 1000),
  status text not null default 'booked' check (status in ('booked', 'cancelled')),
  created_at timestamptz not null default now()
);

create unique index if not exists appointments_one_active_booking_per_slot
  on public.appointments (appointment_date, appointment_time)
  where status = 'booked';

create table if not exists public.blocked_slots (
  appointment_date date not null,
  appointment_time text not null check (
    appointment_time in (
      '11:00 AM – 1:00 PM',
      '1:00 PM – 3:00 PM',
      '3:00 PM – 5:00 PM',
      '5:00 PM – 7:00 PM',
      '7:00 PM – 9:00 PM'
    )
  ),
  created_at timestamptz not null default now(),
  primary key (appointment_date, appointment_time)
);

alter table public.appointments enable row level security;
alter table public.blocked_slots enable row level security;
grant usage on schema public to anon, authenticated;

revoke all on public.appointments, public.blocked_slots from anon, authenticated;

create or replace function public.get_slot_status(p_date date)
returns table (time_slot text, slot_status text)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if p_date is null then
    raise exception 'A booking date is required.';
  end if;

  return query
  select slots.time_slot,
    case
      when p_date < (now() at time zone 'Asia/Kolkata')::date then 'past'
      when exists (
        select 1 from public.blocked_slots b
        where b.appointment_date = p_date and b.appointment_time = slots.time_slot
      ) then 'blocked'
      when exists (
        select 1 from public.appointments a
        where a.appointment_date = p_date
          and a.appointment_time = slots.time_slot
          and a.status = 'booked'
      ) then 'booked'
      when p_date = (now() at time zone 'Asia/Kolkata')::date
        and (now() at time zone 'Asia/Kolkata')::time >= (case slots.time_slot
          when '11:00 AM – 1:00 PM' then time '13:00'
          when '1:00 PM – 3:00 PM' then time '15:00'
          when '3:00 PM – 5:00 PM' then time '17:00'
          when '5:00 PM – 7:00 PM' then time '19:00'
          else time '21:00'
        end) then 'past'
      else 'available'
    end
  from (values
    ('11:00 AM – 1:00 PM'::text),
    ('1:00 PM – 3:00 PM'::text),
    ('3:00 PM – 5:00 PM'::text),
    ('5:00 PM – 7:00 PM'::text),
    ('7:00 PM – 9:00 PM'::text)
  ) as slots(time_slot)
  order by slots.time_slot;
end;
$$;

create or replace function public.create_appointment(
  p_customer_name text,
  p_customer_phone text,
  p_service text,
  p_date date,
  p_time_slot text,
  p_notes text default ''
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  new_appointment_id uuid;
begin
  if p_customer_name is null or char_length(btrim(p_customer_name)) not between 2 and 100 then
    raise exception 'Enter a name between 2 and 100 characters.';
  end if;
  if p_customer_phone is null or btrim(p_customer_phone) !~ '^[0-9]{10}$' then
    raise exception 'Enter a valid 10-digit phone number.';
  end if;
  if p_service is null or char_length(btrim(p_service)) not between 2 and 120 then
    raise exception 'Choose a service or package.';
  end if;
  if p_notes is not null and char_length(p_notes) > 1000 then
    raise exception 'Appointment notes must be 1000 characters or fewer.';
  end if;
  if p_date is null or p_date < (now() at time zone 'Asia/Kolkata')::date then
    raise exception 'Choose today or a future date.';
  end if;
  if p_time_slot is null or p_time_slot not in (
    '11:00 AM – 1:00 PM',
    '1:00 PM – 3:00 PM',
    '3:00 PM – 5:00 PM',
    '5:00 PM – 7:00 PM',
    '7:00 PM – 9:00 PM'
  ) then
    raise exception 'Choose a valid appointment time.';
  end if;
  if p_date = (now() at time zone 'Asia/Kolkata')::date
    and (now() at time zone 'Asia/Kolkata')::time >= (case p_time_slot
      when '11:00 AM – 1:00 PM' then time '13:00'
      when '1:00 PM – 3:00 PM' then time '15:00'
      when '3:00 PM – 5:00 PM' then time '17:00'
      when '5:00 PM – 7:00 PM' then time '19:00'
      else time '21:00'
    end) then
    raise exception using message = 'SLOT_PASSED', errcode = 'P0001';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(p_date::text || ':' || p_time_slot, 0)
  );

  if exists (
    select 1 from public.blocked_slots
    where appointment_date = p_date and appointment_time = p_time_slot
  ) then
    raise exception using message = 'SLOT_UNAVAILABLE', errcode = 'P0001';
  end if;

  insert into public.appointments (
    customer_name, customer_phone, service, appointment_date, appointment_time, notes
  )
  values (
    btrim(p_customer_name), btrim(p_customer_phone), btrim(p_service),
    p_date, p_time_slot, coalesce(p_notes, '')
  )
  returning id into new_appointment_id;

  return new_appointment_id;
exception
  when unique_violation then
    raise exception using message = 'SLOT_ALREADY_BOOKED', errcode = 'P0001';
end;
$$;

revoke all on function public.get_slot_status(date) from public;
revoke all on function public.create_appointment(text, text, text, date, text, text) from public;

grant execute on function public.get_slot_status(date) to anon, authenticated;
grant execute on function public.create_appointment(text, text, text, date, text, text) to anon, authenticated;

create table if not exists public.customer_reviews (
  id uuid primary key default gen_random_uuid(),
  display_name text not null check (char_length(display_name) between 2 and 60),
  rating integer not null check (rating between 1 and 5),
  review_text text not null check (char_length(review_text) between 10 and 500),
  created_at timestamptz not null default now()
);

create index if not exists customer_reviews_newest_first
  on public.customer_reviews (created_at desc);

alter table public.customer_reviews enable row level security;
revoke all on public.customer_reviews from anon, authenticated;

create or replace function public.get_customer_reviews()
returns table (display_name text, rating integer, review_text text, created_at timestamptz)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select r.display_name, r.rating, r.review_text, r.created_at
  from public.customer_reviews r
  order by r.created_at desc
  limit 100;
$$;

create or replace function public.submit_customer_review(
  p_display_name text,
  p_rating integer,
  p_review_text text
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  new_review_id uuid;
begin
  if p_display_name is null or char_length(btrim(p_display_name)) not between 2 and 60 then
    raise exception 'Enter a name between 2 and 60 characters.';
  end if;
  if p_rating is null or p_rating not between 1 and 5 then
    raise exception 'Choose a rating from 1 to 5 stars.';
  end if;
  if p_review_text is null or char_length(btrim(p_review_text)) not between 10 and 500 then
    raise exception 'Write a review between 10 and 500 characters.';
  end if;

  insert into public.customer_reviews (display_name, rating, review_text)
  values (btrim(p_display_name), p_rating, btrim(p_review_text))
  returning id into new_review_id;

  return new_review_id;
end;
$$;

revoke all on function public.get_customer_reviews() from public;
revoke all on function public.submit_customer_review(text, integer, text) from public;
grant execute on function public.get_customer_reviews() to anon, authenticated;
grant execute on function public.submit_customer_review(text, integer, text) to anon, authenticated;
