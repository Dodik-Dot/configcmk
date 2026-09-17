# Checkmk Client Monitoring Agent Script Suite

Sistem pemantauan agen kustom **Checkmk** berbasis skrip otomatis untuk melakukan pengawasan terstandarisasi pada seluruh host client **Linux** dan **Windows**. Seluruh konfigurasi, skrip monitoring (_local checks_), dan installer otomatis dikelola secara terpusat pada repositori GitHub resmi **`Dodik-Dot/configcmk`**. #kredit untuk mas Aziz yang sudah susah payah bikin **`andin1st/scriptcmk/`**

Dengan arsitektur ini, baik server Linux maupun Windows klien akan memancarkan matriks serta visualisasi pemantauan yang **identik dan terstandarisasi** ke server pusat Checkmk.

---

## 📂 Struktur Repositori GitHub (`Dodik-Dot/configcmk`)

```text
andin1st/scriptcmk/
├── .gitignore
├── README.md                            # Panduan dokumentasi terpadu ini
├── docker-compose-checkmk.yml           # Konfigurasi container server Checkmk (v2.5.0)
├── linux/
│   ├── install.sh                       # Skrip installer otomatis Linux Host (bootstrap)
│   └── local_checks/                    # Folder tempat 10 skrip local checks Linux
│       ├── battery_health.sh            # 1. Pemantau kesehatan baterai laptop via UPower
│       ├── cpu_info.sh                  # 2. Utilisasi, spesifikasi, clock, dan suhu CPU
│       ├── disk_nvme_health.sh          # 3. Pemantau terpadu NVMe, SATA SSD (Heuristik), & HDD
│       ├── fan_health.sh                # 4. Pemantau kecepatan putaran kipas pendingin (RPM)
│       ├── info_network.sh              # 5. Real-time network throughput, RX/TX rate, & IP info
│       ├── info_OS_office.sh            # 6. Detail distro OS & versi Office terpasang (Timestamped)
│       ├── ram_health.sh                # 7. Log reader uji memori asinkron memtester & slot fisik
│       ├── ram_usage.sh                 # 8. Penggunaan RAM fisik aktif
│       ├── remote_apps.sh               # 9. Pelacak AnyDesk ID & RustDesk ID unik
│       └── storage_usage.sh             # 10. Penggunaan partisi disk fisik aktif (Non-virtual)
└── windows/
    ├── install.ps1                      # Skrip installer otomatis Windows Host (bootstrap)
    └── local_checks/                    # Folder tempat 10 skrip local checks Windows
        ├── battery_health.ps1           # 1. Pemantau kesehatan baterai laptop Windows
        ├── cpu_info.ps1                 # 2. Utilisasi, spesifikasi, clock, dan suhu CPU Windows
        ├── disk_nvme_health.ps1         # 3. Kesehatan storage NVMe/SSD/HDD (CIM/WMI) Windows
        ├── fan_health.ps1               # 4. Pemantau kecepatan kipas pendingin Windows (WMI)
        ├── info_network.ps1             # 5. Real-time network throughput & IP info Windows
        ├── info_OS_office.ps1           # 6. Status aktivasi Windows OS & lisensi MS Office (ospp.vbs)
        ├── ram_health.ps1               # 7. Log reader uji RAM asinkron & inventory slot fisik Windows
        ├── ram_usage.ps1                # 8. Penggunaan RAM fisik aktif Windows
        ├── remote_apps.ps1              # 9. Pelacak AnyDesk ID & RustDesk ID unik Windows
        └── storage_usage.ps1            # 10. Penggunaan kapasitas partisi hard disk Windows (NTFS/ReFS)
```

---

## 🚀 Panduan Deployment Cepat (One-Liner Bootstrap)

### **A. Linux Host (Ubuntu, Debian, Fedora, RHEL, dll.)**

Jalankan perintah berikut di terminal target Linux untuk mengunduh agen (.deb/.rpm), mengonfigurasi dependensi, memasang 10 skrip pemantauan, dan mengatur Cron Job uji RAM Sabtu jam 11:00 AM:

```bash
curl -sSL https://raw.githubusercontent.com/Dodik-Dot/configcmk/main/linux/install.sh | sudo bash
```
Jika ingin meremove semua config yang pernah ada :
```bash
sudo rm -rf /usr/lib/check_mk_agent/local/* /var/lib/check_mk_agent/cache/* && curl -sSL https://raw.githubusercontent.com/Dodik-Dot/configcmk/main/linux/install.sh | sudo bash
```
Jika ingin meremove semua config yang pernah ada dan langsung ke SERVER KEDIRI:
```bash
sudo rm -rf /usr/lib/check_mk_agent/local/* /var/lib/check_mk_agent/cache/* && curl -sSL https://raw.githubusercontent.com/Dodik-Dot/configcmk/main/linux/install.sh | sudo bash -s -- -s 192.168.55.112:8081 -d cmk -v 2.4.0p35-1
```

