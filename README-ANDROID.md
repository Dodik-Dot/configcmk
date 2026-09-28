# cmkagent v1.3.3 - Stable Release

> **Catatan Rilis v1.3.3 Stable:** 
> - **Kalkulasi Baterai Riil (Hardware-Accurate):** Menghapus seluruh baseline buatan dan menerapkan kalkulasi muatan matematis langsung dari register kernel fisik (`chargeCounterMah / (level / 100)`) sehingga menghilangkan false alert degradasi kapasitas.
> - **Kalibrasi Kapasitas Penuh (Full Charge):** Menyimpan otomatis kapasitas muatan riil dan tegangan cut-off puncak (~4.35 V - 4.40 V) saat PDA mencapai 100% atau status `Full` di docking cradle.
> - **Metrik Siklus Pengisian (Cycle Count) Terpadu:** Membaca jumlah siklus pengisian baterai menggunakan metode ganda: konstanta ID `7` (Android 14+) dan fallback berkas kernel sysfs Newland MT93.
> - **Proteksi Penuh Anti-Crash (SecurityException):** Membungkus seluruh akses register hardware dengan blok pengaman exception menyeluruh (`try-catch Throwable`) agar terhindar dari force close pada Android 14 hingga 16.
> - **Penyatuan Baris Service Health_Battery:** Menyatukan persentase kesehatan riil, siklus, kapasitas desain pabrik, kapasitas penuh, tegangan puncak, dan muatan saat ini ke dalam satu baris service Checkmk dengan grafik ganda (perfdata).
> - **Stabilitas Foreground Service:** Menggunakan `targetSdk 33` guna menjamin keandalan background listener pada Android 14/16 tanpa kendala deklarasi hak akses foregroundServiceType.

Agen monitoring Android native untuk Checkmk Community.

- **Package:** `com.bcp.checkmkagent`
- **Nama Aplikasi:** `cmkagent`
- **Versi:** `1.3.3` (Stable Release)
- **Target SDK:** Android SDK 35 (Compile), Android SDK 33 (Target), Android SDK 26 (Minimum)
- **Lingkungan Build:** Java 17 + Gradle 8.9
- **Transport Utama:** Checkmk PULL melalui TCP/6556
- **Transport Cadangan:** HTTP/HTTPS PUSH ke receiver cache
- **Target Armada Produksi:** Newland MT93 (Spesifikasi paten baterai 4.800 mAh) & Android Generic

---

## 1. Arsitektur Agen & Aliran Data

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

---

## 2. Logika Pemantauan & Perhitungan Metrik

### A. Metrik Baterai Terpadu (`Health_Battery`)

Metrik ini memantau kesehatan fisik baterai secara presisi guna mendeteksi baterai kembung, drop, atau penurunan kapasitas sel sebelum mengganggu kegiatan operasional barcode scanning di gudang.

1. **Spesifikasi Hardware Pabrik (`Design Spec`):**  
   Sistem secara otomatis mengenali identitas hardware Newland MT93 dan menetapkan nilai rancangan kapasitas pabrik mutlak sebesar **4.800 mAh** (bukan 5.000 mAh seperti estimasi profil generik Android). Nilai ini menjadi angka dasar pembagi dalam kalkulasi kesehatan.

2. **Kalkulasi Kapasitas Penuh Riil (`Full Capacity`):**  
   - **Mode Operasional Berjalan (Dynamic Real-Time):**  
     Saat baterai berada pada kondisi penggunaan normal (misal 61%), agen mengambil register muatan listrik aktual dari pengontrol baterai (`chargeCounterMah`, misal 2.946 mAh). Nilai kapasitas penuh dihitung dengan rumus:
     
         Full Capacity = Muatan Aktual (mAh) / (Level Baterai / 100)
         Contoh: 2946 / (61 / 100) = 4829 mAh
     
     Hasil perhitungan menunjukkan kapasitas normal di kisaran 4.829 mAh (Health 100.6% OK), meniadakan kesalahan versi lama yang mendeteksi degradasi palsu 61.4%.
   - **Mode Kalibrasi Penuh (Direct Measurement @ 100% Full Charge):**  
     Ketika PDA di-docking hingga mencapai level 100% atau berstatus `Full`, agen langsung membaca kapasitas puncak fisik dan nilai tegangan cut-off (~4.35 V - 4.40 V), lalu menyimpannya ke `SharedPreferences` sebagai tolok ukur kalibrasi hardware yang valid.

3. **Persentase Kesehatan Baterai (`Real Health`):**  
   
       Health Percent (%) = (Full Capacity / Design Capacity) * 100
       Contoh: (4829 / 4800) * 100 = 100.6%

4. **Deteksi Siklus Baterai (`Cycles`):**  
   Akumulasi siklus pengosongan-pengisian dibaca lewat dua jalur:
   - **API Android 14+:** Mengakses register integer ID `7` (`BATTERY_PROPERTY_CYCLE_COUNT`) yang dilindungi blok `try-catch` dari penolakan izin `BATTERY_STATS`.
   - **Kernel Sysfs Direct Read:** Membaca langsung node `/sys/class/power_supply/battery/cycle_count` atau `/sys/class/power_supply/bms/cycle_count` untuk platform Android industri.

