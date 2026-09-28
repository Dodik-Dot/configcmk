# cmkagent v1.3.3 - Stable Release

> **Catatan Rilis v1.3.3 Stable:** 
> - **Kalkulasi Baterai Riil (Hardware-Accurate):** Menghapus seluruh baseline buatan (*fake baseline*) dan menerapkan ekstrapolasi muatan matematis langsung dari register kernel fisik (`chargeCounterMah / (level / 100)`) sehingga menghilangkan false alert degradasi kapasitas.
> - **Kalibrasi Kapasitas Penuh (Full Charge):** Menyimpan otomatis kapasitas muatan riil dan tegangan cut-off puncak (~4.35 V – 4.40 V) saat PDA mencapai 100% atau status `Full` di docking cradle.
> - **Metrik Siklus Pengisian (Cycle Count) Terpadu:** Membaca jumlah siklus pengisian baterai menggunakan metode ganda: konstanta ID `7` (Android 14+) dan *fallback* berkas kernel `sysfs` Newland MT93.
> - **Proteksi Penuh Anti-Crash (`SecurityException`):** Membungkus seluruh akses register hardware dengan blok pengaman *exception* menyeluruh (`try-catch Throwable`) agar terhindar dari *force close* pada Android 14 hingga 16.
> - **Penyatuan Baris Service `Health_Battery`:** Menyatukan persentase kesehatan riil, siklus, kapasitas desain pabrik, kapasitas penuh, tegangan puncak, dan muatan saat ini ke dalam satu baris service Checkmk dengan grafik ganda (*perfdata*).
> - **Stabilitas Foreground Service:** Menggunakan `targetSdk 33` guna menjamin keandalan *background listener* pada Android 14/16 tanpa kendala deklarasi hak akses `foregroundServiceType`.

Agen monitoring Android native untuk Checkmk Community.

- **Package:** `com.bcp.checkmkagent`[cite: 1, 2, 15]
- **Nama Aplikasi:** `cmkagent`
- **Versi:** `1.3.3` (Stable Release)
- **Target SDK:** Android SDK 35 (Compile), Android SDK 33 (Target), Android SDK 26 (Minimum)
- **Lingkungan Build:** Java 17 + Gradle 8.9
- **Transport Utama:** Checkmk PULL melalui TCP/6556
- **Transport Cadangan:** HTTP/HTTPS PUSH ke receiver cache
- **Target Armada Produksi:** Newland MT93 (Spesifikasi paten baterai 4.800 mAh) & Android Generic

---

## 1. Arsitektur Agen & Aliran Data

