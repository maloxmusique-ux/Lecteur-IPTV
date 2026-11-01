-- Codes cadeaux : 1 mois, 12 mois ou a vie, crees depuis le portail.
create table if not exists public.promo_codes (
  code        text primary key,
  months      integer not null,            -- 0 = a vie
  max_uses    integer not null default 1,  -- nombre de personnes qui peuvent l'utiliser
  uses        integer not null default 0,
  note        text,                        -- ex. "pour Marc"
  disabled    boolean not null default false,
  created_at  timestamptz not null default now()
);

create table if not exists public.redemptions (
  id          bigserial primary key,
  code        text not null references public.promo_codes(code) on delete cascade,
  mac         text not null references public.devices(mac) on delete cascade,
  created_at  timestamptz not null default now(),
  unique (code, mac)
);

alter table public.promo_codes enable row level security;
alter table public.redemptions enable row level security;
