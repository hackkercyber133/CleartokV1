import 'package:flutter/material.dart';

import 'app_state.dart';

class SettingsPage extends StatefulWidget {
  final AppState s;
  const SettingsPage({super.key, required this.s});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late double minSec = widget.s.settings.minDelayMs / 1000;
  late double maxSec = widget.s.settings.maxDelayMs / 1000;
  late bool unlimited = widget.s.settings.dailyLimit == 0;
  late final TextEditingController limitCtl = TextEditingController(
      text: widget.s.settings.dailyLimit == 0
          ? '1000'
          : '${widget.s.settings.dailyLimit}');

  void _save() {
    widget.s.updateSettings(
      minMs: (minSec * 1000).round(),
      maxMs: (maxSec * 1000).round(),
      limit: unlimited ? 0 : (int.tryParse(limitCtl.text) ?? 1000),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Tanpa batas harian'),
            subtitle: const Text('Aplikasi tidak membatasi jumlah hapus per hari'),
            value: unlimited,
            onChanged: (v) {
              setState(() => unlimited = v);
              _save();
            },
          ),
          if (!unlimited)
            TextField(
              controller: limitCtl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Batas harian'),
              onChanged: (_) => _save(),
            ),
          const SizedBox(height: 24),
          Text('Jeda minimum: ${minSec.toStringAsFixed(1)} detik'),
          Slider(
            min: 0.5,
            max: 20,
            value: minSec,
            onChanged: (v) => setState(() {
              minSec = v;
              if (maxSec < minSec) maxSec = minSec;
            }),
            onChangeEnd: (_) => _save(),
          ),
          Text('Jeda maksimum: ${maxSec.toStringAsFixed(1)} detik'),
          Slider(
            min: 0.5,
            max: 30,
            value: maxSec,
            onChanged: (v) => setState(() {
              maxSec = v < minSec ? minSec : v;
            }),
            onChangeEnd: (_) => _save(),
          ),
          const SizedBox(height: 8),
          const Text(
            'Jeda acak antar penghapusan menjaga akun tidak dianggap bot. '
            'Jeda terlalu singkat meningkatkan risiko pembatasan sementara dari TikTok.',
            style: TextStyle(color: Colors.white54),
          ),
        ],
      ),
    );
  }
}
