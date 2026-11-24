import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'app_state.dart';
import 'models.dart';
import 'settings_page.dart';

const _purple = Color(0xFF8B7CF6);
const _purpleLight = Color(0xFFC9C0FF);
const _card = Color(0xFF141414);

class HomePage extends StatelessWidget {
  final AppState s;
  const HomePage({super.key, required this.s});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final mq = MediaQuery.of(context);
        final size = mq.size;
        final captcha = s.browser == BrowserMode.captcha;
        final login = s.browser == BrowserMode.full;

        // "Lubang" tempat WebView terlihat. null = WebView disembunyikan di
        // belakang UI (tetap berjalan normal, hanya tertutup).
        Rect? hole;
        if (login) {
          hole = Rect.fromLTRB(
              0, mq.padding.top + 48, size.width, size.height - mq.padding.bottom);
        } else if (captcha) {
          hole = Rect.fromLTRB(12, mq.padding.top + 72, size.width - 12,
              size.height - mq.padding.bottom - 24);
        }
        final radius = captcha ? 16.0 : 0.0;

        return Stack(
          children: [
            // Lapisan bawah: WebView selalu ada & berukuran penuh.
            Positioned.fill(child: WebViewWidget(controller: s.web)),

            // UI aplikasi di atasnya (dilubangi saat login/captcha).
            Positioned.fill(
              child: ClipPath(
                clipper: _HoleClipper(hole, radius),
                child: Scaffold(
                  body: SafeArea(
                    child: Column(
                      children: [
                        Expanded(child: _content(context)),
                        _bottomBar(context),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            if (hole != null) ...[
              Positioned.fill(
                child: ClipPath(
                  clipper: _HoleClipper(hole, radius),
                  child: const ColoredBox(color: Color(0xB3000000)),
                ),
              ),
              Positioned(
                left: hole.left,
                width: hole.width,
                top: hole.top - 48,
                height: 48,
                child: Material(
                  color: _card,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            captcha
                                ? 'Selesaikan captcha — otomatis lanjut'
                                : 'Login TikTok',
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (login) ...[
                          TextButton(
                              onPressed: () => s.confirmLogin(),
                              child: const Text('Saya sudah login')),
                          TextButton(
                              onPressed: s.cancelLogin, child: const Text('Batal')),
                        ],
                        if (captcha)
                          TextButton(onPressed: s.stop, child: const Text('Berhenti')),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned.fromRect(
                rect: hole,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(radius),
                      border: captcha ? Border.all(color: _purple, width: 2) : null,
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  // ------------------------------------------------------------ content
  Widget _content(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _header(context)),
        SliverToBoxAdapter(child: _counter(context)),
        SliverToBoxAdapter(child: _accountSection(context)),
        SliverToBoxAdapter(child: _todayCard(context)),
        SliverToBoxAdapter(child: _listHeader(context)),
        SliverList.builder(
          itemCount: s.reposts.length,
          itemBuilder: (_, i) => _RepostTile(r: s.reposts[i], s: s),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  Widget _header(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 16, 0),
        child: Row(
          children: [
            const Expanded(
              child: Text('ClearRepost',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.w600)),
            ),
            IconButton.filledTonal(
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => SettingsPage(s: s))),
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ),
      );

  Widget _counter(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Column(
          children: [
            Text('${s.reposts.length}',
                style: const TextStyle(
                    fontSize: 96, fontWeight: FontWeight.w800, color: _purpleLight, height: 1.1)),
            Text(s.statusText,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _purple, fontSize: 16)),
            if (s.lastDiag != null)
              TextButton(
                onPressed: () => _showDiag(context),
                child: const Text('Lihat diagnostik'),
              ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(24)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check, size: 18),
                  const SizedBox(width: 8),
                  Text('${s.removedSession} dibersihkan'),
                ],
              ),
            ),
          ],
        ),
      );

  void _showDiag(BuildContext context) {
    final text = s.lastDiag ?? '';
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Diagnostik'),
        content: SingleChildScrollView(
          child: SelectableText(text, style: const TextStyle(fontSize: 11)),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              Navigator.pop(c);
            },
            child: const Text('Salin'),
          ),
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Tutup')),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
        child: Text(t, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
      );

  Widget _accountSection(BuildContext context) {
    final a = s.account;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Akun'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: s.busy
                ? null
                : () => a == null ? s.startLogin() : _confirmLogout(context),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white12),
              ),
              child: a == null
                  ? const Row(children: [
                      Icon(Icons.login, color: _purple),
                      SizedBox(width: 14),
                      Expanded(
                          child: Text('Masuk dengan TikTok',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
                      Icon(Icons.chevron_right),
                    ])
                  : Row(children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: _purple,
                        child: Text(a.nickname.substring(0, 1).toUpperCase(),
                            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(a.nickname,
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                            Row(children: [
                              const Icon(Icons.circle, size: 10, color: Colors.green),
                              const SizedBox(width: 8),
                              Text('@${a.username}',
                                  style: const TextStyle(color: Colors.white60, fontSize: 16)),
                            ]),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ]),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Keluar dari akun?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Keluar')),
        ],
      ),
    );
    if (ok == true) await s.logout();
  }

  Widget _todayCard(BuildContext context) {
    final limit = s.settings.dailyLimit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Hari Ini'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(TextSpan(children: [
                        TextSpan(
                            text: '${s.removedToday}',
                            style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w700)),
                        TextSpan(
                            text: limit == 0 ? ' / ∞' : ' / $limit',
                            style: const TextStyle(
                                fontSize: 44, fontWeight: FontWeight.w700, color: _purple)),
                      ])),
                      Text(limit == 0 ? 'Tanpa batas harian' : 'Batas harian',
                          style: const TextStyle(color: Colors.white60, fontSize: 16)),
                    ],
                  ),
                ),
                FilledButton.tonal(
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => SettingsPage(s: s))),
                  child: const Text('Atur'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _listHeader(BuildContext context) {
    final allOn = s.reposts.isNotEmpty && s.selected.length == s.reposts.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 16, 8),
      child: Row(
        children: [
          const Expanded(
            child: Text('Repost Anda',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          ),
          IconButton.filledTonal(
            onPressed: s.reposts.isEmpty || s.busy ? null : () => _openFilter(context),
            icon: const Icon(Icons.filter_alt_outlined),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: s.reposts.isEmpty || s.busy ? null : () => s.selectAll(!allOn),
            child: Text('${s.selected.length} dipilih'),
          ),
        ],
      ),
    );
  }

  void _openFilter(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _card,
      builder: (_) => _FilterSheet(s: s),
    );
  }

  // ------------------------------------------------------------ bottom
  Widget _bottomBar(BuildContext context) {
    Widget btn(String label, VoidCallback? onTap, {IconData? icon}) => Expanded(
          child: SizedBox(
            height: 64,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _purple,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
              ),
              onPressed: onTap,
              icon: Icon(icon ?? Icons.play_arrow),
              label: Text(label, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            ),
          ),
        );

    Widget child;
    if (s.phase == Phase.removing || s.phase == Phase.paused) {
      child = Row(children: [
        btn(s.phase == Phase.paused ? 'Lanjut' : 'Jeda', s.togglePause,
            icon: s.phase == Phase.paused ? Icons.play_arrow : Icons.pause),
        const SizedBox(width: 10),
        btn('Berhenti', s.stop, icon: Icons.stop),
      ]);
    } else if (s.phase == Phase.scanning) {
      child = Row(children: [btn('Batalkan pindai', s.stop, icon: Icons.close)]);
    } else if (s.account == null) {
      child = Row(children: [
        btn('Masuk TikTok', s.phase == Phase.loggingIn ? null : s.startLogin, icon: Icons.login)
      ]);
    } else if (s.reposts.isEmpty) {
      child = Row(children: [btn('Pindai Repost', s.scan, icon: Icons.search)]);
    } else {
      child = Row(children: [
        btn('Hapus ${s.selected.length} Repost',
            s.selected.isEmpty ? null : s.removeSelected,
            icon: Icons.delete_outline),
        const SizedBox(width: 10),
        SizedBox(
          height: 64,
          child: IconButton.filledTonal(onPressed: s.scan, icon: const Icon(Icons.refresh)),
        ),
      ]);
    }
    return Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 12), child: child);
  }
}

