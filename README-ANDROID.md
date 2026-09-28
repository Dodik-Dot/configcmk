# cmkagent v1.3.3 - Stable Release

> **Catatan Rilis v1.3.3 Stable:** 
> - **Kalkulasi Baterai Riil (Hardware-Accurate):** Menghapus baseline sintetis dan menghitung kapasitas muatan secara dinamis berdasarkan data register kernel nyata (`chargeCounterMah / (level / 100)`), mencegah kesalahan status degradasi pada perangkat baru.
> - **Kalibrasi Kapasitas Penuh (Full Charge):** Merekam otomatis nilai kapasitas riil dan tegangan *cut-off* puncak (~4.35 V – 4.40 V) saat perangkat terisi 100% atau berstatus `Full` pada *docking charger/cradle*.
> - **Metrik Siklus Pengisian (Cycle Count) Terpadu:** Membaca akumulasi siklus pengisian menggunakan metode ganda (API Android 14+ via konstanta ID `7` dan *fallback* berkas kernel `sysfs` untuk Newland MT93).
> - **Proteksi Anti-Crash (`SecurityException`):** Membungkus seluruh pemanggilan register baterai dengan proteksi *exception* menyeluruh agar aplikasi tidak mengalami *force close* saat dijalankan pada sistem operasi Android modern.
> - **Penyatuan Service `Health_Battery`:** Menggabungkan persentase kesehatan riil, jumlah siklus, kapasitas desain pabrik, kapasitas penuh, dan tegangan puncak ke dalam satu baris service Checkmk dengan grafik ganda (*perfdata*).
> - **Kompatibilitas Foreground Service:** Menggunakan `targetSdk 33` untuk menjamin stabilitas *background listener* pada Android 14 hingga 16 tanpa bentrok perizinan *foreground service type*.

Agen monitoring Android native untuk Checkmk Community.

- **Package:** `com.bcp.checkmkagent`[cite: 1, 2, 6]
- **Nama Aplikasi:** `cmkagent`
- **Versi:** `1.3.3` (Stable)
- **Target SDK:** Android SDK 35 (Compile), Android SDK 33 (Target), Android SDK 26 (Minimum)
- **Lingkungan Build:** Java 17 + Gradle
- **Transport Utama:** Checkmk PULL melalui TCP/6556
- **Transport Cadangan:** HTTP/HTTPS PUSH ke receiver cache
- **Target Utama Armada:** Newland MT93 (Kapasitas desain standar 4.800 mAh) & Android Generic

---

## Arsitektur Agen & Aliran Data

```text
+-----------------------------------------------------------------------------------+
|                            cmkagent v1.3.3 Architecture                           |
+-----------------------------------------------------------------------------------+
|  [Hardware: Newland MT93 / Android]                                               |
|        │                                                                          |
|        ├──> Kernel Sysfs Nodes (/sys/class/power_supply/...)                      |
|        ├──> Android BatteryManager API (Charge Counter, Arus, Siklus)             |
|        ├──> ConnectivityManager & LinkProperties (Wi-Fi, RSSI, IP, Frequency)     |
|        └──> Linux StatFs & ActivityManager (Storage & RAM Usage)                  |
|                                                                                   |
|  [DeviceMetrics.java Engine]                                                      |
|        │                                                                          |
|        ├──> Ekstrapolasi Baterai Riil: Charge / (Level / 100)                     |
|        ├──> Filter Validasi RSSI: -126 dBm s.d. 0 dBm                             |
|        └──> Anti-Crash Safety Wrapper (Proteksi SecurityException)                |
|                                                                                   |
|  [CheckmkOutput.java Formatter]                                                   |
|        │                                                                          |
|        ├──> Real-time Service (Agent_Status, Health_Battery, WiFi_Status, dll)    |
|        └──> Cached Service (Temp: 30m, Current: 1h, Transport: 3h, Volt/Disk: 24h)|
+-----------------------------------------------------------------------------------+
