/// Semua skrip yang dijalankan di dalam WebView TikTok (versi web desktop).
///
/// PENTING: selector TikTok bisa berubah kapan saja. Semua selector ada di
/// satu tempat (di bawah) supaya mudah diperbaiki. Cek lewat
/// chrome://inspect -> WebView aplikasi ini.
class TikTokJs {
  // ---------- Cek akun yang sedang login ----------
  static const String probeAccount = r'''
(function(){
  try {
    var el = document.getElementById('__UNIVERSAL_DATA_FOR_REHYDRATION__');
    if (el) {
      var d = JSON.parse(el.textContent);
      var ctx = (d['__DEFAULT_SCOPE__'] || {})['webapp.app-context'] || {};
      var u = ctx.user;
      if (u && u.uniqueId) {
        return JSON.stringify({loggedIn:true, username:u.uniqueId, nickname:u.nickName || u.uniqueId});
      }
    }
    var a = document.querySelector('[data-e2e="nav-profile"]');
    if (a) {
      var m = (a.getAttribute('href') || '').match(/@([^\/?#]+)/);
      if (m) return JSON.stringify({loggedIn:true, username:m[1], nickname:m[1]});
    }
    return JSON.stringify({loggedIn:false});
  } catch (e) {
    return JSON.stringify({loggedIn:false, error:String(e)});
  }
})()
''';

  // ---------- Cari & klik tab Repost (body async, menunggu halaman render) ----------
  static const String findRepostTab = r'''
var RE = /(^|\s)(reposts?|posting(an)? ulang|pos ulang|repostingan)(\s|$)/i;
function sleep(ms){ return new Promise(function(r){ setTimeout(r, ms); }); }
function visible(e){ var r = e.getBoundingClientRect(); return r.width > 0 && r.height > 0; }

function find(){
  var d = document.querySelector('[data-e2e="repost-tab"]');
  if (d) return {el:d, how:'data-e2e=repost-tab'};

  var attrs = document.querySelectorAll('[data-e2e],[aria-label],[title]');
  for (var i = 0; i < attrs.length; i++) {
    var e = attrs[i];
    var e2e = e.getAttribute('data-e2e') || '';
    var lb = (e.getAttribute('aria-label') || '') + ' ' + (e.getAttribute('title') || '');
    if (visible(e) && ((/repost/i.test(e2e) && /tab/i.test(e2e)) || RE.test(lb.trim()))) {
      return {el:e, how:'atribut'};
    }
  }

  var els = document.querySelectorAll('[role="tab"], a, button, p, span, div');
  var best = null;
  for (var j = 0; j < els.length; j++) {
    var x = els[j];
    var t = (x.innerText || '').trim();
    if (t && t.length < 30 && RE.test(t) && visible(x)) {
      if (x.children.length === 0) return {el:x, how:'teks'};
      if (!best) best = x;
    }
  }
  return best ? {el:best, how:'teks-induk'} : null;
}

for (var n = 0; n < 30; n++) {
  var f = find();
  if (f) {
    var t = f.el.closest('[role="tab"]') || f.el;
    t.scrollIntoView({block:'center'});
    t.click();
    return {ok:true, how:f.how};
  }
  await sleep(700);
}

var list = [];
document.querySelectorAll('[role="tab"], [data-e2e*="tab"], [data-e2e*="repost"], [data-e2e*="profile"]').forEach(function(e, i){
  if (i < 40) list.push({tag:e.tagName, e2e:e.getAttribute('data-e2e'), aria:e.getAttribute('aria-label'), text:(e.innerText || '').trim().slice(0, 30)});
});
return {ok:false, step:'tab-not-found', diag:{
  url: location.href,
  title: document.title,
  body: (document.body.innerText || '').slice(0, 300),
  videoLinks: document.querySelectorAll('a[href*="/video/"]').length,
  tabs: list
}};
''';

  // ---------- Buka video dari grid repost (navigasi dalam halaman, tanpa muat ulang) ----------
  // Dipakai dengan awalan:  var ID = '<id video>';
  static const String openItem = r'''
function sleep(ms){ return new Promise(function(r){ setTimeout(r, ms); }); }
for (var n = 0; n < 25; n++) {
  var a = document.querySelector('a[href*="/video/' + ID + '"]');
  if (a) {
    a.scrollIntoView({block:'center'});
    await sleep(300);
    a.click();
    return {ok:true, how:'grid'};
  }
  window.scrollBy(0, 1200);
  await sleep(600);
}
return {ok:false, step:'item-not-in-grid'};
''';