// ---------------------------------------------------------------- tile
class _RepostTile extends StatelessWidget {
  final Repost r;
  final AppState s;
  const _RepostTile({required this.r, required this.s});

  @override
  Widget build(BuildContext context) {
    final on = s.selected.contains(r.id);
    final done = r.state == RepostState.removed;
    final failed = r.state == RepostState.failed;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Opacity(
        opacity: done ? 0.4 : 1,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: s.busy || done ? null : () => s.toggle(r.id),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: failed ? Colors.redAccent : Colors.white12),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child: r.thumb.isEmpty
                        ? const ColoredBox(color: Colors.white10)
                        : Image.network(r.thumb,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const ColoredBox(color: Colors.white10)),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Flexible(
                          child: Text('@${r.author}',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 10),
                        Text('${r.year}', style: const TextStyle(color: Colors.white54)),
                      ]),
                      const SizedBox(height: 4),
                      Text(
                        done ? 'Sudah dihapus' : (failed ? 'Gagal dihapus' : r.desc),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white60),
                      ),
                    ],
                  ),
                ),
                Icon(
                  done
                      ? Icons.check_circle
                      : (on ? Icons.check_circle : Icons.radio_button_unchecked),
                  color: on || done ? _purple : Colors.white30,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- filter
class _FilterSheet extends StatefulWidget {
  final AppState s;
  const _FilterSheet({required this.s});

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  DateTime? olderThan;
  final keep = TextEditingController();
  final keyword = TextEditingController();
  final creator = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Pilih repost', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text('Semua kriteria yang diisi harus cocok.',
              style: TextStyle(color: Colors.white54)),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            icon: const Icon(Icons.event),
            label: Text(olderThan == null
                ? 'Video lebih lama dari tanggal…'
                : 'Video sebelum ${olderThan!.day}/${olderThan!.month}/${olderThan!.year}'),
            onPressed: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: DateTime.now(),
                firstDate: DateTime(2016),
                lastDate: DateTime.now(),
              );
              if (d != null) setState(() => olderThan = d);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: keep,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Pertahankan N repost terbaru'),
          ),
          TextField(
            controller: keyword,
            decoration: const InputDecoration(labelText: 'Mengandung kata kunci'),
          ),
          TextField(
            controller: creator,
            decoration: const InputDecoration(labelText: 'Dari kreator (@username)'),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _purple),
              onPressed: () {
                widget.s.applyFilter(
                  olderThan: olderThan,
                  keepNewest: int.tryParse(keep.text),
                  keyword: keyword.text.trim(),
                  creator: creator.text.trim(),
                );
                Navigator.pop(context);
              },
              child: const Text('Terapkan'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Memotong seluruh layar kecuali sebuah "lubang" (agar WebView di bawahnya terlihat
/// dan bisa disentuh). Tanpa lubang = seluruh layar.
class _HoleClipper extends CustomClipper<Path> {
  final Rect? hole;
  final double radius;
  _HoleClipper(this.hole, this.radius);

  @override
  Path getClip(Size size) {
    final p = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size);
    final h = hole;
    if (h != null) {
      p.addRRect(RRect.fromRectAndRadius(h, Radius.circular(radius)));
    }
    return p;
  }

  @override
  bool shouldReclip(_HoleClipper old) => old.hole != hole || old.radius != radius;
}
