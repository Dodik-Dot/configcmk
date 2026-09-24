# cmkagent v1.3.2 - Hybrid Preview

> **Perbaikan compile:** v1.3.2 menghapus referensi non-public `WifiInfo.INVALID_RSSI` agar project dapat di-compile dengan baik menggunakan Android SDK 35. Validasi Wi-Fi sekarang menggunakan pemeriksaan rentang RSSI lokal (`-126..0 dBm`).

Agen monitoring Android native untuk Checkmk Community.

- Package: `com.bcp.checkmkagent`
- Nama aplikasi: `cmkagent`
- Versi: `1.3.2`
- Build: Java 17 + Android SDK + Gradle
- Transport utama: Checkmk PULL melalui TCP/6556
- Transport cadangan: HTTP/HTTPS PUSH ke receiver yang dapat dikonfigurasi
- Target PDA produksi: Newland MT93 (Android generic juga tetap didukung)

## Cara Kerja Hybrid

`cmkagent` tetap menjalankan listener pull Checkmk Community pada TCP/6556. Jalur PULL tetap menjadi jalur monitoring utama.

Jika backup PUSH diaktifkan dan Receiver URL sudah dikonfigurasi, foreground service juga akan mengirim output agent Checkmk yang sama secara berkala ke receiver. Dengan demikian receiver menyimpan salinan terbaru dari data agent sebagai backup.

```text
Checkmk Community ---- PULL TCP/6556 ----> Android cmkagent
                                             |
                                             +---- PUSH HTTP(S) ----> receiver cache
```

Aplikasi Android tidak menentukan kapan Checkmk harus menggunakan data backup. Nantinya program data source di sisi server akan menjalankan logika berikut:

1. mencoba PULL terlebih dahulu;
2. jika PULL gagal, membaca cache PUSH terbaru;
3. jika keduanya tidak tersedia atau cache sudah terlalu lama, host dilaporkan tidak tersedia.

## Pengaturan Android

Card **SETTINGS** memiliki pengaturan berikut:

- Hostname
- Pull TCP port (default 6556)
- Allowed Checkmk Server IP
- Battery Design Capacity
- Aktifkan backup PUSH
- Push Receiver URL
- Push Token
- Push Interval (minimum 60 detik; default 300 detik)
- Auto start setelah boot
- Tombol `TEST PUSH NOW`

Rekomendasi konfigurasi pengujian untuk server OMV saat ini:

```text
Allowed Checkmk Server IP : 192.168.55.112
Push Receiver URL          : http://192.168.55.112:18080/api/v1/agent
Push Interval              : 300
```

Untuk penggunaan produksi, gunakan HTTPS. HTTP pada versi preview ini hanya ditujukan untuk mempermudah pengujian transport di jaringan LAN internal.

## Service Checkmk

Semua metrik Android yang sudah ada tetap dipertahankan. Pada v1.3.2 ditambahkan service:

- `Transport_Status`

`Transport_Status` menampilkan:

- port PULL utama;
- alamat receiver PUSH;
- interval push;
- waktu push terakhir;
- HTTP response code terakhir;
- jumlah push berhasil dan gagal.

## Tampilan UI Ringkas

UI accordion/dropdown tetap digunakan agar tampilan aplikasi tidak terlalu panjang. Semua section dapat dibuka dan ditutup dengan menekan card terkait.

Card yang tersedia:

- AGENT
- HYBRID TRANSPORT
- BATTERY
- SYSTEM
- NETWORK
- DEVICE
- SETTINGS
- DIAGNOSTICS

Secara default section dibuat dalam kondisi collapsed agar tampilan lebih ringkas. Gunakan tombol `EXPAND ALL` atau `COLLAPSE ALL` jika ingin membuka atau menutup semua section sekaligus.

## Receiver untuk Pengujian

ZIP menyertakan `server-test/receiver.py`, yaitu endpoint pengujian berbasis Python standard library. Receiver ini digunakan untuk menguji fungsi PUSH dari Android dan belum melakukan integrasi cache secara otomatis ke Checkmk.

Jalankan di host OMV:

```bash
python3 receiver.py   --listen 0.0.0.0   --port 18080   --data-dir ./push-cache   --token cmk-test-token
```

Kemudian atur APK:

```text
Push Receiver URL : http://192.168.55.112:18080/api/v1/agent
Push Token        : cmk-test-token
Push Interval     : 300
```

Tekan **TEST PUSH NOW**. Jika menerima HTTP 200, berarti jalur transport PUSH berhasil.

## Build Menggunakan GitHub Actions

Copy/replace folder `android/` dan file `.github/workflows/build-cmkagent.yml` pada repository `configcmk`.

Perubahan atau push yang memengaruhi `android/**` akan menjalankan workflow build secara otomatis.

Artifact yang dihasilkan:

```text
cmkagent-v1.3.2-debug
└── cmkagent-v1.3.2-debug.apk
```

## Catatan Keamanan

Versi ini merupakan hybrid preview untuk pengujian pada jaringan internal.

- Akses PULL dapat dibatasi hanya dari `192.168.55.112`.
- PUSH mendukung autentikasi menggunakan Bearer token.
- Token saat ini disimpan di Android SharedPreferences. Untuk hardening produksi, token dapat dipindahkan ke Android Keystore.
- Gunakan HTTPS untuk production.
- Test receiver belum ditujukan sebagai service production.

## Rekomendasi Resource dan Interval

- PULL tetap menjadi jalur utama dan mengikuti interval Checkmk, umumnya sekitar 60 detik.
- PUSH backup default 300 detik untuk mengurangi wake-up jaringan pada PDA yang digunakan sepanjang hari.
- Listener TCP menggunakan blocking `ServerSocket.accept()` sehingga penggunaan CPU sangat kecil saat idle.
- Aplikasi tidak melakukan scanning berat secara terus-menerus. Metrik dibaca saat ada PULL atau ketika jadwal PUSH berjalan.
- Untuk Newland MT93 dengan RAM 4 GB, verifikasi penggunaan aktual menggunakan Android Settings atau perintah:

```bash
adb shell dumpsys meminfo com.bcp.checkmkagent
```

## UI

Semua section menggunakan accordion/dropdown dan secara default berada dalam kondisi collapsed agar layar tidak terlalu panjang. Tekan section untuk membuka atau menutup detail.

---

**Dibuat oleh IT OPS HQEJBNT**
