# cmkagent v1.3.6 - Stable Release

> **Catatan Rilis v1.3.6 Stable:** 
> - **Penyatuan Penuh Menu Baterai ke 1 Baris (`Health_Battery`):** Menggabungkan seluruh metrik baterai (Level, Status, Real Health, Cycles, Full Capacity, Design Spec, Temperature, Voltage, Current) menjadi **1 baris service Checkmk tunggal (`Health_Battery`)** dengan multi-perfdata (`battery_level`, `battery_health`, `battery_cycles`, `battery_temp`, `battery_voltage`, `battery_current`). Menghapus 4 baris service terpisah (`Battery_Level`, `Battery_Temperature`, `Battery_Voltage`, `Battery_Current`).
> - **Logika Kesehatan 2946 mAh @ 100% & Perbaikan Pembacaan Siklus (`Cycles`):** Mengkalibrasi kesehatan baterai menggunakan kapasitas penuh hardware saat charge 100% di **2946 mAh** (`Design Spec : 4800 mAh`), serta memperbaiki penghitung siklus charging (`Cycles`) dengan pelacakan sesi & delta muatan kontinu (`BatteryHistory` + `BroadcastReceiver` + timer 1 menit) sehingga tetap akurat pada Newland MT93 meskipun node kernel sysfs `cycle_count` diblokir SELinux.
> - **Monitoring Ping 4x Setiap 1 Menit (Kirim ke Checkmk Setiap 1 Jam, Retensi Log 30 Hari ala CCTV di HP):** Menjalankan ping 4x setiap 1 menit ke **`192.168.122.10`** dan **`8.8.8.8`**, menyimpannya ke berkas log lokal di PDA (`ping_history.log`) dengan **retensi otomatis 30 hari** (log di hari ke-31 dan seterusnya otomatis dihapus seperti rekaman CCTV), dan mengirimkan rangkuman 1 jam ke Checkmk dalam **2 baris service terpisah** (`Ping_192.168.122.10` dan `Ping_8.8.8.8`).
> - **Deteksi Roaming Access Point Wi-Fi (`WiFi_Status` - UniFi & Multi-AP):** Menangkap perpindahan Access Point (roaming BSSID, identifikasi vendor OUI UniFi/Ubiquiti termasuk virtual BSSID, Band 2.4GHz/5GHz & Nomor Kanal, riwayat perpindahan AP sebelumnya ke AP aktif, hitungan roam 1 jam terakhir & total, serta log permanen `wifi_roaming.log`).
> - **Pembatasan Firewall IP Server Checkmk Cabang:** Menolak konfigurasi kosong pada port TCP/6556 dan mewajibkan pengisian manual **IP Server Checkmk Cabang** saat setting pertama kali di PDA (tanpa menampilkan IP default bawaan; mendukung input IP saja maupun `IP:Port` seperti `:80`, `:8080`, `:8081`).

Agen monitoring Android native untuk Checkmk Community.

- **Package:** `com.bcp.checkmkagent`
- **Nama Aplikasi:** `cmkagent`
- **Versi:** `1.3.6` (Stable Release)
- **Target SDK:** Android SDK 35 (Compile), Android SDK 33 (Target), Android SDK 26 (Minimum)
- **Lingkungan Build:** Java 17 + Gradle 8.9
- **Transport Utama:** Checkmk PULL melalui TCP/6556 (Terproteksi Whitelist IP Server Cabang)
- **Transport Cadangan:** HTTP/HTTPS PUSH ke receiver cache
- **Target Armada Produksi:** Newland MT93 (`Full Capacity @ 100% = 2946 mAh`, `Design Spec = 4800 mAh`) & Android Generic

---

## 1. Arsitektur Agen & Aliran Data

    +-----------------------------------------------------------------------------------+
    |                            cmkagent v1.3.6 Architecture                           |
    +-----------------------------------------------------------------------------------+
    |  [Hardware & Network Layer: Newland MT93 / Android OS]                            |
    |        │                                                                          |
    |        ├──> Kernel Sysfs + BatteryManager + BroadcastReceiver (Charge & Cycles)   |
    |        ├──> ConnectivityManager + WifiManager + Roaming Tracker (BSSID/UniFi/Ch)  |
    |        ├──> Background 1-Minute Scheduler (4x Ping to 192.168.122.10 & 8.8.8.8)   |
    |        └──> Linux StatFs & ActivityManager (Storage & RAM Usage)                  |
    |                                                                                   |
    |  [Processing & Local Persistence Engine]                                          |
    |        │                                                                          |
    |        ├──> BatteryHistory.java : Kalibrasi 2946 mAh @ 100% & Siklus Charging     |
    |        ├──> PingMonitor.java    : Buffer 60m (240 pkt/jam) + Log ping_history.log |
    |        └──> WifiRoamingTracker  : Deteksi Handoff AP + Log wifi_roaming.log       |
    |                                                                                   |
    |  [Checkmk Formatter: CheckmkOutput.java]                                          |
    |        │                                                                          |
    |        ├──> Real-time (60s) : Agent_Status, Health_Battery (1 Baris),             |
    |        │                      RAM_Usage, WiFi_Status (AP Roaming), Android_Info   |
    |        └──> Cached Service  : Ping_192.168.122.10 (1h), Ping_8.8.8.8 (1h),        |
    |                               Transport_Status (3h), Storage_Usage (24h)          |
    +-----------------------------------------------------------------------------------+

