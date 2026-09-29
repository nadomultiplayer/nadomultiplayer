alter table public.meadow_tornadoes
  add column if not exists intensity smallint not null default 0,
  add column if not exists wind_speed_mph integer not null default 75;

alter table public.meadow_tornadoes
  drop constraint if exists meadow_tornadoes_speed_check,
  drop constraint if exists meadow_tornadoes_intensity_check,
  drop constraint if exists meadow_tornadoes_wind_speed_mph_check;

with draws as (
  select
    id,
    random() as severity_roll,
    random() as wind_roll,
    random() as movement_roll
  from public.meadow_tornadoes
), ratings as (
  select
    id,
    case
      when severity_roll < 0.45 then 0
      when severity_roll < 0.72 then 1
      when severity_roll < 0.88 then 2
      when severity_roll < 0.96 then 3
      when severity_roll < 0.99 then 4
      else 5
    end as intensity,
    wind_roll,
    movement_roll
  from draws
)
update public.meadow_tornadoes as storm
set intensity = ratings.intensity,
    wind_speed_mph = case ratings.intensity
      when 0 then 65 + floor(ratings.wind_roll * 21)::integer
      when 1 then 86 + floor(ratings.wind_roll * 25)::integer
      when 2 then 111 + floor(ratings.wind_roll * 25)::integer
      when 3 then 136 + floor(ratings.wind_roll * 30)::integer
      when 4 then 166 + floor(ratings.wind_roll * 35)::integer
      else 201 + floor(ratings.wind_roll * 70)::integer
    end,
    speed = 28 + ratings.intensity * 6 + ratings.movement_roll * 10
from ratings
where storm.id = ratings.id;

alter table public.meadow_tornadoes
  add constraint meadow_tornadoes_speed_check check (speed between 28 and 78),
  add constraint meadow_tornadoes_intensity_check check (intensity between 0 and 5),
  add constraint meadow_tornadoes_wind_speed_mph_check check (wind_speed_mph between 65 and 270);

create or replace function public.advance_meadow_tornadoes()
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog, public
as $$
declare
  server_now timestamptz := clock_timestamp();
  storm record;
  elapsed_seconds double precision;
  next_heading double precision;
  next_x double precision;
  next_y double precision;
  next_steer_at timestamptz;
  storm_state jsonb;
  spawn_index integer;
  severity_roll double precision;
  storm_intensity smallint;
  wind_roll double precision;
  storm_wind_mph integer;
begin
  perform pg_advisory_xact_lock(hashtext('stormwatch:meadow-tornadoes'));
  server_now := clock_timestamp();

  if not exists (select 1 from public.meadow_tornadoes) then
    for spawn_index in 1..3 loop
      severity_roll := random();
      wind_roll := random();
      storm_intensity := case
        when severity_roll < 0.45 then 0
        when severity_roll < 0.72 then 1
        when severity_roll < 0.88 then 2
        when severity_roll < 0.96 then 3
        when severity_roll < 0.99 then 4
        else 5
      end;
      storm_wind_mph := case storm_intensity
        when 0 then 65 + floor(wind_roll * 21)::integer
        when 1 then 86 + floor(wind_roll * 25)::integer
        when 2 then 111 + floor(wind_roll * 25)::integer
        when 3 then 136 + floor(wind_roll * 30)::integer
        when 4 then 166 + floor(wind_roll * 35)::integer
        else 201 + floor(wind_roll * 70)::integer
      end;

      insert into public.meadow_tornadoes (
        x, y, heading, speed, updated_at, steer_at, intensity, wind_speed_mph
      ) values (
        60 + random() * 2480,
        60 + random() * 1780,
        random() * 2 * pi(),
        28 + storm_intensity * 6 + random() * 10,
        server_now,
        server_now + interval '1 second' + random() * interval '3 seconds',
        storm_intensity,
        storm_wind_mph
      );
    end loop;
  end if;

  for storm in
    select id, x, y, heading, speed, updated_at, steer_at, intensity, wind_speed_mph
    from public.meadow_tornadoes
    for update
  loop
    elapsed_seconds := greatest(
      0,
      least(4, extract(epoch from (server_now - storm.updated_at)))
    );
    next_heading := storm.heading + (random() - 0.5) * (1.2 + storm.intensity * 0.25);
    next_steer_at := storm.steer_at;
    next_steer_at := server_now + interval '1 second' + random() * interval '3 seconds';

    next_x := storm.x + cos(next_heading) * storm.speed * elapsed_seconds;
    next_y := storm.y + sin(next_heading) * storm.speed * elapsed_seconds;

    if next_x < 60 or next_x > 2540 then
      next_heading := pi() - next_heading;
      next_x := greatest(60, least(2540, next_x));
    end if;
    if next_y < 60 or next_y > 1840 then
      next_heading := -next_heading;
      next_y := greatest(60, least(1840, next_y));
    end if;

    update public.meadow_tornadoes
    set x = next_x,
        y = next_y,
        heading = next_heading,
        updated_at = server_now,
        steer_at = next_steer_at
    where id = storm.id;
  end loop;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', id,
        'x', x,
        'y', y,
        'heading', heading,
        'speed', speed,
        'updated_at', updated_at,
        'intensity', intensity,
        'ef_rating', 'EF' || intensity::text,
        'wind_speed_mph', wind_speed_mph,
        'warning_radius', 460 + intensity * 54,
        'lethal_radius', 100 + intensity * 17,
        'eye_radius', 25 + intensity * 7,
        'contract_reward', 100 + intensity * intensity * 70
      ) order by id
    ),
    '[]'::jsonb
  )
  into storm_state
  from public.meadow_tornadoes;

  return jsonb_build_object(
    'server_time', clock_timestamp(),
    'tornadoes', storm_state
  );
end;
$$;

revoke all on function public.advance_meadow_tornadoes() from public;
grant execute on function public.advance_meadow_tornadoes() to anon, authenticated;
