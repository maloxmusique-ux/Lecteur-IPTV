// Stockage local, toujours protege (certaines teles refusent ou le vident).
var Store = {
  get: function (k, d) {
    try { var v = localStorage.getItem('cx_' + k); return v === null ? d : JSON.parse(v); } catch (e) { return d; }
  },
  set: function (k, v) {
    try { localStorage.setItem('cx_' + k, JSON.stringify(v)); return true; } catch (e) { return false; }
  },
  del: function (k) { try { localStorage.removeItem('cx_' + k); } catch (e) {} },
};
var Platform = {
  tizen: typeof window.tizen !== 'undefined',
  webos: typeof window.webOS !== 'undefined' || /web0s|webos/i.test(navigator.userAgent),
  name: function () { return this.tizen ? 'tizen' : (this.webos ? 'webos' : 'web'); },
};
