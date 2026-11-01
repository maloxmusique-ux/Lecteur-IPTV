-- Licences par appareil (adresse MAC generee par l'app).
-- Seules les fonctions serveur (cle service_role) lisent et ecrivent ces tables.

create table if not exists public.devices (
  mac            text primary key,
  secret_hash    text not null,
  platform       text,
  trial_ends_at  timestamptz not null default (now() + interval '7 days'),
  created_at     timestamptz not null default now(),
  last_seen_at   timestamptz not null default now()
);

create table if not exists public.licenses (
  mac                     text primary key references public.devices(mac) on delete cascade,
  plan                    text not null,          -- monthly, quarterly, semiannual, yearly, lifetime
  status                  text not null,          -- active, canceled, expired
  expires_at              timestamptz,            -- null = a vie
  auto_renew              boolean not null default false,
  source                  text not null default 'stripe', -- stripe, apple, google, gift
  stripe_customer_id      text,
  stripe_subscription_id  text unique,
  note                    text,                   -- ex. "cadeau a Marc"
  updated_at              timestamptz not null default now()
);

create table if not exists public.payments (
  id              text primary key,               -- id Stripe (facture ou paiement)
  mac             text not null references public.devices(mac) on delete cascade,
  plan            text,
  amount_cents    integer not null,
  currency        text not null default 'cad',
  receipt_url     text,
  created_at      timestamptz not null default now()
);

create index if not exists payments_mac_idx on public.payments(mac, created_at desc);

-- Personne ne peut lire ces tables avec la cle publique de l'app.
alter table public.devices  enable row level security;
alter table public.licenses enable row level security;
alter table public.payments enable row level security;

-- Vue pratique pour le tableau de bord (Supabase > Table editor).
create or replace view public.dashboard as
select d.mac, d.platform, d.created_at as installed_at, d.trial_ends_at,
       l.plan, l.status, l.expires_at, l.auto_renew, l.source, l.note,
       (select coalesce(sum(p.amount_cents), 0) / 100.0 from public.payments p where p.mac = d.mac) as total_paid
from public.devices d left join public.licenses l on l.mac = d.mac
order by d.created_at desc;