```text
+-----------------------------------------------------------------------------------+
|                            cmkagent v1.3.3 Architecture                           |
+-----------------------------------------------------------------------------------+
|  [Hardware Layer: Newland MT93 / Android OS]                                      |
|        │                                                                          |
|        ├──> Kernel Sysfs Nodes (/sys/class/power_supply/...)                      |
|        ├──> Android BatteryManager API (Charge Counter, Arus, Siklus)             |
|        ├──> ConnectivityManager & LinkProperties (Wi-Fi, RSSI, IP, Frequency)     |
|        └──> Linux StatFs & ActivityManager (Storage & RAM Usage)                  |
|                                                                                   |
|  [Processing Engine: DeviceMetrics.java]                                          |
|        │                                                                          |
|        ├──> Ekstrapolasi Baterai Riil: Charge / (Level / 100)                     |
|        ├──> Validasi Jangkauan RSSI: Rentang -126 dBm s.d. 0 dBm                  |
|        └──> Anti-Crash Safety Wrapper (Proteksi Penuh Exception)                  |
|                                                                                   |
|  [Checkmk Formatter: CheckmkOutput.java]                                          |
|        │                                                                          |
|        ├──> Real-time Service (Agent_Status, Health_Battery, WiFi_Status, dll)    |
|        └──> Cached Service (Temp: 30m, Current: 1h, Transport: 3h, Volt/Disk: 24h)|
+-----------------------------------------------------------------------------------+

2. Logika Pemantauan & Perhitungan MetrikA. Metrik Baterai Terpadu (Health_Battery)Metrik ini memantau kesehatan fisik baterai secara presisi guna mendeteksi baterai kembung, drop, atau penurunan kapasitas sel sebelum mengganggu kegiatan operasional barcode scanning di gudang.   Spesifikasi Hardware Pabrik (Design Spec):Sistem secara otomatis mengenali identitas hardware Newland MT93 dan menetapkan nilai rancangan kapasitas pabrik mutlak sebesar 4.800 mAh (bukan 5.000 mAh seperti estimasi profil generik Android). Nilai ini menjadi angka dasar pembagi dalam kalkulasi kesehatan.   Kalkulasi Kapasitas Penuh Riil (Full Capacity):Mode Operasional Berjalan (Dynamic Real-Time):Saat baterai berada pada kondisi penggunaan normal (misal 61%), agen mengambil register muatan listrik aktual dari pengontrol baterai (chargeCounterMah, misal 2.946 mAh). Nilai kapasitas penuh diekstrapolasikan secara linier:
   $$\text{Full Capacity} = \frac{\text{Muatan Aktual (mAh)}}{\text{Level Baterai} / 100}$$
Contoh: $\frac{2946}{0.61} \approx 4829\text{ mAh}$ (Health 100.6% OK). Hal ini meniadakan pembacaan keliru versi terdahulu yang sempat mendeteksi degradasi palsu 61.4%.   Mode Kalibrasi Penuh (Direct Measurement @ 100% Full Charge):Ketika PDA di-docking hingga mencapai level 100% atau berstatus Full, agen langsung membaca kapasitas puncak fisik dan nilai tegangan cut-off (~4.35 V – 4.40 V), lalu menyimpannya ke SharedPreferences sebagai tolok ukur kalibrasi hardware yang valid.   Persentase Kesehatan Baterai (Real Health):$$\text{Health Percent (\%)} = \left(\frac{\text{Full Capacity}}{\text{Design Capacity (4800 mAh)}}\right) \times 100$$Deteksi Siklus Baterai (Cycles):Akumulasi siklus pengosongan-pengisian dibaca lewat dua jalur:   API Android 14+: Mengakses register integer ID 7 (BATTERY_PROPERTY_CYCLE_COUNT) yang dilindungi blok try-catch dari penolakan izin BATTERY_STATS.   Kernel Sysfs Direct Read: Membaca langsung node /sys/class/power_supply/battery/cycle_count atau /sys/class/power_supply/bms/cycle_count untuk platform Android industri.   Format Output & Ambang Batas Checkmk:Format output terpadu dalam satu baris service:   Plaintext0 "Health_Battery" battery_health=100.2;80;65;0;100|battery_cycles=15;500;800;0 Status : OK | Real Health : 100.2% | Cycles : 15 | Full Capacity : 4810 mAh | Design Spec : 4800 mAh | Full Voltage : 4.38 V | Current Charge : 4810 mAh | Calculation : Direct Measurement @ 100% Full Charge
CRITICAL (State 2): Health $< 65\%$ ATAU Cycles $\ge 800$ siklus.   WARNING (State 1): Health $< 80\%$ ATAU Cycles $\ge 500$ siklus.   OK (State 0): Kondisi fisik baterai normal di atas ambang toleransi.   B. Metrik Jaringan Wi-Fi (WiFi_Status)Metrik ini memantau kualitas konektivitas nirkabel PDA untuk mengidentifikasi area blind spot (blank spot), Access Point yang kelebihan beban (overloaded), atau interferensi kanal di area kerja.   Parameter yang Diekstraksi:Signal Strength (wifi_rssi): Kekuatan sinyal radio dalam satuan dBm.   SSID: Nama Access Point / jaringan nirkabel yang aktif terhubung.   IP Address: Alamat IPv4 lokal antarmuka nirkabel (mengabaikan alamat loopback dan APIPA 169.254.x.x)[cite: 1].Link Speed: Kecepatan negosiasi lapisan fisik perangkat ke Access Point (Mbps).   Frequency: Frekuensi radio kerja (MHz), membedakan kanal 2.4 GHz (~2412–2484 MHz) dengan 5 GHz (~5180–5825 MHz).   Mekanisme Ekstraksi Tiga Lapis:Lapisan 1 (ConnectivityManager): Mengambil objek NetworkCapabilities transport Wi-Fi lalu membedah WifiInfo (standar modern Android 10+)[cite: 1].Lapisan 2 (WifiManager): Membaca getConnectionInfo() jika lapisan pertama belum menyediakan info lengkap[cite: 1].Lapisan 3 (NetworkInterface Kernel): Jika sistem operasi menolak izin lokasi/Wi-Fi, agen langsung mengekstrak soket kernel wlan0/wlan1 agar PDA tetap terlacak online beserta alamat IP-nya di Checkmk[cite: 1].Logika Ambang Batas Sinyal:OK (State 0): RSSI $> -68\text{ dBm}$ (Sinyal sangat kuat dan stabil).   WARNING (State 1): RSSI antara $-68\text{ dBm}$ hingga $-75\text{ dBm}$ (Sinyal menurun, rawan peningkatan latensi transmisi).   CRITICAL (State 2): RSSI $\le -75\text{ dBm}$ (Area tidak aman, rentan putus koneksi / packet loss tinggi).   WARNING (State 1): Wi-Fi tidak terhubung / terputus (WiFi not connected or unavailable).   C. Ringkasan Seluruh Metrik & Strategi CachingUntuk menjaga efisiensi daya baterai pada PDA yang dipakai aktif selama pergantian shift kerja, agen membagi metrik menjadi dua kelompok:   Nama Service CheckmkTipe EksekusiInterval CacheAmbang Batas (Threshold) & KeteranganAgent_StatusReal-timeSetiap polling (60 dtk)   Statistik koneksi masuk/ditolak, durasi pull terakhir, dan filter IP server.   Battery_LevelReal-timeSetiap polling (60 dtk)   Persentase daya saat ini. WARN $< 30\%$, CRIT $< 15\%$.   Health_BatteryReal-timeSetiap polling (60 dtk)   Persentase kesehatan riil, siklus baterai, kapasitas desain, kapasitas penuh, dan tegangan puncak.   RAM_UsageReal-timeSetiap polling (60 dtk)   Membaca memori via ActivityManager. WARN $\ge 85\%$, CRIT $\ge 95\%$.   WiFi_StatusReal-timeSetiap polling (60 dtk)   Nilai RSSI (dBm), SSID, kecepatan tautan fisik, frekuensi saluran, dan IP lokal.   Android_InfoReal-timeSetiap polling (60 dtk)   Model perangkat, manufaktur, versi OS Android, level SDK, profil, dan uptime sistem.   Battery_TemperatureCaching30 Menit (1800 dtk)   Sensor suhu sirkuit baterai. WARN $\ge 42^\circ\text{C}$, CRIT $\ge 48^\circ\text{C}$.   Battery_CurrentCaching1 Jam (3600 dtk)   Arus beban instan (current_now) dan rata-rata (current_avg) dalam satuan mA.   Transport_StatusCaching3 Jam (10800 dtk)   Status jalur cadangan PUSH HTTP(S), jumlah sukses/gagal, dan status kode HTTP.   Battery_VoltageCaching24 Jam (86400 dtk)   Tegangan sirkuit baterai saat ini dalam Volt.   Storage_UsageCaching24 Jam (86400 dtk)   Membaca partisi flash memory /data via StatFs. WARN $\ge 85\%$, CRIT $\ge 95\%$.   Efisiensi Caching Lokal (<<<local:cached(...)>>>): Data yang perubahannya bertahap (seperti sisa kapasitas storage dan tegangan baterai) hanya dieksekusi sekali dalam jendelanya. Selama cache masih valid, agen langsung merespons dari RAM tanpa membebani disk I/O perangkat[cite: 2].   Beban CPU Rendah: Listener TCP menggunakan pemanggilan blocking murni (ServerSocket.accept()), menjaga pemakaian CPU tetap berada pada ~0.0% saat kondisi idle.   
