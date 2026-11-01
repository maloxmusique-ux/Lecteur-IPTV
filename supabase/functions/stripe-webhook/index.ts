// Evenements Stripe : paiements, renouvellements, annulations.
import { cryptoProvider, db, saveSubscription, stripe } from "../_shared/common.ts";
import type Stripe from "npm:stripe@17.7.0";

async function addPayment(p: {
  id: string; mac: string; plan?: string | null; amount: number; currency: string; receipt?: string | null;
}) {
  await db.from("payments").upsert({
    id: p.id,
    mac: p.mac,
    plan: p.plan ?? null,
    amount_cents: p.amount,
    currency: p.currency,
    receipt_url: p.receipt ?? null,
  });
}

Deno.serve(async (req) => {
  const sig = req.headers.get("Stripe-Signature");
  const body = await req.text();
  let event: Stripe.Event;
  try {
    event = await stripe.webhooks.constructEventAsync(
      body, sig ?? "", Deno.env.get("STRIPE_WEBHOOK_SECRET") ?? "", undefined, cryptoProvider,
    );
  } catch (_) {
    return new Response("bad signature", { status: 400 });
  }

  try {
    switch (event.type) {
      case "checkout.session.completed": {
        const s = event.data.object as Stripe.Checkout.Session;
        const mac = s.metadata?.mac ?? s.client_reference_id;
        const plan = s.metadata?.plan ?? null;
        if (!mac) break;
        if (s.mode === "payment") {
          // Achat a vie.
          await db.from("licenses").upsert({
            mac, plan: "lifetime", status: "active", expires_at: null, auto_renew: false,
            source: "stripe",
            stripe_customer_id: typeof s.customer === "string" ? s.customer : null,
            stripe_subscription_id: null,
            updated_at: new Date().toISOString(),
          });
          let receipt: string | null = null;
          if (typeof s.payment_intent === "string") {
            const pi = await stripe.paymentIntents.retrieve(s.payment_intent, { expand: ["latest_charge"] });
            // deno-lint-ignore no-explicit-any
            receipt = (pi.latest_charge as any)?.receipt_url ?? null;
          }
          await addPayment({
            id: String(s.payment_intent ?? s.id), mac, plan,
            amount: s.amount_total ?? 0, currency: s.currency ?? "cad", receipt,
          });
        } else if (typeof s.subscription === "string") {
          // Nouvel abonnement : on arrete l'ancien s'il existe (changement de forfait).
          const { data: old } = await db.from("licenses").select("stripe_subscription_id").eq("mac", mac).maybeSingle();
          if (old?.stripe_subscription_id && old.stripe_subscription_id !== s.subscription) {
            try { await stripe.subscriptions.cancel(old.stripe_subscription_id); } catch (_) { /* deja termine */ }
          }
          const sub = await stripe.subscriptions.retrieve(s.subscription);
          await saveSubscription(sub, mac);
        }
        break;
      }

      case "invoice.paid": {
        const inv = event.data.object as Stripe.Invoice;
        // deno-lint-ignore no-explicit-any
        const subId = (inv as any).subscription ?? (inv as any).parent?.subscription_details?.subscription;
        if (!subId) break;
        const sub = await stripe.subscriptions.retrieve(String(subId));
        await saveSubscription(sub);
        if (sub.metadata?.mac && inv.amount_paid > 0) {
          await addPayment({
            id: inv.id ?? String(Date.now()), mac: sub.metadata.mac, plan: sub.metadata.plan,
            amount: inv.amount_paid, currency: inv.currency, receipt: inv.hosted_invoice_url,
          });
        }
        break;
      }

      case "customer.subscription.updated":
      case "customer.subscription.deleted": {
        const sub = event.data.object as Stripe.Subscription;
        // On ne touche qu'a l'abonnement actuel de l'appareil.
        const { data: l } = await db.from("licenses").select("stripe_subscription_id")
          .eq("mac", sub.metadata?.mac ?? "").maybeSingle();
        if (l && l.stripe_subscription_id && l.stripe_subscription_id !== sub.id) break;
        await saveSubscription(sub);
        break;
      }
    }
  } catch (e) {
    console.error(e);
    return new Response("error", { status: 500 });
  }
  return new Response("ok");
});