5. **Format Output & Ambang Batas Checkmk:**  
   Format output terpadu dalam satu baris service:
   
       0 "Health_Battery" battery_health=100.2;80;65;0;100|battery_cycles=15;500;800;0 Status : OK | Real Health : 100.2% | Cycles : 15 | Full Capacity : 4810 mAh | Design Spec : 4800 mAh | Full Voltage : 4.38 V | Current Charge : 4810 mAh | Calculation : Direct Measurement @ 100% Full Charge
   
   - **CRITICAL (State 2):** Health < 65% ATAU Cycles >= 800 siklus
   - **WARNING (State 1):** Health < 80% ATAU Cycles >= 500 siklus
   - **OK (State 0):** Kondisi fisik baterai normal di atas ambang toleransi

---

### B. Metrik Jaringan Wi-Fi (`WiFi_Status`)

Metrik ini memantau kualitas konektivitas nirkabel PDA untuk mengidentifikasi area blind spot, Access Point yang kelebihan beban, atau interferensi kanal di area kerja.

1. **Parameter yang Diekstraksi:**
   - **Signal Strength (`wifi_rssi`):** Kekuatan sinyal radio dalam satuan dBm.
   - **SSID:** Nama Access Point / jaringan nirkabel yang aktif terhubung.
   - **IP Address:** Alamat IPv4 lokal antarmuka nirkabel (mengabaikan loopback dan APIPA 169.254.x.x).
   - **Link Speed:** Kecepatan negosiasi lapisan fisik perangkat ke Access Point (Mbps).
   - **Frequency:** Frekuensi radio kerja (MHz), membedakan kanal 2.4 GHz (~2412-2484 MHz) dengan 5 GHz (~5180-5825 MHz).

2. **Mekanisme Ekstraksi Tiga Lapis:**
   - **Lapisan 1 (`ConnectivityManager`):** Mengambil objek NetworkCapabilities transport Wi-Fi lalu membedah WifiInfo (standar modern Android 10+).
   - **Lapisan 2 (`WifiManager`):** Membaca getConnectionInfo() jika lapisan pertama belum menyediakan info lengkap.
   - **Lapisan 3 (`NetworkInterface` Kernel):** Jika sistem operasi menolak izin lokasi/Wi-Fi, agen langsung mengekstrak soket kernel wlan0/wlan1 agar PDA tetap terlacak online beserta alamat IP-nya di Checkmk.

3. **Logika Ambang Batas Sinyal:**
   - **OK (State 0):** RSSI > -68 dBm (Sinyal sangat kuat dan stabil)
   - **WARNING (State 1):** RSSI antara -68 dBm hingga -75 dBm (Sinyal menurun, rawan peningkatan latensi)
   - **CRITICAL (State 2):** RSSI <= -75 dBm (Area tidak aman, rentan putus koneksi / packet loss tinggi)
   - **WARNING (State 1):** Wi-Fi tidak terhubung / terputus (WiFi not connected or unavailable)

---

### C. Ringkasan Seluruh Metrik & Strategi Caching

Untuk menjaga efisiensi daya baterai pada PDA yang dipakai aktif selama shift kerja, agen membagi metrik menjadi dua kelompok:

| Nama Service Checkmk | Tipe Eksekusi | Interval Cache | Ambang Batas (Threshold) & Keterangan |
| :--- | :--- | :--- | :--- |
| **`Agent_Status`** | Real-time | Setiap polling (60 dtk) | Statistik koneksi masuk/ditolak, durasi pull terakhir, dan filter IP server. |
| **`Battery_Level`** | Real-time | Setiap polling (60 dtk) | Persentase daya saat ini. **WARN** < 30%, **CRIT** < 15%. |
| **`Health_Battery`** | Real-time | Setiap polling (60 dtk) | Persentase kesehatan riil, siklus baterai, kapasitas desain, kapasitas penuh, dan tegangan puncak. |
| **`RAM_Usage`** | Real-time | Setiap polling (60 dtk) | Membaca memori via ActivityManager. **WARN** >= 85%, **CRIT** >= 95%. |
| **`WiFi_Status`** | Real-time | Setiap polling (60 dtk) | Nilai RSSI (dBm), SSID, kecepatan tautan fisik, frekuensi saluran, dan IP lokal. |
| **`Android_Info`** | Real-time | Setiap polling (60 dtk) | Model perangkat, manufaktur, versi OS Android, level SDK, profil, dan uptime sistem. |
| **`Battery_Temperature`** | Caching | **30 Menit** (1800 dtk) | Sensor suhu sirkuit baterai. **WARN** >= 42 C, **CRIT** >= 48 C. |
| **`Battery_Current`** | Caching | **1 Jam** (3600 dtk) | Arus beban instan (current_now) dan rata-rata (current_avg) dalam satuan mA. |
| **`Transport_Status`** | Caching | **3 Jam** (10800 dtk) | Status jalur cadangan PUSH HTTP(S), jumlah sukses/gagal, dan status kode HTTP. |
| **`Battery_Voltage`** | Caching | **24 Jam** (86400 dtk) | Tegangan sirkuit baterai saat ini dalam Volt. |
| **`Storage_Usage`** | Caching | **24 Jam** (86400 dtk) | Membaca partisi flash memory /data via StatFs. **WARN** >= 85%, **CRIT** >= 95%. |

