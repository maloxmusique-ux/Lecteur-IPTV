// Enregistreur maison : la tele envoie ses enregistrements a un appareil
// Canalix toujours allume (boite Android TV, ordinateur...) du meme reseau.
// La tele peut etre eteinte : c'est l'enregistreur qui enregistre.
var Home = (function () {
  var PORT = 8765;

  function get() { return Store.get('home', null); }
  function paired() { var h = get(); return !!(h && h.host && h.code); }

  function req(method, url, body, code, timeout) {
    return new Promise(function (resolve, reject) {
      var x = new XMLHttpRequest();
      x.open(method, url, true);
      x.timeout = timeout || 8000;
      if (code) x.setRequestHeader('x-canalix-key', code);
      if (body) x.setRequestHeader('content-type', 'application/json');
      x.onload = function () {
        if (x.status !== 200) return reject(new Error(String(x.status)));
        try { resolve(JSON.parse(x.responseText)); } catch (e) { reject(e); }
      };
      x.onerror = x.ontimeout = function () { reject(new Error('net')); };
      x.send(body ? JSON.stringify(body) : null);
    });
  }

  function base(h) { return 'http://' + h.host + ':' + PORT; }
  function call(path, body) {
    var h = get();
    if (!h) return Promise.reject(new Error('none'));
    return req(body ? 'POST' : 'GET', base(h) + path, body, h.code);
  }

  /** Identifiant stable de la liste de la tele (sans mot de passe). */
  function srcId(src) {
    var s = src ? (src.server || src.url || '') + '|' + (src.user || '') : '';
    var h = 0;
    for (var i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) | 0;
    return 'tv' + (h >>> 0).toString(36);
  }

  function chJson(c) {
    var j = { i: c.id, n: c.name, u: c.url, t: 0 };
    if (c.logo) j.l = c.logo;
    if (c.group) j.g = c.group;
    if (c.epg) j.e = c.epg;
    return j;
  }

  /** Adresse IP de la tele (Samsung), pour chercher sur le bon reseau. */
  function myIp() {
    try { if (window.webapis && webapis.network && webapis.network.getIp) return webapis.network.getIp() || ''; } catch (e) {}
    return '';
  }

  /** Cherche les enregistreurs Canalix sur le reseau local. */
  function scan(onFound) {
    var ip = myIp(), nets = [];
    if (/^\d+\.\d+\.\d+\.\d+$/.test(ip)) nets.push(ip.replace(/\.\d+$/, ''));
    ['192.168.1', '192.168.0', '10.0.0', '192.168.2', '10.0.1', '192.168.100', '192.168.10', '10.1.1']
      .forEach(function (n) { if (nets.indexOf(n) < 0) nets.push(n); });
    var found = [];
    function probe(host) {
      return req('GET', 'http://' + host + ':' + PORT + '/api/ping', null, null, 1500).then(function (j) {
        if (j && j.app === 'canalix') { var f = { host: host, name: j.name || host }; found.push(f); if (onFound) onFound(f); }
      }).catch(function () {});
    }
    // Un reseau a la fois (48 essais en parallele) ; on s'arrete des qu'on trouve.
    function scanNet(n) {
      var i = 1;
      return new Promise(function (resolve) {
        var running = 0;
        function next() {
          while (running < 48 && i < 255) {
            running++;
            probe(n + '.' + (i++)).then(function () { running--; next(); });
          }
          if (running === 0 && i >= 255) resolve();
        }
        next();
      });
    }
    var k = 0;
    function loop() {
      if (found.length || k >= nets.length) return Promise.resolve(found);
      return scanNet(nets[k++]).then(loop);
    }
    return loop();
  }

  function pair(host, name, code) {
    return req('GET', 'http://' + host + ':' + PORT + '/api/list', null, code, 8000).then(function (j) {
      Store.set('home', { host: host, name: j.name || name || host, code: code });
      return true;
    });
  }

  return {
    get: get,
    paired: paired,
    scan: scan,
    pair: pair,
    forget: function () { Store.del('home'); },
    list: function () { return call('/api/list'); },
    schedule: function (src, c, p) {
      return call('/api/schedule', { src: { id: srcId(src), name: 'TV' }, ch: chJson(c), p: { start: p.start, stop: p.stop, title: p.title || '' } });
    },
    now: function (src, c, minutes, title) {
      var b = { src: { id: srcId(src), name: 'TV' }, ch: chJson(c), minutes: minutes };
      if (title) b.title = title;
      return call('/api/now', b);
    },
    stop: function (id) { return call('/api/stop', { id: id }); },
    del: function (id) { return call('/api/delete', { id: id }); },
    fileUrl: function (r) {
      var h = get();
      return base(h) + '/files/' + encodeURIComponent(r.id) + '.' + (r.ext || 'ts') + '?k=' + encodeURIComponent(h.code);
    },
  };
})();