---

## 2. Logika Pemantauan & Perhitungan Metrik

### A. Metrik Baterai Terpadu 1 Baris (`Health_Battery`)

Seluruh informasi baterai kini disatukan ke dalam **1 baris service Checkmk (`Health_Battery`)** agar ringkas dan mudah dipantau.

1. **Kapasitas Penuh @ 100% (`2946 mAh`) & Spesifikasi Pabrik (`4800 mAh`):**  
   Pada perangkat Newland MT93, pembacaan coulomb counter penuh ketika 100% charge berada di **2.946 mAh** (`Full Capacity : 2946 mAh`) dengan spesifikasi desain pabrik **4.800 mAh** (`Design Spec : 4800 mAh`).
   - Logika kesehatan (`Real Health`) membaca langsung dari rasio kapasitas penuh pada 100% charge (`2946 mAh`) terhadap muatan terkalibrasi penuh sehingga kesehatan baterai terbaca akurat (**100%** saat full capacity 2946 mAh) dan otomatis turun secara proporsional apabila kapasitas 100% baterai mulai mengalami degradasi fisik di bawah 2946 mAh.

2. **Perbaikan Pembacaan Siklus Pengisian (`Cycles`):**  
   Mengatasi masalah `Cycles : N/A` atau tidak bertambah pada Android 11 Newland MT93 dengan 3 lapis pembacaan:
   - **Lapisan 1 (Hardware/OS):** Membaca `Intent.EXTRA_CYCLE_COUNT`, `BatteryManager` property ID `7`, dan beragam path sysfs kernel (`battery/cycle_count`, `bms/cycle_count`, `mtk-master-charger/cycle_count`).
   - **Lapisan 2 (Pelacakan Muatan Kontinu via `BatteryHistory`):** `CheckmkAgentService` memantau baterai setiap 1 menit serta menangkap event `ACTION_BATTERY_CHANGED`, `ACTION_POWER_CONNECTED`, dan `ACTION_POWER_DISCONNECTED`. Setiap kenaikan muatan (`mAh` maupun `%` level baterai, baik saat status `Charging`, `Full`, maupun saat perangkat bangun dari sleep) diakumulasikan terhadap basis `2946 mAh`.
   - **Lapisan 3 (Penghitung Sesi Charge Valid):** Mencatat setiap sesi pengisian daya yang nyata (>= 5% kenaikan level atau mencapai 100% Full di cradle) dan mengambil nilai siklus tertinggi yang valid antara hardware cycle, ekuivalen siklus mAh (`accumulatedMah / 2946 mAh`), dan jumlah sesi pengisian.

3. **Format Output 1 Baris Checkmk:**  
   ```text
   0 "Health_Battery" battery_level=100;30;15;0;100|battery_health=100.0;80;65;0;100|battery_cycles=4;500;800;0|battery_temp=31.0;42;48|battery_voltage=4.349|battery_current=-180.0 Level : 100% (Full, AC) | Health : 100.0% (OK) | Cycles : 4 | Full Capacity : 2946 mAh | Design Spec : 4800 mAh | Temp : 31.0 C | Voltage : 4.35 V | Current : -180.0 mA | Calc : Full Capacity @ 100% Charge (2946 mAh)
   ```

---

### B. Monitoring Ping 4x Setiap 1 Menit & Laporan 1 Jam (`Ping_192.168.122.10` & `Ping_8.8.8.8`)

1. **Eksekusi Setiap 1 Menit:**
   - Scheduler latar belakang (`PingMonitor`) menjalankan **4x ping setiap 1 menit** ke **`192.168.122.10`** dan **`8.8.8.8`**.
2. **Penyimpanan Lokal & Retensi 30 Hari (Mirip Rekaman CCTV):**
   - Hasil setiap menit dikumpulkan di memori/storage PDA hingga mencapai durasi **1 jam (60 sampel = 240 paket ping per target)**.
   - Seluruh log per menit dan ringkasan per jam disimpan di memori internal PDA pada berkas **`ping_history.log`** dengan **retensi otomatis 30 hari** (`LOG_RETENTION_DAYS = 30`). Begitu memasuki **hari ke-31 dan seterusnya**, log lama yang berumur lebih dari 30 hari otomatis dihapus seperti sistem rekaman CCTV, dan dapat dilihat langsung dari tombol **VIEW PING LOG** di aplikasi.
