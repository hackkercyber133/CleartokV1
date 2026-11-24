import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'models.dart';
import 'tiktok_js.dart';

enum Phase { idle, loggingIn, scanning, removing, paused }

/// hidden = WebView tetap jalan di belakang UI (tak terlihat)
/// full   = layar login   |   captcha = kotak captcha di tengah layar
enum BrowserMode { hidden, mini, full, captcha }

class AppState extends ChangeNotifier {
  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

  late final WebViewController web;
  final _rng = Random();
  SharedPreferences? _prefs;

  Settings settings = Settings();
  Account? account;
  final List<Repost> reposts = [];
  final Set<String> _ids = {};
  final Set<String> selected = {};

  Phase phase = Phase.idle;
  BrowserMode browser = BrowserMode.hidden;
  String statusText = 'Siap';
  String? lastDiag;
  int removedSession = 0;
  int failedSession = 0;
  int removedToday = 0;
  int removedTotal = 0;

  bool _cancel = false;
  bool _paused = false;
  Completer<void>? _load;
  String? _lastLoadError;

  bool get busy =>
      phase == Phase.scanning ||
      phase == Phase.removing ||
      phase == Phase.paused;

  // ------------------------------------------------------------ init
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final p = _prefs!;
    settings.minDelayMs = p.getInt('minDelay') ?? 2500;
    settings.maxDelayMs = p.getInt('maxDelay') ?? 6000;
    settings.dailyLimit = p.getInt('dailyLimit') ?? 0;
    removedTotal = p.getInt('removedTotal') ?? 0;
    if (p.getString('dayKey') == _dayKey()) {
      removedToday = p.getInt('removedToday') ?? 0;
    }
    final u = p.getString('username');
    if (u != null) {
      account = Account(username: u, nickname: p.getString('nickname') ?? u);
    }

