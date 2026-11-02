// Touches de telecommande et navigation au focus (Samsung, LG, clavier).
var Keys = {
  LEFT: 37, UP: 38, RIGHT: 39, DOWN: 40, ENTER: 13,
  BACK: [10009, 461, 8, 27],
  CH_UP: [427, 33], CH_DOWN: [428, 34],
  PLAY_PAUSE: [10252, 415, 19, 32],
  INFO: [457, 73],
  is: function (code, k) { return Array.isArray(k) ? k.indexOf(code) >= 0 : code === k; },
};

(function registerKeys() {
  // Samsung : les touches speciales doivent etre demandees.
  try {
    if (window.tizen && tizen.tvinputdevice) {
      ['ChannelUp', 'ChannelDown', 'MediaPlayPause', 'MediaPlay', 'MediaPause', 'Info', 'ColorF0Red']
        .forEach(function (k) { try { tizen.tvinputdevice.registerKey(k); } catch (e) {} });
    }
  } catch (e) {}
})();

/** Navigation spatiale generique entre les elements .focusable d'un ecran. */
var SpatialNav = {
  current: null,
  items: function (root) {
    return Array.prototype.filter.call(root.querySelectorAll('.focusable'), function (el) {
      return el.offsetParent !== null && !el.closest('.hidden');
    });
  },
  focus: function (el) {
    if (this.current) this.current.classList.remove('focused');
    this.current = el;
    if (el) {
      el.classList.add('focused');
      if (el.scrollIntoView) el.scrollIntoView({ block: 'nearest' });
    }
  },
  first: function (root) { this.focus(this.items(root)[0] || null); },
  move: function (root, dir) {
    var list = this.items(root);
    if (!this.current || list.indexOf(this.current) < 0) return this.focus(list[0] || null);
    var a = this.current.getBoundingClientRect();
    var ax = a.left + a.width / 2, ay = a.top + a.height / 2, best = null, bestD = Infinity;
    list.forEach(function (el) {
      if (el === SpatialNav.current) return;
      var b = el.getBoundingClientRect(), bx = b.left + b.width / 2, by = b.top + b.height / 2;
      var dx = bx - ax, dy = by - ay;
      var ok = dir === 'left' ? dx < -5 : dir === 'right' ? dx > 5 : dir === 'up' ? dy < -5 : dy > 5;
      if (!ok) return;
      var main = (dir === 'left' || dir === 'right') ? Math.abs(dx) : Math.abs(dy);
      var side = (dir === 'left' || dir === 'right') ? Math.abs(dy) : Math.abs(dx);
      var d = main + side * 2.5;
      if (d < bestD) { bestD = d; best = el; }
    });
    if (best) this.focus(best);
  },
  /** Gestion des fleches + OK pour un ecran de formulaire. Renvoie vrai si traite. */
  handle: function (root, code) {
    var active = document.activeElement;
    var typing = active && active.tagName === 'INPUT';
    if (typing) {
      // Dans un champ : OK ou bas sortent du champ (le clavier de la tele se ferme).
      if (code === Keys.ENTER || code === Keys.DOWN || code === Keys.UP) { active.blur(); this.move(root, code === Keys.UP ? 'up' : 'down'); return true; }
      return false;
    }
    if (code === Keys.LEFT) this.move(root, 'left');
    else if (code === Keys.RIGHT) this.move(root, 'right');
    else if (code === Keys.UP) this.move(root, 'up');
    else if (code === Keys.DOWN) this.move(root, 'down');
    else if (code === Keys.ENTER && this.current) {
      if (this.current.tagName === 'INPUT') this.current.focus();
      else this.current.click();
    } else return false;
    return true;
  },
};
