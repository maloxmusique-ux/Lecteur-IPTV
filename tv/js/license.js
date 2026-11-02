// Licence par tele : meme serveur que les autres versions de Canalix.
var License = (function () {
  var cfg = window.CANALIX_CONFIG || {};
  var testMode = !cfg.licenseApi;
  var info = Store.get('license', null);

  function rand(n) {
    var a = new Uint8Array(n);
    (window.crypto || window.msCrypto).getRandomValues(a);
    return a;
  }
  function hex(b) { return ('0' + b.toString(16)).slice(-2).toUpperCase(); }

  /** Adresse MAC : la vraie sur Samsung, sinon une adresse generee une fois. */
  function identity() {
    var id = Store.get('device', null);
    if (id && id.mac && id.secret) return id;
    var mac = null;
    try {
      if (window.webapis && webapis.network && webapis.network.getMac) {
        mac = String(webapis.network.getMac()).toUpperCase();
      }
    } catch (e) {}
    if (!mac || !/^([0-9A-F]{2}:){5}[0-9A-F]{2}$/.test(mac)) {
      var b = rand(6);
      b[0] = (b[0] & 0xfc) | 0x02; // adresse locale, jamais celle d'un materiel
      mac = Array.prototype.map.call(b, hex).join(':');
    }
    var secret = btoa(String.fromCharCode.apply(null, rand(24))).replace(/[+/=]/g, 'x');
    id = { mac: mac, secret: secret };
    Store.set('device', id);
    return id;
  }

  function call(action, extra) {
    if (testMode) return new Promise(function (ok) { ok(testCall(action, extra || {})); });
    var id = identity();
    var body = Object.assign({ action: action, device: id.mac, secret: id.secret, platform: Platform.name() }, extra || {});
    var headers = { 'Content-Type': 'application/json' };
    if (cfg.licenseKey) { headers.Authorization = 'Bearer ' + cfg.licenseKey; headers.apikey = cfg.licenseKey; }
    return fetch(cfg.licenseApi, { method: 'POST', headers: headers, body: JSON.stringify(body) })
      .then(function (r) { return r.json().then(function (j) { if (!r.ok) throw new Error(j.error || r.status); return j; }); });
  }

  // Mode test (sans serveur) : essai local et paiements simules.
  function testCall(action, extra) {
    var s = Store.get('license_test', null);
    var now = Date.now(), day = 864e5;
    if (!s) s = { trialEndsAt: new Date(now + (cfg.trialDays || 7) * day).toISOString() };
    if (action === 'pay') {
      var months = { monthly: 1, quarterly: 3, semiannual: 6, yearly: 12, lifetime: 0 }[extra.plan];
      var d = new Date(); d.setMonth(d.getMonth() + months);
      s.plan = extra.plan; s.expiresAt = months ? d.toISOString() : null; s.autoRenew = months > 0;
    } else if (action === 'cancel') { s.autoRenew = false; }
    else if (action === 'resume') { if (s.plan) s.autoRenew = true; }
    else if (action === 'redeem') {
      var code = String(extra.code || '').toUpperCase().replace(/[^A-Z0-9]/g, '');
      var m = { TEST1M: 1, TEST12M: 12, TESTVIE: 0 }[code];
      if (m === undefined) throw new Error('invalid_code');
      var e = new Date(); e.setMonth(e.getMonth() + m);
      s.plan = m === 0 ? 'lifetime' : (m === 1 ? 'monthly' : 'yearly'); s.expiresAt = m ? e.toISOString() : null; s.autoRenew = false; s.source = 'gift';
    } else if (action === 'checkout') {
      return { url: 'test://' + extra.plan };
    }
    Store.set('license_test', s);
    var active = s.plan && (!s.expiresAt || new Date(s.expiresAt) > new Date());
    return {
      status: active ? 'active' : (new Date(s.trialEndsAt) > new Date() && !s.plan ? 'trial' : 'expired'),
      trialEndsAt: s.trialEndsAt, plan: s.plan || null, expiresAt: s.expiresAt || null,
      autoRenew: !!s.autoRenew, source: s.source || 'test',
    };
  }

  function set(j) { info = j; Store.set('license', j); return j; }

  return {
    testMode: testMode,
    mac: function () { return identity().mac; },
    info: function () { return info; },
    canPlay: function () { return !info || info.status !== 'expired'; },
    trialDaysLeft: function () {
      if (!info) return cfg.trialDays || 7;
      return Math.max(0, Math.ceil((new Date(info.trialEndsAt) - Date.now()) / 864e5));
    },
    refresh: function () {
      return call('status').then(set).catch(function () {
        // Hors ligne : on garde le dernier etat connu (fin d'essai recalculee).
        if (info && info.status === 'trial' && new Date(info.trialEndsAt) < new Date()) info.status = 'expired';
        if (info && info.status === 'active' && info.expiresAt && new Date(info.expiresAt) < new Date() - 3 * 864e5) info.status = 'expired';
        return info;
      });
    },
    checkout: function (plan) { return call('checkout', { plan: plan }); },
    testPay: function (plan) { return Promise.resolve(set(testCall('pay', { plan: plan }))); },
    cancel: function () { return call('cancel').then(set); },
    resume: function () { return call('resume').then(set); },
    redeem: function (code) { return call('redeem', { code: code }).then(set); },
  };
})();