3. **Pengiriman ke Server Checkmk Setiap 1 Jam (2 Baris Terpisah):**
   - Menggunakan mekanisme `<<<local:cached(...,3600):sep(0)>>>`, laporan rangkuman 1 jam dikirim ke Checkmk dalam **2 baris service terpisah**:
     - **`Ping_192.168.122.10`** (Baris 1: rta, pl, jitter, max/min RTT, jumlah sampel 1 jam)
     - **`Ping_8.8.8.8`** (Baris 2: rta, pl, jitter, max/min RTT, jumlah sampel 1 jam)

---

### C. Deteksi Roaming Access Point Wi-Fi (`WiFi_Status`)

Memantau perpindahan Access Point (UniFi maupun AP multi-vendor lainnya) secara real-time saat PDA dibawa berkeliling gudang/cabang:

1. **Identifikasi AP & Roaming (`WifiRoamingTracker`):**
   - Melacak alamat fisik **BSSID** Access Point aktif, mengenali vendor **UniFi / Ubiquiti** (baik global OUI maupun locally-administered virtual BSSID multi-SSID UniFi), serta memetakan frekuensi ke **Band (2.4GHz / 5GHz / 6GHz) dan Nomor Kanal (Ch)**.
   - Mendeteksi setiap perpindahan BSSID (atau perpindahan kanal saat BSSID disembunyikan OS), mencatat waktu roaming terakhir, AP asal -> AP tujuan (`Last Roam : aa:bb:cc:11:22:33 -> aa:bb:cc:44:55:66`), jumlah roaming dalam 1 jam terakhir (`wifi_roams_1h`), dan total roaming (`wifi_roams_total`).
   - Menyimpan riwayat perpindahan AP secara permanen di PDA pada berkas **`wifi_roaming.log`** (dapat dibuka melalui tombol **VIEW ROAMING LOG** di aplikasi).

---

### D. Ringkasan Seluruh Metrik & Strategi Caching (`v1.3.6`)

| Nama Service Checkmk | Tipe Eksekusi | Interval Cache | Ambang Batas (Threshold) & Keterangan |
| :--- | :--- | :--- | :--- |
| **`Agent_Status`** | Real-time | Setiap polling (60 dtk) | Statistik koneksi masuk/ditolak, durasi pull terakhir, dan whitelist IP server cabang. |
| **`Health_Battery`** | Real-time | Setiap polling (60 dtk) | **1 Baris Terpadu:** Level (%), Status, Health (%) berbasis 2946 mAh @ 100%, Cycles, Full Capacity (2946 mAh), Design Spec (4800 mAh), Suhu (C), Tegangan (V), dan Arus (mA). |
| **`RAM_Usage`** | Real-time | Setiap polling (60 dtk) | Pemakaian memori RAM via ActivityManager. **WARN** >= 85%, **CRIT** >= 95%. |
| **`WiFi_Status`** | Real-time | Setiap polling (60 dtk) | RSSI (dBm), SSID, BSSID & Vendor AP (UniFi), Band/Channel, Roam Count (1h & Total), Last Roam transition, Link Speed, dan IP lokal. |
| **`Android_Info`** | Real-time | Setiap polling (60 dtk) | Model perangkat, manufaktur, versi OS Android, level SDK, profil, dan uptime sistem. |
| **`Ping_192.168.122.10`** | Caching + Log HP | **1 Jam** (3600 dtk) | Ping 4x setiap 1 menit ke `192.168.122.10` (240 paket/jam), rta/pl/jitter, log 30 hari di `ping_history.log`. |
| **`Ping_8.8.8.8`** | Caching + Log HP | **1 Jam** (3600 dtk) | Ping 4x setiap 1 menit ke `8.8.8.8` (240 paket/jam), rta/pl/jitter, log 30 hari di `ping_history.log`. |
| **`Transport_Status`** | Caching | **3 Jam** (10800 dtk) | Status jalur cadangan PUSH HTTP(S), jumlah sukses/gagal, dan status kode HTTP. |
| **`Storage_Usage`** | Caching | **24 Jam** (86400 dtk) | Pemakaian partisi internal `/data` via StatFs. **WARN** >= 85%, **CRIT** >= 95%. |

---

## 3. Pengaturan IP Server Checkmk Cabang (Keamanan Port 6556)

Saat setting pertama kali di PDA pada kartu **SETTINGS**:
- Kolom **IP Server Checkmk Cabang** ditampilkan kosong tanpa IP default bawaan dan wajib diisi secara manual sesuai server cabang tempat PDA beroperasi.
- Mendukung input **IP saja** (`192.168.x.x`) maupun **IP beserta Port Web cabang** (`192.168.x.x:8081`, `192.168.x.x:8080`, atau `192.168.x.x:80`). Untuk filter firewall PULL TCP/6556, agen secara otomatis mengekstrak alamat IP server cabang tersebut sehingga baik diisi dengan port maupun tanpa port tetap valid dan berfungsi.

---

**Dibuat oleh IT OPS HQEJBNT**
