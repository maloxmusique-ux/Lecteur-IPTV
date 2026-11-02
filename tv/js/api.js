// Chargement des listes : Xtream Codes et M3U.
var Api = (function () {
  function getJson(url, ms) {
    return withTimeout(fetch(url, { cache: 'no-store' }), ms || 20000).then(function (r) {
      if (!r.ok) throw new Error('HTTP ' + r.status);
      return r.json();
    });
  }
  function getText(url, ms) {
    return withTimeout(fetch(url, { cache: 'no-store' }), ms || 30000).then(function (r) {
      if (!r.ok) throw new Error('HTTP ' + r.status);
      return r.text();
    });
  }
  function withTimeout(p, ms) {
    return new Promise(function (ok, ko) {
      var t = setTimeout(function () { ko(new Error('timeout')); }, ms);
      p.then(function (v) { clearTimeout(t); ok(v); }, function (e) { clearTimeout(t); ko(e); });
    });
  }
  function server(src) {
    var s = (src.server || '').trim().replace(/\/+$/, '');
    if (!/^https?:\/\//i.test(s)) s = 'http://' + s;
    return s;
  }
  function base(src) {
    return server(src) + '/player_api.php?username=' + encodeURIComponent(src.user) +
      '&password=' + encodeURIComponent(src.pass);
  }

  /** Catalogue : { live: [...], movie: [...], groups: {live:[], movie:[]} } */
  function loadXtream(src) {
    var b = base(src);
    return getJson(b).then(function (acc) {
      if (!acc || !acc.user_info || String(acc.user_info.auth) === '0') throw new Error('auth');
      return Promise.all([
        getJson(b + '&action=get_live_categories'),
        getJson(b + '&action=get_live_streams', 60000),
        getJson(b + '&action=get_vod_categories').catch(function () { return []; }),
        getJson(b + '&action=get_vod_streams', 60000).catch(function () { return []; }),
      ]).then(function (r) {
        var lc = {}, vc = {};
        (r[0] || []).forEach(function (c) { lc[c.category_id] = c.category_name; });
        (r[2] || []).forEach(function (c) { vc[c.category_id] = c.category_name; });
        var s = server(src), u = encodeURIComponent(src.user), p = encodeURIComponent(src.pass);
        var live = (r[1] || []).map(function (x) {
          return {
            id: 'l' + x.stream_id, sid: x.stream_id, name: x.name || '', logo: x.stream_icon || '',
            group: lc[x.category_id] || '', epg: x.epg_channel_id || '',
            // HLS : lu par toutes les teles et par le navigateur.
            url: s + '/live/' + u + '/' + p + '/' + x.stream_id + '.m3u8',
            ts: s + '/live/' + u + '/' + p + '/' + x.stream_id + '.ts',
          };
        });
        var movie = (r[3] || []).map(function (x) {
          return {
            id: 'v' + x.stream_id, sid: x.stream_id, name: x.name || '', logo: x.stream_icon || '',
            group: vc[x.category_id] || '',
            url: s + '/movie/' + u + '/' + p + '/' + x.stream_id + '.' + (x.container_extension || 'mp4'),
          };
        });
        return finish(live, movie, catOrder(r[0]), catOrder(r[2]));
      });
    });
  }
  function catOrder(cats) { return (cats || []).map(function (c) { return c.category_name; }); }

  function parseM3u(text) {
    var lines = text.split(/\r?\n/), out = [], cur = null;
    for (var i = 0; i < lines.length; i++) {
      var l = lines[i].trim();
      if (l.indexOf('#EXTINF') === 0) {
        var attr = function (k) { var m = l.match(new RegExp(k + '="([^"]*)"')); return m ? m[1] : ''; };
        var comma = l.lastIndexOf(',');
        cur = { name: comma >= 0 ? l.slice(comma + 1).trim() : '', logo: attr('tvg-logo'), group: attr('group-title'), epg: attr('tvg-id') };
      } else if (l && l[0] !== '#' && cur) {
        cur.url = l;
        cur.id = 'm' + out.length;
        out.push(cur);
        cur = null;
      }
    }
    return out;
  }
  function loadM3u(src) {
    return getText(src.url, 60000).then(function (text) {
      if (text.indexOf('#EXTM3U') < 0 && text.indexOf('#EXTINF') < 0) throw new Error('format');
      var all = parseM3u(text);
      var isVod = function (c) { return /\.(mp4|mkv|avi|mov)(\?|$)/i.test(c.url) || /\/movie\//.test(c.url); };
      return finish(all.filter(function (c) { return !isVod(c); }), all.filter(isVod), null, null);
    });
  }

  function finish(live, movie, liveOrder, movieOrder) {
    function groups(list, order) {
      var seen = {}, gs = [];
      (order || []).forEach(function (g) { if (!seen[g]) { seen[g] = 1; gs.push(g); } });
      list.forEach(function (c) { if (c.group && !seen[c.group]) { seen[c.group] = 1; gs.push(c.group); } });
      // Seulement les categories non vides.
      var used = {};
      list.forEach(function (c) { used[c.group] = 1; });
      return gs.filter(function (g) { return used[g]; });
    }
    return { live: live, movie: movie, groups: { live: groups(live, liveOrder), movie: groups(movie, movieOrder) } };
  }

  /** Emission en cours et suivante (Xtream). */
  function nowNext(src, ch) {
    if (!src || src.kind !== 'xtream' || !ch.sid) return Promise.resolve([]);
    function map(r) {
      return ((r && r.epg_listings) || []).map(function (e) {
        return { title: b64(e.title), start: Number(e.start_timestamp) * 1000, stop: Number(e.stop_timestamp) * 1000 };
      });
    }
    function upcoming(list) {
      var now = Date.now();
      return list.filter(function (e) { return e.stop > now; }).sort(function (a, b) { return a.start - b.start; }).slice(0, 2);
    }
    return getJson(base(src) + '&action=get_short_epg&stream_id=' + ch.sid + '&limit=2', 8000).then(function (r) {
      var list = upcoming(map(r));
      if (list.length) return list;
      // Certains serveurs ne repondent qu'a la table complete.
      return getJson(base(src) + '&action=get_simple_data_table&stream_id=' + ch.sid, 10000).then(function (r2) {
        return upcoming(map(r2));
      });
    }).catch(function () { return []; });
  }
  function b64(s) {
    try { return decodeURIComponent(escape(atob(s || ''))); } catch (e) { return s || ''; }
  }

  function load(src) { return src.kind === 'xtream' ? loadXtream(src) : loadM3u(src); }
  return { load: load, nowNext: nowNext, parseM3u: parseM3u };
})();
