# cmkagent v1.3.3 - Stable Release

> **Catatan Rilis v1.3.3 Stable:** 
> - **Kalkulasi Baterai Riil (Hardware-Accurate):** Menghapus baseline sintetis dan menghitung kapasitas muatan secara dinamis berdasarkan data register kernel nyata (`chargeCounterMah / (level / 100)`), sehingga mencegah kesalahan status degradasi pada perangkat baru.
> - **Kalibrasi Kapasitas Penuh (Full Charge):** Merekam otomatis nilai kapasitas riil dan tegangan *cut-off* puncak (~4.35 V – 4.40 V) saat perangkat terisi 100% atau berstatus `Full` pada *docking charger/cradle*.
> - **Metrik Siklus Pengisian (Cycle Count) Terpadu:** Membaca akumulasi siklus pengisian menggunakan metode ganda (API Android 14+ via konstanta ID `7` dan *fallback* berkas kernel `sysfs` untuk Newland MT93).
> - **Proteksi Anti-Crash (`SecurityException`):** Membungkus seluruh pemanggilan register baterai dengan proteksi *exception* menyeluruh agar aplikasi tidak mengalami *force close* saat dijalankan pada sistem operasi Android modern.
> - **Penyatuan Service `Health_Battery`:** Menggabungkan persentase kesehatan riil, jumlah siklus, kapasitas desain pabrik, kapasitas penuh, dan tegangan puncak ke dalam satu baris service Checkmk dengan grafik ganda (*perfdata*).
> - **Kompatibilitas Foreground Service:** Menggunakan `targetSdk 33` untuk menjamin stabilitas *background listener* pada Android 14 hingga 16 tanpa bentrok perizinan *foreground service type*.

Agen monitoring Android native untuk Checkmk Community.

- **Package:** `com.bcp.checkmkagent`[cite: 5, 6, 10]
- **Nama Aplikasi:** `cmkagent`
- **Versi:** `1.3.3` (Stable)[cite: 6, 13]
- **Target SDK:** Android SDK 35 (Compile), Android SDK 33 (Target), Android SDK 26 (Minimum)
- **Lingkungan Build:** Java 17 + Gradle
- **Transport Utama:** Checkmk PULL melalui TCP/6556
- **Transport Cadangan:** HTTP/HTTPS PUSH ke receiver cache
- **Target Utama Armada:** Newland MT93 (Kapasitas desain standar 4.800 mAh) & Android Generic

---

## Arsitektur Hybrid Transport

`cmkagent` menjalankan listener lokal pada TCP/6556 untuk melayani tarikan data berkala dari server Checkmk (PULL). 

Ketika mode backup PUSH diaktifkan dan URL Receiver telah dikonfigurasi, *foreground service* agen juga akan mengirimkan salinan metrik yang sama secara berkala ke endpoint HTTP/HTTPS sebagai redundansi data.

