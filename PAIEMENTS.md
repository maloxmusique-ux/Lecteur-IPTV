# Mettre en place les paiements (Stripe + Supabase)

Tant que ces étapes ne sont pas faites, l'app est en **mode test** : l'essai de 7 jours,
les forfaits et l'annulation fonctionnent, mais les paiements sont simulés.

Compte environ 1 heure, une seule fois. Claude peut te guider écran par écran.

## 1. Stripe (encaisser les paiements)

1. Crée un compte sur https://dashboard.stripe.com/register (au nom de ton entreprise).
2. Active le compte : informations de l'entreprise, compte bancaire pour les versements.
3. **Catalogue de produits > Ajouter un produit** : un produit nommé comme l'app, avec 5 prix en CAD :

| Forfait | Prix | Type |
|---|---|---|
| Mensuel | 2,99 $ | Récurrent, tous les 1 mois |
| 3 mois | 7,99 $ | Récurrent, tous les 3 mois |
| 6 mois | 12,99 $ | Récurrent, tous les 6 mois |
| Annuel | 19,99 $ | Récurrent, tous les 12 mois |
| À vie | 39,99 $ | Paiement unique |

4. Note l'identifiant de chaque prix (commence par `price_...`).
5. **Paramètres > Facturation > Portail client et reçus** : active l'envoi des reçus par courriel.
6. Taxes : **Stripe Tax** peut calculer TPS/TVQ automatiquement (à valider avec ton comptable).

## 2. Supabase (la liste des appareils et des abonnements)

1. Crée un projet sur https://supabase.com (région Canada si possible).
2. **SQL Editor** : colle et exécute le contenu de `supabase/migrations/20261101000000_licences.sql`.
3. **Edge Functions > Secrets**, ajoute :
   - `STRIPE_SECRET_KEY` : clé secrète Stripe (`sk_live_...`)
   - `STRIPE_PRICE_MONTHLY`, `STRIPE_PRICE_QUARTERLY`, `STRIPE_PRICE_SEMIANNUAL`, `STRIPE_PRICE_YEARLY`, `STRIPE_PRICE_LIFETIME` : les identifiants `price_...`
   - `APP_NAME` : le nom de l'app
   - `STRIPE_TAX` : `1` si Stripe Tax est activé
4. Déploie les fonctions (sur le Mac ou le PC, avec la CLI Supabase) :
   ```bash
   npx supabase login
   npx supabase link --project-ref TON_PROJET
   npx supabase functions deploy license
   npx supabase functions deploy stripe-webhook
   ```

## 3. Relier Stripe au serveur (webhook)

1. Stripe > **Développeurs > Webhooks > Ajouter un endpoint**.
2. URL : `https://TON_PROJET.supabase.co/functions/v1/stripe-webhook`
3. Événements : `checkout.session.completed`, `invoice.paid`,
   `customer.subscription.updated`, `customer.subscription.deleted`.
4. Copie le **secret de signature** (`whsec_...`) et ajoute-le dans Supabase comme secret
   `STRIPE_WEBHOOK_SECRET`.

## 4. Brancher l'app

GitHub > dépôt > **Settings > Secrets and variables > Actions > onglet Variables** :
- `LICENSE_API` : `https://TON_PROJET.supabase.co/functions/v1/license`
- `LICENSE_KEY` : la clé publique « anon » de Supabase (Project Settings > API)

La prochaine compilation sortira avec les vrais paiements.

## Au quotidien

- **Voir les clients** : Supabase > Table editor > vue `dashboard` (adresse MAC, forfait, expiration, total payé).
- **Offrir un accès** : table `licenses`, ajoute une ligne avec l'adresse MAC, `plan = lifetime`,
  `status = active`, `source = gift`, et une note.
- **Rembourser** : depuis Stripe (Paiements > Rembourser). Annule aussi l'abonnement dans Stripe si besoin.
- **Revenus** : tableau de bord Stripe.