  // ---------- Deteksi captcha ----------
  static const String hasCaptcha = r'''
(function(){
  function capVisible(){
    var n = document.querySelectorAll('[id*="captcha" i],[class*="captcha" i]');
    for (var i = 0; i < n.length; i++) {
      var r = n[i].getBoundingClientRect();
      if (r.width > 150 && r.height > 100) return true;
    }
    return false;
  }
  return JSON.stringify(capVisible());
})()
''';

  // ---------- Kumpulkan repost yang tampil + scroll ke bawah ----------
  static const String collect = r'''
(function(){
  function capVisible(){
    var n = document.querySelectorAll('[id*="captcha" i],[class*="captcha" i]');
    for (var i = 0; i < n.length; i++) {
      var r = n[i].getBoundingClientRect();
      if (r.width > 150 && r.height > 100) return true;
    }
    return false;
  }
  var root = document.querySelector('[data-e2e="user-post-item-list"]') || document;
  var out = [];
  root.querySelectorAll('a[href*="/video/"]').forEach(function(a){
    var m = (a.getAttribute('href') || '').match(/\/@([^\/]+)\/video\/(\d+)/);
    if (!m) return;
    var img = a.querySelector('img');
    out.push({id:m[2], author:m[1], url:a.href, desc: img ? (img.alt || '') : '', thumb: img ? img.src : ''});
  });
  window.scrollTo(0, document.body.scrollHeight);
  var sc = document.scrollingElement;
  if (sc) sc.scrollTop = sc.scrollHeight;
  return JSON.stringify({items: out, captcha: capVisible()});
})()
''';

  // ---------- Hapus satu repost (dijalankan di halaman video) ----------
  // Body fungsi async. Mengembalikan {ok, step}.
  static const String removeRepost = r'''
var SELECTORS = {
  share:  '[data-e2e="share-icon"]',
  repost: '[data-e2e="repost-icon"]'
};
var REMOVE = /^(remove repost|undo repost|hapus postingan ulang|batalkan postingan ulang|hapus repost|batalkan repost)$/i;
var CONFIRM = /^(remove|hapus|confirm|konfirmasi|yes|ya|ok)$/i;

function sleep(ms){ return new Promise(function(r){ setTimeout(r, ms); }); }
function visible(e){ var r = e.getBoundingClientRect(); return r.width > 0 && r.height > 0; }
function findByText(re, root){
  var els = (root || document).querySelectorAll('button,[role="button"],[role="menuitem"],li,a,div,span,p');
  var best = null;
  for (var i = 0; i < els.length; i++) {
    var e = els[i];
    var t = (e.innerText || '').trim();
    if (t && t.length < 50 && re.test(t) && visible(e)) {
      best = e;
      if (e.children.length === 0) return e;
    }
  }
  return best;
}
function clickEl(e){ var t = e.closest('button,[role="button"],[role="menuitem"],li,a') || e; t.click(); }

function capVisible(){
  var n = document.querySelectorAll('[id*="captcha" i],[class*="captcha" i]');
  for (var i = 0; i < n.length; i++) {
    var r = n[i].getBoundingClientRect();
    if (r.width > 150 && r.height > 100) return true;
  }
  return false;
}
if (capVisible()) return {ok:false, step:'captcha'};
if (location.pathname.indexOf('/login') === 0) return {ok:false, step:'login'};

await sleep(900);
var btn = findByText(REMOVE);

if (!btn) {
  var openers = [SELECTORS.share, SELECTORS.repost];
  for (var i = 0; i < openers.length && !btn; i++) {
    var el = document.querySelector(openers[i]);
    if (el) { clickEl(el); await sleep(900); btn = findByText(REMOVE); }
  }
}
if (!btn) {
  var al = document.querySelectorAll('[aria-label]');
  for (var j = 0; j < al.length && !btn; j++) {
    var lb = al[j].getAttribute('aria-label') || '';
    if (/share|repost|bagikan|postingan ulang/i.test(lb) && visible(al[j])) {
      clickEl(al[j]); await sleep(900); btn = findByText(REMOVE);
    }
  }
}
if (!btn) {
  var items = [];
  document.querySelectorAll('button,[role="button"],[role="menuitem"],[data-e2e]').forEach(function(e){
    if (items.length < 50 && visible(e)) {
      items.push({tag:e.tagName, e2e:e.getAttribute('data-e2e'), aria:e.getAttribute('aria-label'), text:(e.innerText || '').trim().slice(0, 30)});
    }
  });
  return {ok:false, step:'remove-button-not-found', diag:{
    url: location.href,
    title: document.title,
    body: (document.body.innerText || '').slice(0, 300),
    items: items
  }};
}

clickEl(btn);
await sleep(900);
var dlg = document.querySelector('[role="dialog"]');
if (dlg) {
  var cf = findByText(CONFIRM, dlg);
  if (cf) { clickEl(cf); await sleep(600); }
}
return {ok:true, step:'done'};
''';
}