### **B. Windows Host (Windows 10, 11, Server)**

Buka **PowerShell sebagai Administrator**, lalu jalankan perintah bypass satu baris berikut untuk menginstal agen (.msi), memasang 10 skrip PowerShell, membersihkan cache lama, dan mendaftarkan Windows Task Scheduler uji RAM asinkron hari Sabtu jam 11:00 AM:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/Dodik-Dot/configcmk/main/windows/install.ps1'))
```

_Untuk kebutuhan deployment massal non-interaktif di Windows, Anda dapat melewatkan parameter konfigurasi Server secara langsung:_

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12; & ([scriptblock]::Create((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/Dodik-Dot/configcmk/main/windows/install.ps1'))) -s "192.168.55.112:8081" -d "cmk"
```
```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12; & ([scriptblock]::Create((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/Dodik-Dot/configcmk/main/windows/install.ps1'))) -s "IP_SERVER_CHECKMK:PORT" -d "NAMA_SITE"
```
---

## 📋 Matriks Standardisasi Threshold (Checkmk)

Seluruh status peringatan visual pada dashboard server Checkmk (0 = OK, 1 = WARNING, 2 = CRITICAL) diatur secara terpusat berdasarkan standar matriks di bawah ini:

| Metrik Pemantauan      | Batas Aman (OK / 0)    | Batas Peringatan (Warning / 1) | Batas Kritis (Critical / 2) | Keterangan Platform                      |
| :--------------------- | :--------------------- | :----------------------------- | :-------------------------- | :--------------------------------------- |
| **Suhu CPU**           | $\le 75^\circ\text{C}$ | $> 75^\circ\text{C}$           | $> 85^\circ\text{C}$        | Linux (lm-sensors) & Windows (MSAcpi)    |
| **Kipas Prosesor**     | $> 1600\text{ RPM}$    | $< 1600\text{ RPM}$            | Kombinasi Suhu Tinggi       | Autodetect sistem pendingin pasif        |
| **Kesehatan Baterai**  | $\ge 60\%$             | $\le 40\%$ s.d $59\%$          | $\le 20\%$                  | Linux (UPower/Sysfs) & Windows (CIM)     |
| **Kesehatan SSD**      | $> 90\%$               | $\le 90\%$                     | $\le 80\%$                  | Linux (smartctl) & Windows (CIM Storage) |
| **Penggunaan Storage** | $< 85\%$               | $\ge 85\%$                     | $\ge 95\%$                  | Linux (df) & Windows (Win32_Volume)      |
| **Penggunaan RAM**     | $< 85\%$               | $\ge 85\%$                     | $\ge 95\%$                  | Linux (meminfo) & Windows (Win32_OS)     |
| **Kesehatan RAM**      | Passed                 | -                              | Failed                      | Berbasis log uji asinkron Sabtu 11:00 AM |

---

## ⚙️ Detail Keselarasan 10 Skrip Local Checks (Linux vs Windows)

Skrip pemantauan telah diselaraskan agar menghasilkan format keluaran visual yang **identik** menggunakan pembatas visual **Unicode Light Vertical Bar (`❘` - U+2758)** dan penulisan metadata yang seragam.

### **1. battery_health (.sh / .ps1)**

- **Fungsi**: Memantau tingkat kesehatan (_SOH - State of Health_) baterai laptop, sisa daya, status pengisian, dan kapasitas desain.
- **Linux Output**:
  `0 "Health_Battery" -  Status Battery : Fully Charged | Design Capacity : 35w/h | Current Capacity : 10w/h | Health : 28% | Battery Level : 100%`
- **Windows Output**:
  `0 "Health_Battery" -  Status Battery : Fully Charged | Design Capacity : 35w/h | Current Capacity : 10w/h | Health : 28% | Battery Level : 100%`

### **2. cpu_info (.sh / .ps1)**

- **Fungsi**: Menampilkan detail spesifikasi prosesor bersih, beban utilitas load, kecepatan clock (GHz), rasio Core/Thread fisik, dan sensor suhu.
- **Linux Output**:
  `0 "CPU_Info" - Spesifikasi : Intel Core i3 13100 | Clock Speed : 3.4Ghz | Core/Thread : 4/8 | CPU Load : 12% | CPU Temperature: 48 Celcius`
- **Windows Output**:
  `0 "CPU_Info" - Spesifikasi : Intel Core i3 13100 | Clock Speed : 3.4Ghz | Core/Thread : 4/8 | CPU Load : 12% | CPU Temperature: 48 Celcius`

### **3. disk_nvme_health (.sh / .ps1)**