```text
Checkmk Server ---- PULL TCP/6556 ----> Android cmkagent (Newland MT93)
                                            |
                                            +---- PUSH HTTP(S) ----> Receiver Cache
Mekanisme failover di sisi server Checkmk:   
MD

Mencoba koneksi PULL TCP/6556 terlebih dahulu.   
MD

Jika PULL gagal (misal PDA tertidur atau roaming jaringan), server beralih membaca cache PUSH terbaru.   
MD

Jika kedua jalur tidak dapat dihubungi atau data cache telah kedaluwarsa, host dinyatakan Down/Unavailable.   
MD

Logika Pemantauan Baterai
1. Spesifikasi Hardware Newland MT93
Sistem mengenali profil perangkat keras Newland MT93 secara otomatis dan menetapkan nilai rancangan paten sebesar 4.800 mAh. Nilai ini dapat disesuaikan secara manual melalui menu Settings jika menggunakan modul baterai berkapasitas lain.   
JAVA
+ 2

2. Penghitungan Kapasitas & Kesehatan Nyata
Kondisi Normal / Discharging: Muatan saat ini diekstrapolasikan secara dinamis (chargeCounterMah / (level / 100)). Pada level 61% dengan sisa muatan 2.946 mAh, kapasitas penuh terbaca tepat pada ~4.829 mAh (Health 100.6% OK), meniadakan false alarm 61.4% yang muncul pada versi lama.   
JAVA
+ 1

Kondisi 100% Penuh (Full Charger): Saat PDA diletakkan di cradle hingga mencapai 100% atau berstatus Full, agen langsung mencatat kapasitas fisik penuh dan tegangan cut-off baterai (~4.35 V – 4.40 V) ke penyimpanan lokal.   
JAVA

3. Deteksi Siklus Baterai (Cycle Count)
Agen membaca riwayat siklus baterai melalui dua lapisan:   
JAVA

API Android 14+: Mengakses register integer konstanta 7 tanpa dependensi variabel SDK yang rentan kegagalan build.   
JAVA

Kernel Sysfs Direct Read: Membaca berkas sistem /sys/class/power_supply/battery/cycle_count atau node bms/cycle_count untuk perangkat Android versi industri (Newland MT93)[cite: 5].

Daftar Service Checkmk
Service Real-Time (Setiap Tarikan PULL)
Agent_Status: Menampilkan statistik koneksi diterima/ditolak, port TCP, waktu pull terakhir, dan filter IP server yang diizinkan.   
JAVA

Battery_Level: Level daya baterai (%) dan status pengisian (Charging, Discharging, Full).   
JAVA
+ 1

Health_Battery: Ringkasan kesehatan fisik baterai terpadu dalam satu baris:   
JAVA

Plaintext
Status : OK | Real Health : 100.2% | Cycles : 15 | Full Capacity : 4810 mAh | Design Spec : 4800 mAh | Full Voltage : 4.38 V | Current Charge : 4810 mAh | Calculation : Direct Measurement @ 100% Full Charge
Ambang Evaluasi:

OK: Health ≥ 80% dan Cycles < 500   
JAVA

WARN: Health < 80% atau Cycles ≥ 500   
JAVA

CRIT: Health < 65% atau Cycles ≥ 800   
JAVA

RAM_Usage: Persentase pemakaian memori, memori terpakai, memori bebas, dan kapasitas total RAM.   
JAVA
+ 1

WiFi_Status: Kekuatan sinyal Wi-Fi (dBm), kecepatan tautan (Link Speed), frekuensi saluran (MHz), IP lokal, dan status konektivitas[cite: 5, 6].

Android_Info: Produsen perangkat, model, versi Android, level SDK, profil perangkat keras, dan waktu aktif (uptime)[cite: 5, 6].

Service Terjadwal (Local Cache)
Untuk menghemat pemakaian baterai dan sumber daya CPU pada PDA operasional, metrik berikut dibaca secara berkala melalui sistem cache:   
JAVA
+ 1

Battery_Temperature: Diperbarui setiap 30 menit (Threshold: WARN ≥ 42°C, CRIT ≥ 48°C).   
JAVA

Battery_Current: Diperbarui setiap 1 jam (Arus instan dan rata-rata penyerapan/pengeluaran daya).   
JAVA

Transport_Status: Diperbarui setiap 3 jam (Status jalur PUSH HTTP backup, respons kode HTTP, dan rasio keberhasilan).   
JAVA
+ 1

Battery_Voltage: Diperbarui setiap 24 jam (Tegangan kerja baterai saat ini)[cite: 6].

Storage_Usage: Diperbarui setiap 24 jam (Persentase kapasitas memori internal yang terpakai)[cite: 5, 6].

Konfigurasi Aplikasi (Menu Settings)
Parameter yang dapat dikonfigurasi melalui kartu SETTINGS pada aplikasi[cite: 10, 13]:

Hostname: Pengenal perangkat yang diselaraskan dengan nama host di Checkmk.   
JAVA
+ 1

Pull TCP Port: Port listener (standar: 6556).   
JAVA
+ 1

Allowed Checkmk Server IP: Membatasi akses listener PULL hanya dari IP server tertentu[cite: 6, 10].

Battery Design Capacity: Nilai kapasitas desain baterai dalam satuan mAh (bawaan Newland MT93: 4800)[cite: 5, 10].

Aktifkan Backup PUSH: Mengaktifkan pengiriman metrik cadangan melalui protokol HTTP/HTTPS[cite: 6, 10].

Push Receiver URL: Alamat URL endpoint penerima cache PUSH[cite: 6, 10].

Push Token: Token otentikasi Bearer untuk keamanan pengiriman data.   
MD

Push Interval: Interval waktu siklus pengiriman PUSH (minimal 60 detik; standar: 300 detik)[cite: 6, 10].

Auto Start After Boot: Menjalankan agen secara otomatis saat perangkat selesai dihidupkan.   
MD

Rekomendasi konfigurasi server operasional:

Plaintext
Allowed Checkmk Server IP : 192.168.55.112
Push Receiver URL         : [http://192.168.55.112:18080/api/v1/agent](http://192.168.55.112:18080/api/v1/agent)
Push Interval             : 300
Design Capacity (mAh)     : 4800
Panduan Stabilitas Background Service pada PDA
Agar service agen tidak dihentikan secara sepihak oleh manajemen daya agresif Android saat layar perangkat padam:

Masuk ke Pengaturan Android → Aplikasi → Kelola Aplikasi → pilih cmkagent.

Aktifkan opsi Mulai Otomatis / Autostart.

Buka menu Penghemat Baterai (Battery Saver) dan ubah opsinya menjadi Tidak ada batasan (No restrictions).

Buka aplikasi cmkagent, masuk ke section SETTINGS, lalu tekan SAVE & START AGENT hingga kartu AGENT berstatus hijau RUNNING[cite: 13].

Catatan Instalasi Pembaruan: Jika muncul pesan "Aplikasi tidak diinstal karena paket ini bentrok dengan paket yang sudah ada", copot pemasangan (uninstall) aplikasi versi lama terlebih dahulu sebelum memasang APK v1.3.3 hasil build GitHub Actions.   
JPG

Kompilasi & Build (GitHub Actions)
Proses build berjalan otomatis melalui GitHub Actions setiap kali terjadi pembaruan pada direktori android/**[cite: 10].

Berkas artefak rilis stabil yang dihasilkan:

Plaintext
cmkagent-v1.3.3
└── cmkagent-v1.3.3.apk
Dibuat oleh IT OPS HQEJBNT

[cite: 10]
