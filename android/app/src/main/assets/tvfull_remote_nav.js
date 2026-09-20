(function () {
  'use strict';

  if (window.__tvfullNav) {
    try { window.__tvfullNav.refresh(); } catch (_) {}
    return;
  }

  var current = null;
  var frame = null;
  var lastMove = 0;

  function rect(el) {
    try { return el.getBoundingClientRect(); } catch (_) { return null; }
  }

  function visible(el) {
    if (!el || !el.isConnected) return false;
    var r = rect(el);
    if (!r || r.width < 3 || r.height < 3) return false;
    if (r.bottom < -8 || r.right < -8 ||
        r.top > window.innerHeight + 8 || r.left > window.innerWidth + 8) {
      return false;
    }
    try {
      var s = getComputedStyle(el);
      if (s.display === 'none' || s.visibility === 'hidden' ||
          Number(s.opacity || '1') < 0.04 || s.pointerEvents === 'none') {
        return false;
      }
    } catch (_) {}
    if (el.disabled || el.getAttribute('aria-disabled') === 'true') return false;
    return true;
  }

  function interactiveSelector() {
    var host = (location.hostname || '').toLowerCase();
    var common =
      'button,a[href],input:not([type=hidden]),textarea,select,' +
      '[role=button],[role=link],[role=tab],[role=menuitem],[role=option],' +
      '[tabindex]:not([tabindex="-1"])';

    if (host.indexOf('netflix.com') >= 0) {
      return common + ',[data-uia="action-button"],[data-uia="field-email+wrapper"] input';
    }
    if (host.indexOf('primevideo.com') >= 0 || host.indexOf('amazon.com') >= 0) {
      return common + ',[data-testid^=pv-nav-],[data-testid^=dp-atf-play-button],' +
        '[data-testid^=episode] button,[aria-label=Play],[aria-label=Pause],' +
        '[aria-label="Close Player"]';
    }
    if (host.indexOf('max.com') >= 0 || host.indexOf('hbomax.com') >= 0) {
      return common + ',[data-testid],[aria-label]';
    }
    if (host.indexOf('crunchyroll.com') >= 0) {
      return common + ',[data-t=header-tile],[data-t$="-btn"],' +
        '[data-testid=play-pause-button],[data-testid=fullscreen-button]';
    }
    return common;
  }

  function uniqueVisible(nodes) {
    var out = [];
    var seen = new Set();
    for (var i = 0; i < nodes.length && out.length < 650; i++) {
      var el = nodes[i];
      if (!el || seen.has(el) || !visible(el)) continue;
      seen.add(el);
      out.push(el);
    }
    return out;
  }

  function activeLayer() {
    var dialogs = document.querySelectorAll(
      '[role=dialog],[aria-modal=true],[class*=modal],[class*=dialog],[class*=overlay]'
    );
    var best = null;
    var bestArea = 0;
    for (var i = 0; i < dialogs.length; i++) {
      var el = dialogs[i];
      if (!visible(el)) continue;
      var r = rect(el);
      if (!r) continue;
      var area = r.width * r.height;
      if (area > bestArea) { best = el; bestArea = area; }
    }
    return best;
  }

  function candidates() {
    var root = activeLayer() || document;
    var nodes = [];
    try { nodes = root.querySelectorAll(interactiveSelector()); } catch (_) {}
    return uniqueVisible(nodes);
  }

  function ensureFrame() {
    if (frame && frame.isConnected) return frame;
    frame = document.createElement('div');
    frame.setAttribute('data-tvfull-nav', 'frame');
    var s = frame.style;
    s.position = 'fixed';
    s.pointerEvents = 'none';
    s.zIndex = '2147483647';
    s.border = '3px solid #f2d58a';
    s.borderRadius = '10px';
    s.boxShadow = '0 0 0 2px rgba(0,0,0,.75),0 0 18px rgba(216,181,91,.85)';
    s.transition = 'left 70ms linear,top 70ms linear,width 70ms linear,height 70ms linear';
    s.display = 'none';
    (document.documentElement || document.body).appendChild(frame);
    return frame;
  }

  function paint(el) {
    var f = ensureFrame();
    if (!el || !visible(el)) {
      f.style.display = 'none';
      return;
    }
    var r = rect(el);
    if (!r) { f.style.display = 'none'; return; }
    f.style.display = 'block';
    f.style.left = Math.max(1, r.left - 4) + 'px';
    f.style.top = Math.max(1, r.top - 4) + 'px';
    f.style.width = Math.max(4, r.width + 8) + 'px';
    f.style.height = Math.max(4, r.height + 8) + 'px';
  }

  function mark(el) {
    if (!el) return 'none';
    current = el;
    try { el.scrollIntoView({ block: 'nearest', inline: 'nearest', behavior: 'auto' }); } catch (_) {}
    try { el.focus({ preventScroll: true }); } catch (_) { try { el.focus(); } catch (_) {} }
    paint(el);
    setTimeout(function () { if (current === el) paint(el); }, 90);
    return 'focus';
  }

  function initial(list) {
    var active = document.activeElement;
    if (active && list.indexOf(active) >= 0) return active;
    var best = null;
    var score = Infinity;
    for (var i = 0; i < list.length; i++) {
      var r = rect(list[i]);
      if (!r) continue;
      var s = Math.max(0, r.top) * 1.4 + Math.max(0, r.left);
      if (s < score) { score = s; best = list[i]; }
    }
    return best || list[0] || null;
  }

  function center(el) {
    var r = rect(el);
    if (!r) return null;
    return { x: r.left + r.width / 2, y: r.top + r.height / 2, r: r };
  }

  function wakePlayer() {
    try {
      var x = window.innerWidth / 2;
      var y = Math.max(20, window.innerHeight - 90);
      document.dispatchEvent(new MouseEvent('mousemove', {
        bubbles: true, clientX: x, clientY: y
      }));
    } catch (_) {}
  }

  function move(dir) {
    var now = Date.now();
    if (now - lastMove < 65) return 'throttle';
    lastMove = now;
    wakePlayer();

    var list = candidates();
    if (!list.length) { paint(null); current = null; return 'none'; }

    if (!current || list.indexOf(current) < 0 || !visible(current)) {
      return mark(initial(list));
    }

    var a = center(current);
    if (!a) return mark(initial(list));

    var best = null;
    var bestScore = Infinity;
    for (var i = 0; i < list.length; i++) {
      var el = list[i];
      if (el === current) continue;
      var b = center(el);
      if (!b) continue;

      var dx = b.x - a.x;
      var dy = b.y - a.y;
      var primary = 0;
      var secondary = 0;

      if (dir === 'right') {
        if (dx <= 5) continue;
        primary = dx; secondary = Math.abs(dy);
      } else if (dir === 'left') {
        if (dx >= -5) continue;
        primary = -dx; secondary = Math.abs(dy);
      } else if (dir === 'down') {
        if (dy <= 5) continue;
        primary = dy; secondary = Math.abs(dx);
      } else if (dir === 'up') {
        if (dy >= -5) continue;
        primary = -dy; secondary = Math.abs(dx);
      } else {
        continue;
      }

      var aligned = secondary <= Math.max(70, primary * 0.75);
      var score = primary + secondary * (aligned ? 1.7 : 4.2);
      var overlapPenalty = 0;
      if ((dir === 'left' || dir === 'right') &&
          (b.r.bottom < a.r.top || b.r.top > a.r.bottom)) overlapPenalty = 120;
      if ((dir === 'up' || dir === 'down') &&
          (b.r.right < a.r.left || b.r.left > a.r.right)) overlapPenalty = 120;
      score += overlapPenalty;

      if (score < bestScore) { bestScore = score; best = el; }
    }

    if (!best) return 'edge';
    return mark(best);
  }

  function tapFor(el) {
    if (!el || !visible(el)) return 'none';
    var r = rect(el);
    if (!r) return 'none';
    return 'TAP:' +
      Math.round(r.left + r.width / 2) + ',' +
      Math.round(r.top + r.height / 2) + ',' +
      window.innerWidth + ',' + window.innerHeight;
  }

  function activate() {
    var list = candidates();
    if (!current || list.indexOf(current) < 0 || !visible(current)) {
      current = initial(list);
      if (!current) return 'none';
      mark(current);
    }
    return tapFor(current);
  }

  function back() {
    wakePlayer();

    var selectors = [
      '[aria-label="Close Player"]',
      '[aria-label="Close"]',
      '[aria-label="Back"]',
      '[aria-label="Go back"]',
      '[data-testid*=close]',
      '[data-testid*=back]',
      'button[class*=close]',
      'button[class*=back]'
    ];

    for (var i = 0; i < selectors.length; i++) {
      var els = [];
      try { els = document.querySelectorAll(selectors[i]); } catch (_) {}
      for (var j = 0; j < els.length; j++) {
        if (visible(els[j])) return tapFor(els[j]);
      }
    }

    var layer = activeLayer();
    if (layer) {
      var buttons = layer.querySelectorAll('button,[role=button],a[href]');
      for (var k = 0; k < buttons.length; k++) {
        var el = buttons[k];
        if (!visible(el)) continue;
        var label = (
          el.getAttribute('aria-label') || el.getAttribute('title') ||
          el.textContent || ''
        ).trim().toLowerCase();
        if (label === 'cerrar' || label === 'close' ||
            label === 'volver' || label === 'back' ||
            label.indexOf('close') === 0 || label.indexOf('cerrar') === 0) {
          return tapFor(el);
        }
      }
    }

    return 'HISTORY';
  }

  function refresh() {
    if (current && visible(current)) paint(current);
    else { current = null; paint(null); }
    return 'ready';
  }

  window.addEventListener('scroll', function () {
    if (current) paint(current);
  }, true);
  window.addEventListener('resize', function () {
    if (current) paint(current);
  });

  window.__tvfullNav = {
    move: move,
    activate: activate,
    back: back,
    refresh: refresh
  };
})();