- **Fungsi**: Mendeteksi kesehatan media penyimpanan (NVMe, SSD SATA, HDD) otomatis. SSD memantau wearout % dan TBW, HDD memantau bad sector (Reallocated/Pending Sectors) dan jam aktif kerja (POH). Bersih dari metrik sisa umur (_Est. Life_).
- **SATA SSD Output (Identik)**:
  `0 "Storage_Health_sda" - Status : OK | Model: CS900 SSD 120GB (111.79 GB) | Status: PASSED | Temp: 26C | Type: SSD Sata (111.79 GB) | Health: 100% | Read: 6.5 TB | Written: 5.4 TB | Write/Day: 108.64 GB`
- **SATA HDD Output (Identik)**:
  `0 "Storage_Health_sdb" - Status : OK | Model: ST1000LM035 1TB (931.51 GB) | Status: PASSED | Temp: 31C | Disk Type: HDD | Reallocated Sectors: 0 | Pending Sectors: 0 | Power On Hours: 12345 Hrs | Remark: Disk Condition Good`

### **4. fan_health (.sh / .ps1)**

- **Fungsi**: Memantau putaran kecepatan kipas pendingin CPU prosesor dalam satuan RPM.
- **Output (Identik)**:
  `0 "FAN_Health" - Status : OK | FAN Speed : 2319rpm | Remark: FAN Condition Good`

### **5. info_network (.sh / .ps1)**

- **Fungsi**: Mengukur volume akumulatif data terunduh/terunggah serta menghitung kecepatan transfer RX/TX Rate sesungguhnya per detik (B/s, KB/s, MB/s) pada interface aktif.
- **Output (Identik)**:
  `0 "Info_Network_Ethernet" in=122554432c|out=3586048c OK - IP Address: 192.168.43.33 | Total Download: 114.14 GB | Total Upload: 3.34 GB | RX Rate : 250.20 KB/s | TX Rate : 123.00 KB/s`

### **6. info_OS_office (.sh / .ps1)**

- **Fungsi**: Menyajikan rincian nama sistem operasi distribusi, versi kernel, status aktivasi lisensi OS, serta pendeteksian terintegrasi terhadap seluruh aplikasi office terpasang (LibreOffice, WPS, MS Office ClickToRun) beserta lisensinya.
- **Output (Identik)**:
  `0 "Info_OS" - OK - OS: Microsoft Windows 11 Pro | Kernel: 10.0.22631 | Arch: 64-bit | License: Activated (Licensed) | Checked At: 2026-08-22 16:00:00`
  `0 "Info_Office" - OK - Product: O365HomePremRetail (16.0.17830) | Status: Licensed (LICENSED (Key: ...-Y8R3) | Checked At: 2026-08-22 16:00:00`

### **7. ram_health (.sh / .ps1)**

- **Fungsi**: Membaca file log lokal hasil pengetesan integritas RAM asinkron oleh utilitas `memtester`/diagnostic Windows yang dipicu **Setiap Hari Sabtu pukul 11:00 AM** via Cron/Task Scheduler, serta mendeteksi sasis slot RAM fisik motherboard secara dinamis (Used/Empty Slots, Active Module Sizes).
- **Output (Identik)**:
  `0 "Health_RAM" - Status : OK | Result: Passed | Tested Size: 128M | Last Test: 2026-08-22 11:50 | Used Slots: 2/2 (0 Empty) | Active Modules: [4GiB,4GiB] | Log: Memory allocation and system diagnostics passed.`

### **8. ram_usage (.sh / .ps1)**

- **Fungsi**: Memantau kapasitas total, sisa ruang kosong, dan persentase penggunaan memori RAM fisik aktif.
- **Output (Identik)**:
  `0 "RAM_Usage" - Status : OK | Used: 45% | Used Space: 3.60 GB | Free: 4.40 GB | Total: 8.00 GB`

### **9. remote_apps (.sh / .ps1)**

- **Fungsi**: Memindai file konfigurasi dan registry sistem untuk melacak AnyDesk ID dan RustDesk ID unik milik klien.
- **Output (Identik)**:
  `0 "Remote_Apps" - Status : OK | AnyDesk ID: 123456789 | RustDesk ID: 987654321`

### **10. storage_usage (.sh / .ps1)**

- **Fungsi**: Memantau kapasitas seluruh partisi penyimpanan fisik yang terpasang (mounted) secara aman, mengabaikan partisi virtual, swap, maupun system reserved.
- **Output (Identik)**:
  `0 "Storage_Usage_C" - Status : OK | Partition: C: (Local Disk) | Used: 42% | Free: 139.20 GB | Total: 240.00 GB`

---

## 🔧 Pemeliharaan & Kustomisasi Script

Komputer client yang sudah aktif akan menyelaraskan scriptnya secara otomatis. Jika Anda melakukan perubahan logika pada file script local checks di dalam repositori GitHub ini, Anda **tidak perlu** mengonfigurasi ulang komputer klien satu per satu. Cukup lakukan commit/push perubahan Anda ke repositori GitHub, lalu jalankan kembali perintah _one-liner bootstrap_ di atas pada mesin klien untuk memperbarui script lokal mereka ke versi terbaru secara instan.
