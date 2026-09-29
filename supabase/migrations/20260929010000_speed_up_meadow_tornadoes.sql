alter table public.meadow_tornadoes
drop constraint if exists meadow_tornadoes_speed_check;

update public.meadow_tornadoes
set speed = 32 + random() * 18;

alter table public.meadow_tornadoes
add constraint meadow_tornadoes_speed_check check (speed between 32 and 50);