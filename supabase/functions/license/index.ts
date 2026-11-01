// Licence d'un appareil : statut, paiement, annulation, reactivation.
// Appelee par l'app avec { action, device, secret, platform, plan }.
import { cors, db, json, PLANS, priceFor, sha256, stripe } from "../_shared/common.ts";

const MAC = /^[0-9A-F]{2}(:[0-9A-F]{2}){5}$/;
const TRIAL_DAYS = Number(Deno.env.get("TRIAL_DAYS") ?? "7");
const APP_NAME = Deno.env.get("APP_NAME") ?? "StreamFlow";

function page(title: string, text: string): Response {
  const html = `<!doctype html><html lang="fr"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>${title}</title>
<style>body{margin:0;min-height:100vh;display:grid;place-items:center;background:#0E1116;color:#fff;
font-family:system-ui,sans-serif;text-align:center;padding:24px}h1{font-size:28px}p{color:#bbb;font-size:18px}</style>
</head><body><div><h1>${title}</h1><p>${text}</p></div></body></html>`;
  return new Response(html, { headers: { "Content-Type": "text/html; charset=utf-8" } });
}

async function status(mac: string) {
  const { data: d } = await db.from("devices").select("*").eq("mac", mac).single();
  const { data: l } = await db.from("licenses").select("*").eq("mac", mac).maybeSingle();
  const { data: pays } = await db.from("payments").select("*").eq("mac", mac)
    .order("created_at", { ascending: false }).limit(24);
  const now = Date.now();
  const paidActive = l && l.status !== "expired" &&
    (l.expires_at === null || new Date(l.expires_at).getTime() > now);
  const inTrial = new Date(d.trial_ends_at).getTime() > now;
  return {
    status: paidActive ? "active" : (!l && inTrial ? "trial" : "expired"),
    trialEndsAt: d.trial_ends_at,
    plan: l?.plan ?? null,
    expiresAt: l?.expires_at ?? null,
    autoRenew: paidActive ? (l?.auto_renew ?? false) : false,
    source: l?.source ?? "",
    payments: (pays ?? []).map((p) => ({
      date: p.created_at,
      amount: p.amount_cents,
      currency: p.currency,
      plan: p.plan,
      receiptUrl: p.receipt_url ?? "",
    })),
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  // Pages affichees apres le paiement Stripe.
  if (req.method === "GET") {
    const u = new URL(req.url);
    if (u.searchParams.has("done")) {
      return page("Paiement réussi ✓", `Merci ! Retourne dans ${APP_NAME} : ton appareil se débloque tout seul.`);
    }
    return page("Paiement annulé", `Aucun montant n'a été prélevé. Tu peux retourner dans ${APP_NAME}.`);
  }

  try {
    const { action, device, secret, platform, plan } = await req.json();
    const mac = String(device ?? "").toUpperCase();
    if (!MAC.test(mac) || typeof secret !== "string" || secret.length < 16) {
      return json({ error: "invalid device" }, 400);
    }

    // Appareil : creation au premier appel, puis verification du secret.
    const hash = await sha256(secret);
    const { data: existing } = await db.from("devices").select("secret_hash").eq("mac", mac).maybeSingle();
    if (!existing) {
      await db.from("devices").insert({
        mac,
        secret_hash: hash,
        platform: String(platform ?? ""),
        trial_ends_at: new Date(Date.now() + TRIAL_DAYS * 86400000).toISOString(),
      });
    } else if (existing.secret_hash !== hash) {
      return json({ error: "forbidden" }, 403);
    } else {
      await db.from("devices").update({ last_seen_at: new Date().toISOString() }).eq("mac", mac);
    }

    switch (action) {
      case "status":
        return json(await status(mac));

      case "checkout": {
        const p = String(plan ?? "");
        const price = priceFor(p);
        if (!PLANS[p] || !price) return json({ error: "unknown plan" }, 400);
        const recurring = PLANS[p].months > 0;
        const base = new URL(req.url);
        base.search = "";
        const session = await stripe.checkout.sessions.create({
          mode: recurring ? "subscription" : "payment",
          line_items: [{ price, quantity: 1 }],
          client_reference_id: mac,
          metadata: { mac, plan: p },
          ...(recurring
            ? { subscription_data: { metadata: { mac, plan: p } } }
            : { payment_intent_data: { metadata: { mac, plan: p } }, customer_creation: "always" }),
          automatic_tax: { enabled: Deno.env.get("STRIPE_TAX") === "1" },
          allow_promotion_codes: true,
          locale: "auto",
          success_url: `${base.toString()}?done=1`,
          cancel_url: `${base.toString()}?cancel=1`,
        });
        return json({ url: session.url });
      }

      case "cancel":
      case "resume": {
        const { data: l } = await db.from("licenses").select("*").eq("mac", mac).maybeSingle();
        if (!l?.stripe_subscription_id) return json({ error: "no subscription" }, 400);
        const sub = await stripe.subscriptions.update(l.stripe_subscription_id, {
          cancel_at_period_end: action === "cancel",
        });
        await db.from("licenses").update({
          auto_renew: action === "resume",
          status: action === "cancel" ? "canceled" : "active",
          updated_at: new Date().toISOString(),
        }).eq("mac", mac);
        void sub;
        return json(await status(mac));
      }

      default:
        return json({ error: "unknown action" }, 400);
    }
  } catch (e) {
    console.error(e);
    return json({ error: "server error" }, 500);
  }
});
