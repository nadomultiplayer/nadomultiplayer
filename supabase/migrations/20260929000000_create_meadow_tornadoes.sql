create table if not exists public.meadow_tornadoes (
  id uuid primary key default gen_random_uuid(),
  x double precision not null check (x between 60 and 2540),
  y double precision not null check (y between 60 and 1840),
  heading double precision not null,
  speed double precision not null check (speed between 32 and 50),
  updated_at timestamptz not null,
  steer_at timestamptz not null
);

alter table public.meadow_tornadoes enable row level security;
revoke all on table public.meadow_tornadoes from anon, authenticated;

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
begin
  perform pg_advisory_xact_lock(hashtext('stormwatch:meadow-tornadoes'));
  server_now := clock_timestamp();

  if not exists (select 1 from public.meadow_tornadoes) then
    for spawn_index in 1..3 loop
      insert into public.meadow_tornadoes (x, y, heading, speed, updated_at, steer_at)
      values (
        60 + random() * 2480,
        60 + random() * 1780,
        random() * 2 * pi(),
        32 + random() * 18,
        server_now,
        server_now + interval '12 seconds' + random() * interval '13 seconds'
      );
    end loop;
  end if;

  for storm in
    select id, x, y, heading, speed, updated_at, steer_at
    from public.meadow_tornadoes
    for update
  loop
    elapsed_seconds := greatest(
      0,
      least(5, extract(epoch from (server_now - storm.updated_at)))
    );
    next_heading := storm.heading;
    next_steer_at := storm.steer_at;

    if next_steer_at <= server_now then
      next_heading := next_heading + (random() - 0.5) * 1.6;
      next_steer_at := server_now + interval '12 seconds' + random() * interval '18 seconds';
    end if;

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
        'lethal_radius', 118
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