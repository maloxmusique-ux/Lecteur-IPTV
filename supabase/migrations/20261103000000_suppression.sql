-- Suppression des donnees d'un appareil (bouton « Supprimer mes donnees »).
-- Les paiements sont gardes pour la comptabilite (6 ans), mais sans aucun
-- lien avec l'appareil ni la personne.
create table if not exists public.payments_archive (
  id            text primary key,
  plan          text,
  amount_cents  integer not null,
  currency      text not null default 'cad',
  paid_at       timestamptz not null,
  deleted_at    timestamptz not null default now()
);

alter table public.payments_archive enable row level security;