    web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(_ua)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (url) {
          final c = _load;
          if (c != null && !c.isCompleted) c.complete();
          _onPageFinished(url);
        },
        onWebResourceError: (e) {
          if (e.isForMainFrame != false) {
            _lastLoadError = '${e.errorCode} ${e.description}';
          }
        },
        // Cegah TikTok melempar ke aplikasi lain (intent://, snssdk://, dll).
        onNavigationRequest: (req) => req.url.startsWith('http')
            ? NavigationDecision.navigate
            : NavigationDecision.prevent,
      ));
  }

  String _dayKey() {
    final n = DateTime.now();
    return '${n.year}-${n.month}-${n.day}';
  }

  Future<void> _saveCounts() async {
    final p = _prefs;
    if (p == null) return;
    await p.setString('dayKey', _dayKey());
    await p.setInt('removedToday', removedToday);
    await p.setInt('removedTotal', removedTotal);
  }

  Future<void> updateSettings({int? minMs, int? maxMs, int? limit}) async {
    if (minMs != null) settings.minDelayMs = minMs;
    if (maxMs != null) settings.maxDelayMs = maxMs;
    if (settings.maxDelayMs < settings.minDelayMs) {
      settings.maxDelayMs = settings.minDelayMs;
    }
    if (limit != null) settings.dailyLimit = limit;
    final p = _prefs!;
    await p.setInt('minDelay', settings.minDelayMs);
    await p.setInt('maxDelay', settings.maxDelayMs);
    await p.setInt('dailyLimit', settings.dailyLimit);
    notifyListeners();
  }

  // ------------------------------------------------------------ helpers
  Future<void> _sleep(int ms) => Future.delayed(Duration(milliseconds: ms));

  Future<void> _goto(String url, {String? referer}) async {
    _lastLoadError = null;
    _load = Completer<void>();
    await web.loadRequest(
      Uri.parse(url),
      headers: referer != null ? {'Referer': referer} : const {},
    );
    await _load!.future.timeout(const Duration(seconds: 30), onTimeout: () {});
    await _sleep(1500);
  }

  dynamic _decode(Object r) {
    var s = r.toString();
    if (s.startsWith('"')) {
      try {
        s = jsonDecode(s) as String;
      } catch (_) {}
    }
    try {
      return jsonDecode(s);
    } catch (_) {
      return s;
    }
  }

  Future<dynamic> _runSync(String js) async {
    try {
      return _decode(await web.runJavaScriptReturningResult(js));
    } catch (_) {
      return null;
    }
  }

  /// Jalankan body fungsi async di halaman, lalu polling hasilnya.
  Future<Map<String, dynamic>> _runAsync(String body,
      {int timeoutSec = 25}) async {
    final js = 'window.__job = null;\n'
        '(async function(){ try { var r = await (async function(){ $body\n })();'
        ' window.__job = JSON.stringify(r); } catch(e) {'
        ' window.__job = JSON.stringify({ok:false, step:"exception", error:String(e)}); } })();\n'
        '"started";';
    try {
      await web.runJavaScript(js);
    } catch (e) {
      return {'ok': false, 'step': 'inject-error', 'error': '$e'};
    }
    final end = DateTime.now().add(Duration(seconds: timeoutSec));
    while (DateTime.now().isBefore(end)) {
      await _sleep(400);
      final d = await _runSync('window.__job');
      if (d is Map) return Map<String, dynamic>.from(d);
    }
    return {'ok': false, 'step': 'timeout'};
  }

  // ------------------------------------------------------------ login
  Future<void> startLogin() async {
    phase = Phase.loggingIn;
    browser = BrowserMode.full;
    statusText = 'Masuk ke TikTok…';
    notifyListeners();
    await web.loadRequest(Uri.parse('https://www.tiktok.com/login'));
  }

  void cancelLogin() {
    phase = Phase.idle;
    browser = BrowserMode.hidden;
    statusText = 'Siap';
    notifyListeners();
  }

  void _onPageFinished(String url) {
    if (phase == Phase.loggingIn &&
        url.contains('tiktok.com') &&
        !url.contains('/login')) {
      confirmLogin(auto: true);
    }
  }

  Future<void> confirmLogin({bool auto = false}) async {
    if (!auto) await _goto('https://www.tiktok.com/');
    final d = await _runSync(TikTokJs.probeAccount);
    if (d is Map && d['loggedIn'] == true) {
      account = Account(
        username: d['username'] as String,
        nickname: (d['nickname'] as String?) ?? d['username'] as String,
      );
      await _prefs?.setString('username', account!.username);
      await _prefs?.setString('nickname', account!.nickname);
      phase = Phase.idle;
      browser = BrowserMode.hidden;
      statusText = 'Akun terhubung';
    } else if (!auto) {
      statusText = 'Login belum terdeteksi. Selesaikan login, lalu coba lagi.';
    }
    notifyListeners();
  }

  Future<void> logout() async {
    await WebViewCookieManager().clearCookies();
    await web.clearLocalStorage();
    await _prefs?.remove('username');
    await _prefs?.remove('nickname');
    account = null;
    reposts.clear();
    _ids.clear();
    selected.clear();
    statusText = 'Siap';
    notifyListeners();
  }

  // ------------------------------------------------------------ scan
  Future<void> scan() async {
    if (account == null || busy) return;
    _cancel = false;
    _paused = false;
    phase = Phase.scanning;
    browser = BrowserMode.hidden;
    reposts.clear();
    _ids.clear();
    selected.clear();
    lastDiag = null;
    statusText = 'Membuka profil…';
    notifyListeners();

    await _goto('https://www.tiktok.com/@${account!.username}');
    statusText = 'Mencari tab Repost…';
    notifyListeners();
    final tab = await _runAsync(TikTokJs.findRepostTab, timeoutSec: 40);
    if (tab['ok'] != true) {
      lastDiag = const JsonEncoder.withIndent('  ').convert(tab['diag'] ?? tab);
      statusText = 'Tab Repost tidak ditemukan. Ketuk "Lihat diagnostik".';
      _finish();
      return;
    }
    await _sleep(2500);

    var stable = 0;
    while (!_cancel && stable < 6) {
      final d = await _runSync(TikTokJs.collect);
      if (d is Map) {
        if (d['captcha'] == true) {
          await _waitCaptcha();
          continue;
        }
        for (final it in (d['items'] as List? ?? const [])) {
          final m = Map<String, dynamic>.from(it as Map);
          final id = m['id'] as String;
          if (_ids.add(id)) {
            reposts.add(Repost(
              id: id,
              author: m['author'] as String,
              url: m['url'] as String,
              desc: (m['desc'] as String?) ?? '',
              thumb: (m['thumb'] as String?) ?? '',
            ));
            selected.add(id);
          }
        }
      }
      final before = reposts.length;
      statusText = 'Memindai Repost…';
      notifyListeners();
      await _sleep(1300);
      if (reposts.length == before) {
        stable++;
      } else {
        stable = 0;
      }
    }
    statusText = reposts.isEmpty
        ? 'Tidak ada repost ditemukan'
        : 'Ditemukan ${reposts.length} repost';
    _finish();
  }

  Future<void> _waitCaptcha() async {
    final prev = browser;
    browser = BrowserMode.captcha;
    statusText = 'Captcha muncul — selesaikan di layar';
    HapticFeedback.heavyImpact();
    notifyListeners();
    // Beri waktu captcha benar-benar tampil, lalu tunggu sampai hilang.
    await _sleep(1500);
    final end = DateTime.now().add(const Duration(minutes: 10));
    while (!_cancel && DateTime.now().isBefore(end)) {
      await _sleep(1500);
      final c = await _runSync(TikTokJs.hasCaptcha);
      if (c != true) break;
    }
    browser = prev;
    statusText = 'Melanjutkan…';
    notifyListeners();
    await _sleep(1500);
  }

  void _finish() {
    phase = Phase.idle;
    browser = BrowserMode.hidden;
    _paused = false;
    notifyListeners();
  }

  // ------------------------------------------------------------ remove
  Future<bool> _openRepostGrid() async {
    await _goto('https://www.tiktok.com/@${account!.username}');
    final tab = await _runAsync(TikTokJs.findRepostTab, timeoutSec: 40);
    if (tab['ok'] != true) {
      lastDiag ??= const JsonEncoder.withIndent('  ').convert(tab['diag'] ?? tab);
      return false;
    }
    await _sleep(2000);
    return true;
  }

  /// Kembali dari halaman video ke grid repost tanpa muat ulang penuh.
  Future<bool> _backToGrid() async {
    try {
      await web.runJavaScript('history.back();');
    } catch (_) {}
    await _sleep(1800);
    final t = await _runAsync(TikTokJs.findRepostTab, timeoutSec: 12);
    if (t['ok'] == true) {
      await _sleep(1500);
      return true;
    }
    return _openRepostGrid();
  }

  Future<void> removeSelected() async {
    if (account == null || busy) return;
    final queue = reposts
        .where((r) => selected.contains(r.id) && r.state != RepostState.removed)
        .toList();
    if (queue.isEmpty) return;

    _cancel = false;
    _paused = false;
    removedSession = 0;
    failedSession = 0;
    lastDiag = null;
    phase = Phase.removing;
    browser = BrowserMode.hidden;
    statusText = 'Membuka daftar repost…';
    notifyListeners();

    if (!await _openRepostGrid()) {
      statusText = 'Tab Repost tidak ditemukan. Ketuk "Lihat diagnostik".';
      _finish();
      return;
    }

    final profileUrl = 'https://www.tiktok.com/@${account!.username}';
    var consecutiveFails = 0;
    for (var i = 0; i < queue.length; i++) {
      if (_cancel) break;
      while (_paused && !_cancel) {
        await _sleep(300);
      }
      if (_cancel) break;

      final limit = settings.dailyLimit;
      if (limit > 0 && removedToday >= limit) {
        statusText = 'Batas harian ($limit) tercapai';
        break;
      }

      final r = queue[i];
      statusText = 'Menghapus ${i + 1} / ${queue.length}';
      notifyListeners();

      // 1) Buka video dengan klik dari grid (navigasi dalam halaman).
      var res = await _runAsync("var ID = '${r.id}';\n${TikTokJs.openItem}",
          timeoutSec: 30);
      var viaFallback = false;
      if (res['ok'] != true) {
        // 2) Cadangan: muat URL video langsung, dengan Referer profil.
        viaFallback = true;
        await _goto(r.url, referer: profileUrl);
        res = _lastLoadError == null
            ? {'ok': true}
            : {'ok': false, 'step': 'load-error', 'error': _lastLoadError};
      }

      // 3) Hapus repost.
      if (res['ok'] == true) {
        res = await _runAsync(TikTokJs.removeRepost);
        if (res['step'] == 'captcha') {
          await _waitCaptcha();
          res = await _runAsync(TikTokJs.removeRepost);
        }
      }

      if (res['ok'] == true) {
        r.state = RepostState.removed;
        selected.remove(r.id);
        removedSession++;
        removedToday++;
        removedTotal++;
        consecutiveFails = 0;
        await _saveCounts();
      } else {
        r.state = RepostState.failed;
        failedSession++;
        consecutiveFails++;
        statusText = 'Gagal (${res['step']})';
        lastDiag ??= const JsonEncoder.withIndent('  ').convert({
          'step': res['step'],
          'error': res['error'],
          'loadError': _lastLoadError,
          'diag': res['diag'],
        });
        if (res['step'] == 'login') {
          statusText = 'Sesi login habis — masuk lagi';
          break;
        }
        if (consecutiveFails >= 3) {
          statusText =
              'Gagal 3x berturut-turut (${res['step']}). Ketuk "Lihat diagnostik".';
          break;
        }
      }
      notifyListeners();

      // 4) Kembali ke grid untuk repost berikutnya.
      final ok = viaFallback ? await _openRepostGrid() : await _backToGrid();
      if (!ok) {
        statusText = 'Gagal kembali ke daftar repost. Ketuk "Lihat diagnostik".';
        break;
      }

      if (res['ok'] != true) {
        // Backoff: makin sering gagal, makin lama jeda.
        await _sleep(min(30000, 1000 * pow(2, consecutiveFails).toInt()));
      }
      final span = settings.maxDelayMs - settings.minDelayMs;
      await _sleep(settings.minDelayMs + (span > 0 ? _rng.nextInt(span + 1) : 0));
    }

    if (statusText.startsWith('Menghapus')) {
      statusText = _cancel
          ? 'Dihentikan'
          : 'Selesai: $removedSession dihapus, $failedSession gagal';
    }
    _finish();
  }

  void togglePause() {
    if (phase == Phase.removing) {
      _paused = true;
      phase = Phase.paused;
      statusText = 'Dijeda';
    } else if (phase == Phase.paused) {
      _paused = false;
      phase = Phase.removing;
    }
    notifyListeners();
  }

  void stop() {
    _cancel = true;
    _paused = false;
    notifyListeners();
  }

  // ------------------------------------------------------------ selection
  void toggle(String id) {
    if (!selected.remove(id)) selected.add(id);
    notifyListeners();
  }

  void selectAll(bool on) {
    selected.clear();
    if (on) {
      selected.addAll(reposts
          .where((r) => r.state != RepostState.removed)
          .map((r) => r.id));
    }
    notifyListeners();
  }

  /// Semua kriteria yang diisi harus cocok (AND).
  void applyFilter({
    DateTime? olderThan,
    int? keepNewest,
    String keyword = '',
    String creator = '',
  }) {
    selected.clear();
    for (var i = 0; i < reposts.length; i++) {
      final r = reposts[i];
      if (r.state == RepostState.removed) continue;
      if (keepNewest != null && i < keepNewest) continue;
      if (olderThan != null && !r.createdAt.isBefore(olderThan)) continue;
      if (keyword.isNotEmpty &&
          !r.desc.toLowerCase().contains(keyword.toLowerCase())) continue;
      if (creator.isNotEmpty &&
          !r.author.toLowerCase().contains(creator.toLowerCase().replaceAll('@', ''))) {
        continue;
      }
      selected.add(r.id);
    }
    notifyListeners();
  }
}
