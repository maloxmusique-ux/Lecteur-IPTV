// Portail administrateur : codes cadeaux, activation par adresse MAC,
// liste des appareils. Protege par le mot de passe ADMIN_PASSWORD.
import { cors, db, grantAccess, json, sha256 } from "../_shared/common.ts";

const MAC = /^[0-9A-F]{2}(:[0-9A-F]{2}){5}$/;
// Sans 0/O, 1/I/L : faciles a dicter et a taper avec une telecommande.
const ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";

function newCode(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(8));
  const chars = Array.from(bytes, (b) => ALPHABET[b % ALPHABET.length]).join("");
  return `CANALIX${chars}`;
}

/** Affichage lisible : CANALIX-ABCD-EFGH. */
function pretty(code: string): string {
  return `${code.slice(0, 7)}-${code.slice(7, 11)}-${code.slice(11)}`;
}

async function checkPassword(given: string): Promise<boolean> {
  const expected = Deno.env.get("ADMIN_PASSWORD") ?? "";
  if (expected.length < 8) return false;
  // Comparaison des empreintes (temps constant sur la longueur).
  return (await sha256(given)) === (await sha256(expected));
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: { ...cors, "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-admin-password" },
    });
  }
  const pass = req.headers.get("x-admin-password") ?? "";
  if (!(await checkPassword(pass))) {
    await new Promise((r) => setTimeout(r, 800)); // freine les essais au hasard
    return json({ error: "unauthorized" }, 401);
  }

  try {
    const body = await req.json().catch(() => ({}));
    const action = String(body.action ?? "");

    switch (action) {
      case "login":
        return json({ ok: true });

      case "stats": {
        const { count: devices } = await db.from("devices").select("*", { count: "exact", head: true });
        const { data: lic } = await db.from("licenses").select("status, expires_at, source");
        const now = Date.now();
        const active = (lic ?? []).filter((l) =>
          l.status !== "expired" && (l.expires_at === null || new Date(l.expires_at).getTime() > now)
        );
        const { data: pays } = await db.from("payments").select("amount_cents, created_at");
        const month = new Date();
        month.setDate(1);
        month.setHours(0, 0, 0, 0);
        const total = (pays ?? []).reduce((a, p) => a + p.amount_cents, 0);
        const thisMonth = (pays ?? []).filter((p) => new Date(p.created_at) >= month)
          .reduce((a, p) => a + p.amount_cents, 0);
        return json({
          devices: devices ?? 0,
          active: active.length,
          paying: active.filter((l) => l.source === "stripe").length,
          gifted: active.filter((l) => l.source === "gift").length,
          revenueTotal: total,
          revenueMonth: thisMonth,
        });
      }

      case "createCodes": {
        const months = Number(body.months);
        if (![0, 1, 3, 6, 12].includes(months)) return json({ error: "bad duration" }, 400);
        const count = Math.min(50, Math.max(1, Number(body.count ?? 1)));
        const maxUses = Math.min(1000, Math.max(1, Number(body.maxUses ?? 1)));
        const note = String(body.note ?? "").slice(0, 200) || null;
        const rows = Array.from({ length: count }, () => ({ code: newCode(), months, max_uses: maxUses, note }));
        const { error } = await db.from("promo_codes").insert(rows);
        if (error) throw error;
        return json({ codes: rows.map((r) => pretty(r.code)) });
      }

      case "listCodes": {
        const { data } = await db.from("promo_codes").select("*").order("created_at", { ascending: false }).limit(300);
        return json({ codes: (data ?? []).map((c) => ({ ...c, pretty: pretty(c.code) })) });
      }

      case "disableCode": {
        const code = String(body.code ?? "").toUpperCase().replace(/[^A-Z0-9]/g, "");
        await db.from("promo_codes").update({ disabled: true }).eq("code", code);
        return json({ ok: true });
      }

      case "grant": {
        const mac = String(body.mac ?? "").toUpperCase().trim();
        if (!MAC.test(mac)) return json({ error: "Adresse MAC invalide" }, 400);
        const { data: d } = await db.from("devices").select("mac").eq("mac", mac).maybeSingle();
        if (!d) return json({ error: "Appareil inconnu : ouvre d'abord l'app sur l'appareil, connecté à Internet." }, 404);
        const months = Number(body.months);
        if (![0, 1, 3, 6, 12].includes(months)) return json({ error: "bad duration" }, 400);
        const err = await grantAccess(mac, months, String(body.note ?? "") || "Activé par le portail");
        if (err === "already_subscribed") return json({ error: "Cet appareil a un abonnement payant actif." }, 400);
        if (err === "already_lifetime") return json({ error: "Cet appareil a déjà un accès à vie." }, 400);
        return json({ ok: true });
      }

      case "revoke": {
        const mac = String(body.mac ?? "").toUpperCase().trim();
        await db.from("licenses").update({ status: "expired", auto_renew: false, expires_at: new Date().toISOString() })
          .eq("mac", mac).eq("source", "gift");
        return json({ ok: true });
      }

      case "devices": {
        const q = String(body.search ?? "").toUpperCase().trim();
        let query = db.from("dashboard").select("*").limit(100);
        if (q) query = query.ilike("mac", `%${q}%`);
        const { data } = await query;
        return json({ devices: data ?? [] });
      }

      default:
        return json({ error: "unknown action" }, 400);
    }
  } catch (e) {
    console.error(e);
    return json({ error: "server error" }, 500);
  }
});
