// Canalix pour televiseurs (Samsung Tizen, LG webOS).
(function () {
  var cfg = window.CANALIX_CONFIG || {};
  var $ = function (id) { return document.getElementById(id); };
  var ROW = 76, GROW = 66, VISIBLE = 11;

  var S = {
    screen: null,
    source: Store.get('source', null),
    catalog: null,
    section: 'live',
    group: -1,          // -1 = Tout
    groupFocus: 0,      // index dans la liste (0 = Tout)
    item: 0,
    zone: 'items',      // tabs | groups | items
    items: [],
    playing: null,
    epg: {},
  };
  LANG = Store.get('lang', (navigator.language || 'fr').slice(0, 2) === 'en' ? 'en' : 'fr');

  // ----------------------------------------------------------- Ecrans
  function show(id) {
    ['legal', 'setup', 'home', 'settings', 'paywall', 'homerec', 'recs', 'recdlg'].forEach(function (s) {
      $(s).classList.toggle('hidden', s !== id);
    });
    S.screen = id;
    // La video ne reste visible que sur l'accueil.
    $('stage').classList.toggle('hidden', id !== 'home' || !S.playing);
    if (id === 'home' && S.playing && !Player.isFull()) {
      setTimeout(function () { Player.place(previewRect()); }, 0);
    }
    if (id !== 'home') hideOsd();
    if (id !== 'home') {
      setTimeout(function () { SpatialNav.first($(id)); }, 0);
    }
  }

  function toast(text, ms) {
    var el = $('toast');
    el.textContent = text;
    el.classList.remove('hidden');
    clearTimeout(toast.t);
    toast.t = setTimeout(function () { el.classList.add('hidden'); }, ms || 2500);
  }

  // ----------------------------------------------------------- Demarrage
  function start() {
    applyI18n();
    tickClock();
    setInterval(tickClock, 15000);
    License.refresh();
    setInterval(License.refresh, 30 * 60000);
    if (!Store.get('legal', false)) return show('legal');
    if (!S.source) return show('setup');
    loadCatalog();
  }

  function tickClock() {
    var d = new Date();
    $('clock').textContent = ('0' + d.getHours()).slice(-2) + ':' + ('0' + d.getMinutes()).slice(-2);
  }

  $('legal-ok').onclick = function () {
    Store.set('legal', true);
    S.source ? loadCatalog() : show('setup');
  };

  // ----------------------------------------------------------- Source
  var kind = 'xtream';
  Array.prototype.forEach.call(document.querySelectorAll('#setup-tabs .tab'), function (b) {
    b.onclick = function () {
      kind = b.getAttribute('data-kind');
      Array.prototype.forEach.call(document.querySelectorAll('#setup-tabs .tab'), function (x) { x.classList.toggle('active', x === b); });
      $('form-xtream').classList.toggle('hidden', kind !== 'xtream');
      $('form-m3u').classList.toggle('hidden', kind !== 'm3u');
    };
  });
  $('setup-save').onclick = function () {
    var src = kind === 'xtream'
      ? { kind: 'xtream', server: $('x-server').value.trim(), user: $('x-user').value.trim(), pass: $('x-pass').value }
      : { kind: 'm3u', url: $('m-url').value.trim() };
    if (kind === 'xtream' && (!src.server || !src.user)) return ($('setup-error').textContent = t('setup.failed'));
    if (kind === 'm3u' && !src.url) return ($('setup-error').textContent = t('setup.failed'));
    trySource(src);
  };
  $('setup-demo').onclick = function () { trySource({ kind: 'm3u', url: cfg.pages + '/demo.m3u' }); };

  function trySource(src) {
    $('setup-error').textContent = t('setup.loading');
    Api.load(src).then(function (cat) {
      S.source = src;
      Store.set('source', src);
      $('setup-error').textContent = '';
      useCatalog(cat);
    }).catch(function () { $('setup-error').textContent = t('setup.failed'); });
  }

  function loadCatalog() {
    show('home');
    $('count').textContent = t('setup.loading');
    Api.load(S.source).then(useCatalog).catch(function () {
      toast(t('setup.failed'), 5000);
      show('setup');
    });
  }

  function useCatalog(cat) {
    S.catalog = cat;
    S.group = -1; S.groupFocus = 0; S.item = 0; S.zone = 'items';
    show('home');
    renderTabs();
    renderGroups();
    filter();
  }

  // ----------------------------------------------------------- Accueil
  function renderTabs() {
    Array.prototype.forEach.call(document.querySelectorAll('#sections .tab'), function (b) {
      var s = b.getAttribute('data-section');
      b.classList.toggle('active', s === S.section);
      b.classList.toggle('focused', S.zone === 'tabs' && s === S.tabFocus);
    });
  }

  function groupsList() { return S.catalog ? S.catalog.groups[S.section] : []; }

  function renderGroups() {
    var gs = groupsList(), box = $('groups');
    var start = Math.max(0, Math.min(S.groupFocus - 5, gs.length + 1 - 12));
    var html = '';
    for (var i = start; i < Math.min(gs.length + 1, start + 12); i++) {
      var name = i === 0 ? t('home.all') : gs[i - 1];
      var cls = 'item' + ((i - 1) === S.group ? ' sel' : '') + (S.zone === 'groups' && i === S.groupFocus ? ' focused' : '');
      html += '<div class="' + cls + '"><span class="name">' + esc(name) + '</span></div>';
    }
    box.innerHTML = html;
  }

  function filter() {
    var list = S.catalog ? S.catalog[S.section] : [];
    var g = S.group >= 0 ? groupsList()[S.group] : null;
    S.items = g === null ? list : list.filter(function (c) { return c.group === g; });
    S.item = Math.min(S.item, Math.max(0, S.items.length - 1));
    $('count').textContent = t('home.count', [S.items.length]);
    renderItems();
  }

  function renderItems() {
    var list = S.items, box = $('items');
    var start = Math.max(0, Math.min(S.item - 4, list.length - VISIBLE));
    var html = '';
    for (var i = start; i < Math.min(list.length, start + VISIBLE); i++) {
      var c = list[i];
      var cls = 'item' + (S.playing && S.playing.id === c.id ? ' playing' : '') +
        (S.zone === 'items' && i === S.item ? ' focused' : '');
      var logo = c.logo
        ? '<img src="' + esc(c.logo) + '" onerror="this.outerHTML=\'<span class=ph>' + esc(initials(c.name)) + '</span>\'">'
        : '<span class="ph">' + esc(initials(c.name)) + '</span>';
      html += '<div class="' + cls + '"><span class="num">' + (i + 1) + '</span>' + logo +
        '<span class="name">' + esc(c.name) + '</span></div>';
    }
    box.innerHTML = html;
  }

  function renderPreviewInfo() {
    var c = S.playing, box = $('preview-info');
    $('preview-hint').classList.toggle('hidden', !!c);
    if (!c) { box.innerHTML = ''; return; }
    var e = S.epg[c.id] || [], now = e[0], next = e[1];
    var html = '<h2>' + esc(c.name) + '</h2>';
    if (now) {
      var p = Math.max(0, Math.min(1, (Date.now() - now.start) / (now.stop - now.start)));
      html += '<div class="now">' + hm(now.start) + ' – ' + hm(now.stop) + '  ' + esc(now.title) + '</div>' +
        '<div class="bar"><i style="width:' + Math.round(p * 100) + '%"></i></div>';
    }
    if (next) html += '<div class="next">' + hm(next.start) + '  ' + esc(next.title) + '</div>';
    box.innerHTML = html;
  }

  function previewRect() { return $('preview-box').getBoundingClientRect(); }

  /** 1er OK : apercu. 2e OK sur la meme chaine : plein ecran. */
  function openItem(c) {
    if (!License.canPlay()) return openPaywall();
    if (S.section === 'movie') { S.playing = c; Player.play(c, null); osd(); return; }
    if (S.playing && S.playing.id === c.id) { Player.fullscreen(true); osd(); return; }
    S.playing = c;
    Player.play(c, previewRect());
    renderItems();
    renderPreviewInfo();
    Api.nowNext(S.source, c).then(function (e) { S.epg[c.id] = e; renderPreviewInfo(); if (!$('osd').classList.contains('hidden')) osd(); });
  }

  function zap(delta) {
    if (!S.items.length) return;
    var i = S.playing ? S.items.indexOf(S.playing) : S.item;
    i = (i + delta + S.items.length) % S.items.length;
    S.item = i;
    var c = S.items[i];
    S.playing = c;
    Player.play(c, Player.isFull() ? null : previewRect());
    renderItems();
    renderPreviewInfo();
    osd();
    Api.nowNext(S.source, c).then(function (e) { S.epg[c.id] = e; renderPreviewInfo(); osd(); });
  }

  // Bandeau d'information en plein ecran.
  function osd() {
    if (!Player.isFull() || !S.playing) return;
    var c = S.playing, e = S.epg[c.id] || [], now = e[0], next = e[1];
    var n = S.items.indexOf(c) + 1;
    $('osd').innerHTML = '<h2><span class="num">' + (n || '') + '</span>' + esc(c.name) + '</h2>' +
      (now ? '<div class="now">' + hm(now.start) + ' – ' + hm(now.stop) + '  ' + esc(now.title) + '</div>' : '') +
      (next ? '<div class="next">' + hm(next.start) + '  ' + esc(next.title) + '</div>' : '');
    $('osd').classList.remove('hidden');
    clearTimeout(osd.t);
    osd.t = setTimeout(hideOsd, 5000);
  }
  function hideOsd() { $('osd').classList.add('hidden'); }

  Player.on('state', function (s) {
    if (s === 'reconnecting') toast(t('player.reconnecting'), 1500);
    if (s === 'failed') toast(t('player.failed'), 4000);
  });

  function homeKey(code) {
    // Plein ecran
    if (Player.isFull()) {
      if (Keys.is(code, Keys.BACK)) {
        if (S.section === 'movie') { Player.stop(); S.playing = null; renderPreviewInfo(); }
        else Player.fullscreen(false, previewRect());
        hideOsd();
      } else if (code === Keys.UP || Keys.is(code, Keys.CH_UP)) { if (S.section === 'live') zap(-1); }
      else if (code === Keys.DOWN || Keys.is(code, Keys.CH_DOWN)) { if (S.section === 'live') zap(1); }
      else if (code === Keys.ENTER || Keys.is(code, Keys.INFO)) osd();
      else if (Keys.is(code, Keys.PLAY_PAUSE)) Player.pauseToggle();
      else if (Keys.is(code, Keys.RECORD) && S.section === 'live') openRecord(S.playing);
      return;
    }
    if (Keys.is(code, Keys.RECORD) && S.section === 'live') {
      return openRecord(S.playing || S.items[S.item]);
    }
    if (Keys.is(code, Keys.CH_UP)) return zap(-1);
    if (Keys.is(code, Keys.CH_DOWN)) return zap(1);

    var gs = groupsList();
    if (S.zone === 'tabs') {
      var tabs = ['live', 'movie', 'settings'], ti = tabs.indexOf(S.tabFocus);
      if (code === Keys.LEFT) S.tabFocus = tabs[Math.max(0, ti - 1)];
      else if (code === Keys.RIGHT) S.tabFocus = tabs[Math.min(tabs.length - 1, ti + 1)];
      else if (code === Keys.DOWN || Keys.is(code, Keys.BACK)) S.zone = 'items';
      else if (code === Keys.ENTER) {
        if (S.tabFocus === 'settings') { openSettings(); return; }
        if (S.tabFocus !== S.section) {
          S.section = S.tabFocus; S.group = -1; S.groupFocus = 0; S.item = 0;
          renderGroups(); filter();
        }
        S.zone = 'items';
      }
      renderTabs(); renderGroups(); renderItems();
      return;
    }
    if (S.zone === 'groups') {
      if (code === Keys.UP) { if (S.groupFocus === 0) { S.zone = 'tabs'; S.tabFocus = S.section; } else S.groupFocus--; }
      else if (code === Keys.DOWN) S.groupFocus = Math.min(gs.length, S.groupFocus + 1);
      else if (code === Keys.RIGHT || code === Keys.ENTER) {
        S.group = S.groupFocus - 1; S.item = 0; S.zone = 'items'; filter();
      } else if (Keys.is(code, Keys.BACK)) return askExit();
      renderTabs(); renderGroups(); renderItems();
      return;
    }
    // Liste des chaines
    if (code === Keys.UP) { if (S.item === 0) { S.zone = 'tabs'; S.tabFocus = S.section; } else S.item--; }
    else if (code === Keys.DOWN) S.item = Math.min(S.items.length - 1, S.item + 1);
    else if (code === Keys.LEFT || Keys.is(code, Keys.BACK)) { S.zone = 'groups'; S.groupFocus = S.group + 1; }
    else if (code === Keys.ENTER && S.items[S.item]) { openItem(S.items[S.item]); }
    renderTabs(); renderGroups(); renderItems();
  }

  // ----------------------------------------------------------- Reglages
  function openSettings() {
    var info = License.info() || {};
    var items = [
      { k: 'source', title: t('set.source'), sub: S.source ? (S.source.server || S.source.url) : '' },
      { k: 'sub', title: t('set.sub'), sub: subText(info) },
      { k: 'lang', title: t('set.lang'), sub: LANG === 'fr' ? 'Français' : 'English' },
      { k: 'recs', title: t('recs.title'), sub: Home.paired() ? t('home.linked', [Home.get().name]) : t('home.notLinked') },
      { k: 'homerec', title: t('home.title'), sub: Home.paired() ? t('home.linked', [Home.get().name]) : t('home.why') },
      { k: 'reload', title: t('set.reload'), sub: t('set.reloadSub') },
      { k: 'help', title: t('set.help'), sub: cfg.pages + '/aide.html' },
    ];
    if (info.status === 'active' && info.autoRenew && info.source !== 'gift') items.splice(2, 0, { k: 'cancel', title: t('sub.cancel'), sub: '', danger: true });
    if (info.status === 'active' && !info.autoRenew && info.plan && info.plan !== 'lifetime' && info.source !== 'gift') items.splice(2, 0, { k: 'resume', title: t('sub.resume'), sub: '' });
    $('settings-menu').innerHTML = items.map(function (i) {
      return '<div class="item focusable' + (i.danger ? ' btn danger' : '') + '" data-k="' + i.k + '"><span class="name">' +
        esc(i.title) + '<span class="sub">' + esc(i.sub) + '</span></span></div>';
    }).join('') + '<p class="muted small">' + esc(t('set.mac', [License.mac()])) + '</p>';
    Array.prototype.forEach.call($('settings-menu').querySelectorAll('.item'), function (el) {
      el.onclick = function () { settingsAction(el.getAttribute('data-k')); };
    });
    Player.suspend();
    show('settings');
  }

  function subText(i) {
    if (!i || !i.status) return '';
    if (i.status === 'trial') return t('sub.trial', [License.trialDaysLeft()]);
    if (i.status === 'expired') return t('sub.expired');
    if (i.plan === 'lifetime') return t('sub.lifetime');
    var plan = t('plan.' + i.plan);
    var when = i.expiresAt ? new Date(i.expiresAt).toLocaleDateString(LANG) : '';
    if (i.source === 'gift') return t('sub.gift') + ' · ' + t('sub.until', [when]);
    return t('sub.active', [plan]) + ' · ' + (i.autoRenew ? t('sub.next', [when]) : t('sub.cancelled', [when]));
  }

  function settingsAction(k) {
    if (k === 'source') { Player.stop(); S.playing = null; show('setup'); }
    else if (k === 'sub') openPaywall();
    else if (k === 'lang') { LANG = LANG === 'fr' ? 'en' : 'fr'; Store.set('lang', LANG); applyI18n(); openSettings(); }
    else if (k === 'reload') location.reload();
    else if (k === 'homerec') openHomeRec();
    else if (k === 'recs') Home.paired() ? openRecs() : openHomeRec();
    else if (k === 'help') toast(cfg.pages + '/aide.html', 6000);
    else if (k === 'cancel') License.cancel().then(function () { toast(subText(License.info()), 5000); openSettings(); });
    else if (k === 'resume') License.resume().then(function () { openSettings(); });
  }

  function backHome() {
    show('home');
    // Une lecture d'enregistrement a pu remplacer la chaine en apercu.
    var cur = Player.current();
    if (S.playing && (!cur || cur.id !== S.playing.id)) Player.play(S.playing, previewRect());
    else Player.restore();
    renderTabs(); renderItems();
  }

  // ----------------------------------------------------------- Enregistreur maison
  function menu(box, items) {
    box.innerHTML = items.map(function (i) {
      return '<div class="item focusable' + (i.cls ? ' ' + i.cls : '') + '" data-k="' + esc(i.k) + '"><span class="name">' +
        esc(i.title) + (i.sub ? '<span class="sub">' + esc(i.sub) + '</span>' : '') + '</span></div>';
    }).join('');
    Array.prototype.forEach.call(box.querySelectorAll('.item'), function (el, n) {
      el.onclick = function () { items[n].run(); };
    });
  }

  function openHomeRec(found, scanning) {
    Player.suspend();
    var body = $('homerec-body'), h = Home.get();
    var html = '<p class="lead">' + esc(t('home.intro')) + '</p>';
    if (h) {
      html += '<p>' + esc(t('home.linked', [h.name])) + ' <span class="muted small">(' + esc(h.host) + ')</span></p>';
    }
    html += '<div class="menu" id="homerec-menu"></div>';
    html += '<div id="homerec-code" class="hidden"><p id="homerec-for"></p><div class="row">' +
      '<input class="focusable codebox" id="homerec-input" maxlength="6" inputmode="numeric" placeholder="000000">' +
      '<button class="btn primary focusable" id="homerec-ok">' + esc(t('home.connect')) + '</button></div>' +
      '<p class="muted small">' + esc(t('home.codeWhere')) + '</p></div>';
    body.innerHTML = html;
    var items = [];
    if (h) {
      items.push({ k: 'recs', title: t('recs.title'), run: openRecs });
      items.push({ k: 'forget', title: t('home.forget'), cls: 'btn danger', run: function () { Home.forget(); openHomeRec(); } });
    }
    items.push({ k: 'scan', title: scanning ? t('home.searching') : t('home.search'), sub: t('home.searchSub'), run: function () {
      if (scanning) return;
      openHomeRec([], true);
      Home.scan().then(function (list) {
        if (S.screen !== 'homerec') return;
        openHomeRec(list, false);
        if (!list.length) toast(t('home.none'), 6000);
      });
    } });
    (found || []).forEach(function (f) {
      items.push({ k: 'f' + f.host, title: f.name, sub: f.host, run: function () { askCode(f.host, f.name); } });
    });
    items.push({ k: 'manual', title: t('home.manual'), sub: '192.168.1.20', run: function () {
      var ip = (window.prompt && window.prompt(t('home.manual'), '192.168.1.')) || '';
      if (/^\d+\.\d+\.\d+\.\d+$/.test(ip.trim())) askCode(ip.trim(), ip.trim());
    } });
    menu($('homerec-menu'), items);
    show('homerec');
    if (found && found.length) SpatialNav.focus($('homerec-menu').querySelectorAll('.item')[h ? 3 : 1]);
  }

  function askCode(host, name) {
    $('homerec-code').classList.remove('hidden');
    $('homerec-for').textContent = t('home.codeFor', [name]);
    $('homerec-ok').onclick = function () {
      var code = $('homerec-input').value.replace(/\D/g, '');
      if (code.length !== 6) return toast(t('home.badCode'));
      Home.pair(host, name, code).then(function () {
        toast(t('home.linked', [Home.get().name]), 4000);
        openRecs();
      }).catch(function () { toast(t('home.badCode'), 5000); });
    };
    SpatialNav.focus($('homerec-input'));
    $('homerec-input').focus();
  }

  var recsData = null, recsTimer = null;
  function openRecs() {
    Player.suspend();
    show('recs');
    $('recs-info').textContent = t('setup.loading');
    $('recs-list').innerHTML = '';
    loadRecs(true);
    clearInterval(recsTimer);
    recsTimer = setInterval(function () { if (S.screen === 'recs' && !Player.isFull()) loadRecs(false); else if (S.screen !== 'recs') clearInterval(recsTimer); }, 10000);
  }

  function loadRecs(focus) {
    Home.list().then(function (j) { recsData = j; renderRecs(focus); }).catch(function () {
      $('recs-info').textContent = t('home.offline', [(Home.get() || {}).name || '']);
    });
  }

  function gb(b) { return (b / 1073741824).toFixed(b < 10737418240 ? 1 : 0).replace('.', LANG === 'fr' ? ',' : '.') + (LANG === 'fr' ? ' Go' : ' GB'); }
  function size(b) { return b >= 1073741824 ? gb(b) : Math.max(1, Math.round(b / 1048576)) + (LANG === 'fr' ? ' Mo' : ' MB'); }
  function dayTime(ms) { var d = new Date(ms); return d.toLocaleDateString(LANG, { weekday: 'short', day: 'numeric', month: 'short' }) + ' ' + hm(ms); }

  function renderRecs(focus) {
    var j = recsData || { items: [] }, st = j.storage;
    var info = t('home.linked', [j.name || Home.get().name]);
    if (st && st.total > 0) {
      var low = st.free < 2147483648 || st.free / st.total < 0.05;
      info += ' · ' + t('recs.free', [gb(st.free), gb(st.total), Math.floor(st.free / 3221225472)]);
      $('recs-info').innerHTML = esc(info) + '<div class="storage' + (low ? ' low' : '') + '"><i style="width:' + Math.round((1 - st.free / st.total) * 100) + '%"></i></div>';
    } else $('recs-info').textContent = info;
    var order = { recording: 0, scheduled: 1, done: 2, failed: 3, cancelled: 4 };
    var list = (j.items || []).slice().sort(function (a, b) {
      return (order[a.status] - order[b.status]) || (a.status === 'scheduled' ? a.start - b.start : b.start - a.start);
    }).filter(function (r) { return r.status !== 'cancelled'; });
    if (!list.length) { $('recs-list').innerHTML = '<p class="muted">' + esc(t('recs.empty')) + '</p>'; return; }
    var focusedId = SpatialNav.current && SpatialNav.current.getAttribute('data-id');
    $('recs-list').innerHTML = list.slice(0, 40).map(function (r) {
      var st = r.status === 'recording' ? '<span class="rec-dot">●</span>' + t('recs.recording', [hm(r.stop), size(r.bytes)])
        : r.status === 'scheduled' ? t('recs.scheduled', [dayTime(r.start)])
        : r.status === 'done' ? dayTime(r.start) + ' · ' + size(r.bytes)
        : t('recs.failed');
      var act = r.status === 'scheduled' ? t('recs.cancel') : r.status === 'recording' ? t('recs.stop') : t('recs.delete');
      return '<div class="rec-row"><div class="item focusable" data-id="' + esc(r.id) + '" data-a="play"><span class="name">' + esc(r.title) +
        '<span class="sub">' + esc(r.channel) + ' · ' + st + '</span></span></div>' +
        '<button class="btn focusable" data-id="' + esc(r.id) + '" data-a="act">' + esc(act) + '</button></div>';
    }).join('');
    Array.prototype.forEach.call($('recs-list').querySelectorAll('.focusable'), function (el) {
      el.onclick = function () {
        var r = list.filter(function (x) { return x.id === el.getAttribute('data-id'); })[0];
        if (r) recAction(r, el.getAttribute('data-a'));
      };
    });
    var again = focusedId && $('recs-list').querySelector('[data-id="' + focusedId + '"]');
    if (focus || !again) SpatialNav.first($('recs'));
    else SpatialNav.focus(again);
  }

  var confirmAt = 0, confirmId = '';
  function recAction(r, a) {
    if (a === 'play') {
      if (!(r.bytes > 0) || (r.status !== 'done' && r.status !== 'recording')) return toast(t('recs.notYet'));
      Player.play({ id: 'rec_' + r.id, name: r.title, url: Home.fileUrl(r) }, null);
      return;
    }
    // Deuxieme appui pour confirmer.
    if (confirmId !== r.id || Date.now() - confirmAt > 3000) {
      confirmId = r.id; confirmAt = Date.now();
      return toast(t('recs.confirm'), 3000);
    }
    confirmId = '';
    var p = r.status === 'scheduled' || r.status === 'recording' ? Home.stop(r.id) : Home.del(r.id);
    p.then(function () { loadRecs(false); }).catch(function () { toast(t('home.offline', [Home.get().name])); });
  }

  /** Enregistrer la chaine : emission en cours, suivante, ou duree fixe. */
  function openRecord(c) {
    if (!c) return;
    if (!Home.paired()) {
      Player.suspend();
      $('recdlg-title').textContent = t('rec.title', [c.name]);
      $('recdlg-sub').textContent = t('home.needLink');
      menu($('recdlg-menu'), [
        { k: 'link', title: t('home.title'), sub: t('home.why'), run: openHomeRec },
        { k: 'back', title: t('common.back'), run: backHome },
      ]);
      return show('recdlg');
    }
    Player.suspend();
    function sendNow(min, title) {
      Home.now(S.source, c, min, title).then(function () { toast(t('rec.sent', [Home.get().name]), 4000); backHome(); })
        .catch(function () { toast(t('home.offline', [Home.get().name]), 5000); });
    }
    function build(e) {
      var now = e[0], next = e[1], items = [], n = Date.now();
      if (now && now.stop > n) {
        items.push({ k: 'cur', title: t('rec.current', [now.title]), sub: t('rec.until', [hm(now.stop)]), run: function () {
          Home.schedule(S.source, c, now).then(function () { toast(t('rec.sent', [Home.get().name]), 4000); backHome(); })
            .catch(function () { toast(t('home.offline', [Home.get().name]), 5000); });
        } });
      }
      if (next && next.start > n) {
        items.push({ k: 'next', title: t('rec.next', [next.title]), sub: hm(next.start) + ' – ' + hm(next.stop), run: function () {
          Home.schedule(S.source, c, next).then(function () { toast(t('rec.planned', [Home.get().name]), 4000); backHome(); })
            .catch(function () { toast(t('home.offline', [Home.get().name]), 5000); });
        } });
      }
      [[30, '30 min'], [60, '1 h'], [120, '2 h'], [240, '4 h']].forEach(function (d) {
        items.push({ k: 'd' + d[0], title: t('rec.for', [d[1]]), run: function () { sendNow(d[0]); } });
      });
      items.push({ k: 'back', title: t('common.back'), run: backHome });
      $('recdlg-title').textContent = t('rec.title', [c.name]);
      $('recdlg-sub').textContent = t('rec.where', [Home.get().name]);
      menu($('recdlg-menu'), items);
      show('recdlg');
    }
    if (S.epg[c.id]) build(S.epg[c.id]);
    else Api.nowNext(S.source, c).then(function (e) { S.epg[c.id] = e; build(e); });
  }

  // ----------------------------------------------------------- Forfaits
  var PLANS = [['monthly', 299, 1], ['quarterly', 799, 3], ['semiannual', 1299, 6], ['yearly', 1999, 12], ['lifetime', 3999, 0]];
  var pollTimer = null;

  function money(c) { return (c / 100).toFixed(2).replace('.', ',') + ' $'; }

  function openPaywall() {
    Player.suspend();
    var i = License.info() || {};
    $('pay-title').textContent = i.status === 'expired' ? (i.plan ? t('pay.subOver') : t('pay.trialOver'))
      : i.status === 'trial' ? t('pay.trialLeft', [License.trialDaysLeft()]) : t('pay.choose');
    $('plans').innerHTML = PLANS.map(function (p) {
      var per = p[2] ? money(Math.round(p[1] / p[2])) + ' ' + t('plan.per') : t('plan.once');
      return '<div class="plan focusable" data-plan="' + p[0] + '">' + (p[0] === 'yearly' ? '<span class="b">' + t('plan.best') + '</span>' : '') +
        '<div>' + t('plan.' + p[0]) + '</div><div class="p">' + money(p[1]) + '</div><div class="muted small">' + per + '</div></div>';
    }).join('');
    $('pay-terms').textContent = t('terms.renew') + ' ' + t('terms.once');
    $('pay-qr').classList.add('hidden');
    $('pay-mac').textContent = t('set.mac', [License.mac()]);
    Array.prototype.forEach.call($('plans').querySelectorAll('.plan'), function (el) {
      el.onclick = function () { buy(el.getAttribute('data-plan')); };
    });
    show('paywall');
  }

  function buy(plan) {
    if (License.testMode) {
      License.testPay(plan).then(function () { toast(t('pay.testDone')); leavePaywall(); });
      return;
    }
    License.checkout(plan).then(function (s) {
      var label = t('plan.' + plan) + ' (' + money(PLANS.filter(function (p) { return p[0] === plan; })[0][1]) + ')';
      var qr = qrcode(0, 'M'); qr.addData(s.url); qr.make();
      $('pay-qr').innerHTML = '<div class="code">' + qr.createImgTag(6, 0) + '</div><div><p>' + esc(t('pay.scan', [label])) +
        '</p><p class="muted">' + esc(t('pay.wait')) + '</p></div>';
      $('pay-qr').classList.remove('hidden');
      clearInterval(pollTimer);
      pollTimer = setInterval(function () {
        License.refresh().then(function (i) { if (i && i.status === 'active') { clearInterval(pollTimer); leavePaywall(); } });
      }, 4000);
    }).catch(function () { toast(t('setup.failed')); });
  }

  function leavePaywall() {
    clearInterval(pollTimer);
    show('home');
    Player.restore();
    renderTabs(); renderGroups(); renderItems();
  }

  $('pay-back').onclick = leavePaywall;
  $('pay-refresh').onclick = function () {
    License.refresh().then(function (i) { if (i && i.status !== 'expired') leavePaywall(); });
  };
  $('pay-code').onclick = function () {
    // Champ de saisie : le clavier de la tele s'ouvre.
    if (!$('code-input')) {
      var wrap = document.createElement('div');
      wrap.className = 'row';
      wrap.innerHTML = '<input class="focusable" id="code-input" placeholder="CANALIX-XXXX-XXXX" style="flex:1">' +
        '<button class="btn primary focusable" id="code-ok">' + esc(t('common.ok')) + '</button>';
      $('pay-qr').parentNode.insertBefore(wrap, $('pay-qr'));
      $('code-ok').onclick = function () {
        License.redeem($('code-input').value).then(function () { toast(t('code.ok')); leavePaywall(); })
          .catch(function (e) { toast(t('code.bad', [e.message || e])); });
      };
    }
    SpatialNav.focus($('code-input'));
    $('code-input').focus();
  };

  // ----------------------------------------------------------- Quitter
  function askExit() {
    if (Store.get('exitAsk', 0) && Date.now() - Store.get('exitAsk', 0) < 2500) {
      try { if (window.tizen) tizen.application.getCurrentApplication().exit(); } catch (e) {}
      try { if (window.webOS && webOS.platformBack) webOS.platformBack(); } catch (e) {}
      try { window.close(); } catch (e) {}
      return;
    }
    Store.set('exitAsk', Date.now());
    toast(t('exit.q') + ' (' + t('common.back') + ')', 2500);
  }

  // ----------------------------------------------------------- Touches
  document.addEventListener('keydown', function (e) {
    var code = e.keyCode;
    var inInput = document.activeElement && document.activeElement.tagName === 'INPUT';
    if (inInput && (code === 8 || (code >= 48 && code <= 90))) return; // saisie normale
    if (S.screen === 'home') { homeKey(code); e.preventDefault(); return; }
    var root = $(S.screen);
    if (Keys.is(code, Keys.BACK) && !inInput) {
      if (S.screen === 'recs' && Player.isFull()) { Player.stop(); show('recs'); renderRecs(); }
      else if (S.screen === 'settings') backHome();
      else if (S.screen === 'homerec' || S.screen === 'recs') openSettings();
      else if (S.screen === 'recdlg') backHome();
      else if (S.screen === 'paywall') leavePaywall();
      else if (S.screen === 'setup' && S.catalog) show('home');
      else askExit();
      e.preventDefault();
      return;
    }
    if (S.screen === 'recs' && Player.isFull()) {
      if (Keys.is(code, Keys.PLAY_PAUSE) || code === Keys.ENTER) Player.pauseToggle();
      e.preventDefault();
      return;
    }
    if (SpatialNav.handle(root, code)) e.preventDefault();
  });

  // Souris / pointeur LG Magic Remote.
  $('groups').addEventListener('click', function (e) {
    var rows = Array.prototype.slice.call($('groups').children), i = rows.indexOf(e.target.closest('.item'));
    if (i < 0) return;
    var start = Math.max(0, Math.min(S.groupFocus - 5, groupsList().length + 1 - 12));
    S.groupFocus = start + i; S.zone = 'groups'; homeKey(Keys.ENTER);
  });
  $('items').addEventListener('click', function (e) {
    var rows = Array.prototype.slice.call($('items').children), i = rows.indexOf(e.target.closest('.item'));
    if (i < 0) return;
    var start = Math.max(0, Math.min(S.item - 4, S.items.length - VISIBLE));
    S.item = start + i; S.zone = 'items'; homeKey(Keys.ENTER);
  });
  Array.prototype.forEach.call(document.querySelectorAll('#sections .tab'), function (b) {
    b.addEventListener('click', function () { S.zone = 'tabs'; S.tabFocus = b.getAttribute('data-section'); homeKey(Keys.ENTER); });
  });

  // L'app passe en arriere-plan (bouton Accueil de la tele).
  document.addEventListener('visibilitychange', function () {
    if (document.hidden) Player.suspend(); else if (S.screen === 'home') Player.restore();
  });

  // ----------------------------------------------------------- Utilitaires
  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }
  function initials(n) { return String(n || '?').replace(/[^\w ]/g, '').split(' ').filter(Boolean).slice(0, 2).map(function (w) { return w[0]; }).join('').toUpperCase() || '?'; }
  function hm(ms) { var d = new Date(ms); return ('0' + d.getHours()).slice(-2) + ':' + ('0' + d.getMinutes()).slice(-2); }

  // Pour les tests automatiques.
  window.__canalix = { S: S, homeKey: homeKey, openPaywall: openPaywall, openSettings: openSettings, openRecs: openRecs, openHomeRec: openHomeRec, openRecord: openRecord };
  start();
})();