- **Efisiensi Caching Lokal (`<<<local:cached(...)>>>`):** Data yang perubahannya bertahap hanya dieksekusi sekali dalam jendelanya. Selama cache masih valid, agen langsung merespons dari RAM tanpa membebani disk I/O perangkat.
- **Beban CPU Rendah:** Listener TCP menggunakan pemanggilan blocking murni (`ServerSocket.accept()`), menjaga pemakaian CPU tetap berada pada ~0.0% saat kondisi idle.

---

## 3. Cara Kerja Hybrid Transport

`cmkagent` menjalankan server lokal pada port TCP/6556 untuk melayani permintaan data berkala dari server Checkmk (PULL) sebagai jalur utama. 

Jika opsi backup PUSH diaktifkan dan Receiver URL telah dikonfigurasi, layanan latar depan (foreground service) agen juga secara otomatis mengirimkan salinan data yang sama ke endpoint receiver berbasis HTTP/HTTPS.

    Checkmk Server ---- PULL TCP/6556 ----> Android cmkagent (Newland MT93)
                                                |
                                                +---- PUSH HTTP(S) ----> Receiver Cache

**Logika Failover di Sisi Server Checkmk:**
1. Mencoba koneksi PULL TCP/6556 terlebih dahulu.
2. Jika koneksi PULL gagal (misal PDA berada di luar jangkauan Wi-Fi sesaat), sistem beralih membaca cache PUSH terbaru.
3. Jika kedua jalur tidak dapat dihubungi atau data cache telah kedaluwarsa, host dilaporkan berstatus Down/Unavailable.

---

## 4. Pengaturan Aplikasi (Settings Card)

Pengaturan yang tersedia pada kartu **SETTINGS** di dalam aplikasi:

- **Hostname:** Nama host PDA yang diselaraskan dengan nama host di Checkmk.
- **Pull TCP Port:** Port listener (default: `6556`).
- **Allowed Checkmk Server IP:** Membatasi akses listener PULL hanya dari IP server tertentu.
- **Battery Design Capacity:** Nilai kapasitas desain baterai dalam satuan mAh (default Newland MT93: `4800`).
- **Aktifkan Backup PUSH (Hybrid):** Mengaktifkan transmisi metrik cadangan melalui protokol HTTP/HTTPS.
- **Push Receiver URL:** Alamat URL endpoint penerima cache PUSH.
- **Push Token:** Token otentikasi Bearer untuk mengamankan transmisi data.
- **Push Interval:** Interval siklus pengiriman PUSH (minimal 60 detik; default: `300` detik).
- **Start Agent Otomatis Setelah Boot:** Menjalankan agen secara otomatis saat perangkat selesai restart.

Rekomendasi konfigurasi server operasional:

    Allowed Checkmk Server IP : 192.168.55.112
    Push Receiver URL         : http://192.168.55.112:18080/api/v1/agent
    Push Interval             : 300
    Design Capacity (mAh)     : 4800

---

## 5. Panduan Stabilitas Background Service pada PDA

Agar service agen tidak dihentikan secara sepihak oleh manajemen daya agresif bawaan Android saat layar perangkat padam:
1. Masuk ke **Pengaturan Android** -> **Aplikasi** -> **Kelola Aplikasi** -> pilih **cmkagent**.
2. Aktifkan opsi **Mulai Otomatis / Autostart**.
3. Buka menu **Penghemat Baterai (Battery Saver)** dan ubah opsinya menjadi **Tidak ada batasan (No restrictions)**.
4. Buka aplikasi `cmkagent`, masuk ke section **SETTINGS**, lalu tekan **SAVE & START AGENT** hingga kartu AGENT berstatus hijau **RUNNING**.

> **PENTING (Catatan Instalasi Versi Baru):**  
> Jika saat memperbarui muncul pesan *"Aplikasi tidak diinstal karena paket ini bentrok dengan paket yang sudah ada"*, lakukan **Copot Pemasangan (Uninstall)** aplikasi versi lama terlebih dahulu sebelum memasang APK v1.3.3 hasil build GitHub Actions guna menghindari bentrok tanda tangan digital (signature mismatch).

---

## 6. Build Otomatis via GitHub Actions

Proses kompilasi berjalan otomatis melalui alur kerja GitHub Actions setiap kali terjadi pembaruan pada direktori `android/**` atau berkas workflow.

Berkas artefak rilis stabil yang dihasilkan:

    cmkagent-v1.3.3
    └── cmkagent-v1.3.3.apk

---

**Dibuat oleh IT OPS HQEJBNT**
