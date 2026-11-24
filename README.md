# ClearRepost (Flutter, Android)

Penghapus repost TikTok massal, tanpa batas harian bawaan.

## Cara pasang
```bash
flutter create --org com.ady --project-name clear_repost .
# timpa pubspec.yaml dan folder lib/ dengan yang ada di sini
flutter pub get
flutter run
```
Pastikan `android/app/src/main/AndroidManifest.xml` punya:
```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

## Cara kerja
1. **Login**: WebView membuka tiktok.com/login. Pilih *QR code* lalu scan dengan aplikasi TikTok
   (login Google biasanya diblokir di WebView). Password tidak pernah disimpan.
2. **Pindai**: buka profil -> tab Repost -> scroll otomatis, kumpulkan semua video.
3. **Pilih**: semua terpilih; filter lewat tanggal video, N terbaru, kata kunci, kreator.
4. **Hapus**: buka tiap video, klik "Remove repost", jeda acak, backoff saat gagal,
   jeda otomatis kalau captcha muncul.

## Yang harus dicek saat uji pertama
Selector TikTok ada di `lib/tiktok_js.dart` (`SELECTORS`, `REMOVE`, `clickRepostTab`).
Kalau status "remove-button-not-found", buka `chrome://inspect` di Chrome PC,
inspeksi WebView, lalu sesuaikan selector.
