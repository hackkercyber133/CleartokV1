enum RepostState { pending, removed, failed }

class Repost {
  final String id;
  final String author;
  final String url;
  final String desc;
  final String thumb;
  RepostState state = RepostState.pending;

  Repost({
    required this.id,
    required this.author,
    required this.url,
    required this.desc,
    required this.thumb,
  });

  /// ID video TikTok menyimpan waktu pembuatan di 32 bit teratas (detik unix).
  /// Ini tanggal VIDEO dibuat, bukan waktu kamu me-repost.
  DateTime get createdAt {
    try {
      final secs = (BigInt.parse(id) >> 32).toInt();
      return DateTime.fromMillisecondsSinceEpoch(secs * 1000);
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  int get year => createdAt.year;
}

class Account {
  final String username;
  final String nickname;
  const Account({required this.username, required this.nickname});
}

class Settings {
  int minDelayMs = 2500;
  int maxDelayMs = 6000;

  /// 0 = tanpa batas harian.
  int dailyLimit = 0;
}
