// Shared clipboard-copy handler for docs/plugins/*.html copyfield buttons.
// See docs/plugins/_slots.md.
  (function () {
    function legacyCopy(text) {
      try {
        var ta = document.createElement('textarea');
        ta.value = text; ta.setAttribute('readonly', '');
        ta.style.position = 'fixed'; ta.style.top = '-9999px';
        document.body.appendChild(ta); ta.select();
        var ok = document.execCommand('copy');
        document.body.removeChild(ta);
        return ok;
      } catch (e) { return false; }
    }
    function copyText(text) {
      if (navigator.clipboard && navigator.clipboard.writeText) {
        return navigator.clipboard.writeText(text).then(function () { return true; }, function () { return legacyCopy(text); });
      }
      return Promise.resolve(legacyCopy(text));
    }
    var live = document.getElementById('copy-live');
    document.addEventListener('click', function (e) {
      var btn = e.target.closest && e.target.closest('.copy-btn');
      if (!btn) return;
      var text = btn.getAttribute('data-copy') || '';
      var label = btn.querySelector('.cf-label');
      copyText(text).then(function (ok) {
        clearTimeout(btn._resetT);
        btn.classList.remove('copied', 'failed');
        if (ok) {
          btn.classList.add('copied');
          if (label) label.textContent = 'Copied';
          if (live) live.textContent = 'Copied ' + text;
        } else {
          btn.classList.add('failed');
          if (label) label.textContent = 'Press ⌘C';
          if (live) live.textContent = 'Copy failed — select the command and press Command-C.';
        }
        btn._resetT = setTimeout(function () {
          btn.classList.remove('copied', 'failed');
          if (label) label.textContent = 'Copy';
        }, 2000);
      });
    });
  })();
