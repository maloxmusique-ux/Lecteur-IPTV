// Outils partages par les fonctions de licence.
import Stripe from "npm:stripe@17.7.0";
import { createClient } from "npm:@supabase/supabase-js@2.49.4";

export const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY") ?? "", {
  httpClient: Stripe.createFetchHttpClient(),
});
export const cryptoProvider = Stripe.createSubtleCryptoProvider();

export const db = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  { auth: { persistSession: false } },
);

export const PLANS: Record<string, { months: number }> = {
  monthly: { months: 1 },
  quarterly: { months: 3 },
  semiannual: { months: 6 },
  yearly: { months: 12 },
  lifetime: { months: 0 },
};

/** Identifiant Stripe du prix d'un forfait (variables STRIPE_PRICE_MONTHLY...). */
export function priceFor(plan: string): string | undefined {
  return Deno.env.get(`STRIPE_PRICE_${plan.toUpperCase()}`) ?? undefined;
}

export async function sha256(text: string): Promise<string> {
  const data = new TextEncoder().encode(text);
  const hash = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(hash)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

export const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

/** Fin de periode d'un abonnement (compatible anciennes et nouvelles API). */
export function periodEnd(sub: Stripe.Subscription): string | null {
  // deno-lint-ignore no-explicit-any
  const s = sub as any;
  const end = s.current_period_end ?? s.items?.data?.[0]?.current_period_end;
  return end ? new Date(end * 1000).toISOString() : null;
}

/** Enregistre l'etat d'un abonnement Stripe dans la table licenses. */
export async function saveSubscription(sub: Stripe.Subscription, mac?: string) {
  const device = mac ?? sub.metadata?.mac;
  if (!device) return;
  const plan = sub.metadata?.plan ?? "monthly";
  const alive = ["active", "trialing", "past_due"].includes(sub.status);
  await db.from("licenses").upsert({
    mac: device,
    plan,
    status: alive ? (sub.cancel_at_period_end ? "canceled" : "active") : "expired",
    expires_at: periodEnd(sub),
    auto_renew: alive && !sub.cancel_at_period_end,
    source: "stripe",
    stripe_customer_id: typeof sub.customer === "string" ? sub.customer : sub.customer?.id,
    stripe_subscription_id: sub.id,
    updated_at: new Date().toISOString(),
  });
}
