// Lecteur : AVPlay sur Samsung (le plus fiable pour HLS et MPEG-TS),
// balise <video> ailleurs (LG lit le HLS nativement, hls.js dans un navigateur).
var Player = (function () {
  var stage = document.getElementById('stage');
  var video = document.getElementById('video');
  var avEl = document.getElementById('avplay');
  var useAv = !!(window.webapis && webapis.avplay);
  var hls = null, current = null, retries = 0, retryTimer = null;
  var listeners = { state: [] };

  function emit(s) { listeners.state.forEach(function (f) { f(s); }); }

  /** Place la video dans un rectangle de l'ecran (apercu) ou en plein ecran. */
  function place(rect) {
    stage.classList.remove('hidden');
    if (!rect) {
      stage.classList.add('full');
      stage.style.left = stage.style.top = '0px';
    } else {
      stage.classList.remove('full');
      stage.style.left = rect.left + 'px'; stage.style.top = rect.top + 'px';
      stage.style.width = rect.width + 'px'; stage.style.height = rect.height + 'px';
    }
    if (useAv) {
      var r = rect || { left: 0, top: 0, width: 1920, height: 1080 };
      try { webapis.avplay.setDisplayRect(Math.round(r.left), Math.round(r.top), Math.round(r.width), Math.round(r.height)); } catch (e) {}
    }
  }

  function stopInternal() {
    clearTimeout(retryTimer);
    if (useAv) { try { webapis.avplay.stop(); webapis.avplay.close(); } catch (e) {} return; }
    if (hls) { hls.destroy(); hls = null; }
    video.pause(); video.removeAttribute('src'); try { video.load(); } catch (e) {}
  }

  function start(url) {
    stopInternal();
    emit('loading');
    if (useAv) {
      avEl.classList.remove('hidden'); video.classList.add('hidden');
      try {
        webapis.avplay.open(url);
        webapis.avplay.setListener({
          onbufferingstart: function () { emit('loading'); },
          onbufferingcomplete: function () { emit('playing'); },
          onerror: function () { fail(); },
          onstreamcompleted: function () { emit('ended'); },
        });
        place(stage.classList.contains('full') ? null : stage.getBoundingClientRect());
        webapis.avplay.setDisplayMethod('PLAYER_DISPLAY_MODE_LETTER_BOX');
        webapis.avplay.prepareAsync(function () { webapis.avplay.play(); retries = 0; emit('playing'); }, fail);
      } catch (e) { fail(); }
      return;
    }
    avEl.classList.add('hidden'); video.classList.remove('hidden');
    var isHls = /\.m3u8(\?|$)/i.test(url);
    if (isHls && !video.canPlayType('application/vnd.apple.mpegurl') && window.Hls && Hls.isSupported()) {
      hls = new Hls({ liveSyncDurationCount: 3, maxBufferLength: 30 });
      hls.on(Hls.Events.ERROR, function (_, d) { if (d.fatal) fail(); });
      hls.loadSource(url);
      hls.attachMedia(video);
    } else {
      video.src = url;
    }
    var p = video.play();
    if (p && p.catch) p.catch(function () {});
  }

  // Reconnexion automatique (5 essais, de plus en plus espaces).
  function fail() {
    if (!current) return;
    if (retries >= 5) { emit('failed'); return; }
    retries++;
    emit('reconnecting');
    clearTimeout(retryTimer);
    retryTimer = setTimeout(function () { if (current) start(current.url); }, 1000 * retries);
  }

  video.addEventListener('playing', function () { retries = 0; emit('playing'); });
  video.addEventListener('waiting', function () { emit('loading'); });
  video.addEventListener('error', fail);

  return {
    on: function (ev, f) { listeners[ev].push(f); },
    play: function (ch, rect) { current = ch; retries = 0; place(rect); start(ch.url); },
    current: function () { return current; },
    place: place,
    fullscreen: function (on, rect) { place(on ? null : rect); },
    isFull: function () { return stage.classList.contains('full'); },
    stop: function () { current = null; stopInternal(); stage.classList.add('hidden'); emit('stopped'); },
    pauseToggle: function () {
      if (useAv) { try { var s = webapis.avplay.getState(); s === 'PLAYING' ? webapis.avplay.pause() : webapis.avplay.play(); } catch (e) {} return; }
      video.paused ? video.play() : video.pause();
    },
    suspend: function () { if (useAv) { try { webapis.avplay.suspend(); } catch (e) {} } else video.pause(); },
    restore: function () { if (useAv) { try { webapis.avplay.restore(); } catch (e) {} } else if (current) video.play(); },
  };
})();
