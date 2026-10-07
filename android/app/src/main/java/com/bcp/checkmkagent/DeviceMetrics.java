package com.bcp.checkmkagent;

import android.app.ActivityManager;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.net.ConnectivityManager;
import android.net.LinkAddress;
import android.net.LinkProperties;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.net.wifi.WifiInfo;
import android.net.wifi.WifiManager;
import android.os.BatteryManager;
import android.os.Build;
import android.os.Environment;
import android.os.StatFs;
import android.os.SystemClock;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.lang.reflect.Constructor;
import java.lang.reflect.Method;
import java.net.Inet4Address;
import java.net.NetworkInterface;
import java.util.Collections;
import java.util.List;
import java.util.Locale;

public final class DeviceMetrics {

    private DeviceMetrics() {}

    public static final class BatteryInfo {
        public int level = -1;
        public double temperatureC = Double.NaN;
        public double voltageV = Double.NaN;
        public String status = "Unknown";
        public String healthStatus = "Good";
        public double chargeCounterMah = Double.NaN;
        public double currentNowMa = Double.NaN;
        public double currentAverageMa = Double.NaN;
        public double designCapacityMah = Double.NaN;
        public String designCapacitySource = "Unavailable";
        public double fullCapacityMah = Double.NaN;
        public double fullChargeVoltageV = Double.NaN;
        public String fullCapacitySource = "Unavailable";
        public boolean fullCapacityEstimated = false;
        public double healthPercent = 100.0;
        public int estimateSamples = 0;
        public int cycleCount = -1;
    }

    public static final class UsageInfo {
        public double totalGb;
        public double freeGb;
        public double usedGb;
        public double usedPercent;
    }

    public static final class WifiStatus {
        public boolean connected;
        public String ssid = "Not Connected";
        public String ip = "N/A";
        public int rssi = Integer.MIN_VALUE;
        public int linkSpeedMbps = -1;
        public int frequencyMhz = -1;
        public String detectionSource = "Unavailable";
        public String detailsSource = "Unavailable";
    }

    public static final class DeviceInfo {
        public String manufacturer;
        public String model;
        public String androidVersion;
        public int sdk;
        public long uptimeMs;
        public String profile;
        public String hardwareSoc;
        public String board;
        public String kernelVersion;
        public String arch;
    }

    public static final class AppInventoryInfo {
        public int totalApps = 0;
        public int userApps = 0;
        public int systemApps = 0;
        public String fullInventoryPayload = "";
    }

    public static AppInventoryInfo readAppInventory(Context context) {
        AppInventoryInfo info = new AppInventoryInfo();
        if (context == null) return info;

        StringBuilder sb = new StringBuilder();
        DeviceInfo dev = readDeviceInfo();
        UsageInfo ram = readRam(context);
        UsageInfo storage = readStorage();

        // =====================================================================
        // 1. HARDWARE: SYSTEM & MEMORY (RAM) -> Mengisi Hardware > Memory & System
        // =====================================================================
        long ramTotalMb = Math.round(ram.totalGb * 1024.0);
        sb.append("<<<dmidecode:sep(58)>>>\n");
        sb.append("System Information\n");
        sb.append(":Manufacturer: ").append(dev.manufacturer).append("\n");
        sb.append(":Product Name: ").append(dev.model).append("\n");
        sb.append(":Version: Android ").append(dev.androidVersion).append("\n");
        sb.append(":Serial Number: ").append(dev.board).append("\n");
        sb.append(":UUID: ").append(dev.profile.hashCode()).append("\n\n");

        sb.append("Physical Memory Array\n");
        sb.append(":Location: System Board\n");
        sb.append(":Use: System Memory\n");
        sb.append(":Maximum Capacity: ").append(ramTotalMb).append(" MB\n");
        sb.append(":Number Of Devices: 1\n\n");

        sb.append("Memory Device\n");
        sb.append(":Array Handle: 0x0001\n");
        sb.append(":Total Width: 64 bits\n");
        sb.append(":Data Width: 64 bits\n");
        sb.append(":Size: ").append(ramTotalMb).append(" MB\n");
        sb.append(":Form Factor: Row Of Chips\n");
        sb.append(":Locator: RAM 0\n");
        sb.append(":Bank Locator: Bank 0\n");
        sb.append(":Type: LPDDR4\n");
        sb.append(":Type Detail: Synchronous\n");
        sb.append(":Speed: 1866 MT/s\n");
        sb.append(":Manufacturer: ").append(dev.manufacturer).append("\n\n");

        // =====================================================================
        // 2. HARDWARE: PROCESSOR -> Mengisi Hardware > Processor
        // =====================================================================
        int cores = Math.max(1, Runtime.getRuntime().availableProcessors());
        sb.append("<<<lnx_cpuinfo:sep(58)>>>\n");
        for (int i = 0; i < cores; i++) {
            sb.append("processor: ").append(i).append("\n");
            sb.append("model name: ").append(dev.hardwareSoc).append(" (").append(dev.board).append(")\n");
            sb.append("cpu MHz: 2000.000\n");
            sb.append("cache size: 1024 KB\n");
            sb.append("flags: fp asimd evtstrm aes pmull sha1 sha2 crc32\n\n");
        }

        // =====================================================================
        // 3. HARDWARE: STORAGE -> Mengisi Hardware > Storage > Block devices
        // =====================================================================
        long storageSectors512 = Math.round(storage.totalGb * 1024.0 * 1024.0 * 2.0);
        sb.append("<<<lnx_block_devices:sep(0)>>>\n");
        sb.append("|device|/sys/block/internal_storage|\n");
        sb.append("|size|").append(storageSectors512).append("|\n");
        sb.append("|device/vendor|Internal|\n");
        sb.append("|device/model|eMMC/UFS Internal Storage (").append(Math.round(storage.totalGb)).append(" GB)|\n");
        sb.append("|device/type|MMC|\n\n");

        // =====================================================================
        // 4. SOFTWARE: OPERATING SYSTEM -> Mengisi Software > Operating system
        // =====================================================================
        sb.append("<<<lnx_distro:sep(124)>>>\n");
        sb.append("[[[/etc/os-release]]]\n");
        sb.append("NAME=\"Android\"|VERSION=\"").append(dev.androidVersion)
          .append(" (SDK ").append(dev.sdk).append(")\"|ID=android|PRETTY_NAME=\"Android ")
          .append(dev.androidVersion).append(" (").append(dev.manufacturer).append(" ")
          .append(dev.model).append(")\"\n\n");

        sb.append("<<<lnx_uname>>>\n");
        sb.append("Linux ").append(AgentConfig.getHostname(context)).append(" ")
          .append(dev.kernelVersion).append(" #1 SMP PREEMPT ")
          .append(dev.arch).append(" Android\n\n");

        // =====================================================================
        // 5. SOFTWARE: PACKAGES -> Mengisi Software > Software packages (7 Kolom)
        // =====================================================================
        sb.append("<<<lnx_packages:sep(124)>>>\n");
        try {
            PackageManager pm = context.getPackageManager();
            List<PackageInfo> packages = pm.getInstalledPackages(0);

            for (PackageInfo pkg : packages) {
                if (pkg == null || pkg.packageName == null) continue;

                boolean isSystem = false;
                String appLabel = pkg.packageName;

                if (pkg.applicationInfo != null) {
                    isSystem = (pkg.applicationInfo.flags & ApplicationInfo.FLAG_SYSTEM) != 0;
                    try {
                        CharSequence label = pkg.applicationInfo.loadLabel(pm);
                        if (label != null && label.length() > 0) {
                            appLabel = label.toString().replace('|', ' ')
                                    .replace('\n', ' ').replace('\r', ' ').trim();
                        }
                    } catch (Throwable ignored) {}
                }

                info.totalApps++;
                if (isSystem) info.systemApps++;
                else info.userApps++;

                String ver = pkg.versionName != null ? pkg.versionName.trim().replace('|', ' ') : "1.0";
                String pkgType = isSystem ? "system" : "apk";
                long verCode = (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P)
                        ? pkg.getLongVersionCode() : pkg.versionCode;

                // Format 7 Kolom Checkmk: Package|Version|Arch|Type|Release|Summary|Status
                sb.append(pkg.packageName).append('|')
                  .append(ver).append('|')
                  .append(dev.arch).append('|')
                  .append(pkgType).append('|')
                  .append(verCode).append('|')
                  .append(appLabel).append('|')
                  .append("installed\n");
            }
        } catch (Throwable ignored) {}

        info.fullInventoryPayload = sb.toString();
        return info;
    }

    public static BatteryInfo readBattery(Context context) {
        BatteryInfo out = new BatteryInfo();
        if (context == null) return out;

        boolean isMt93 = isNewlandMt93();

        Intent battery = null;
        try {
            battery = context.registerReceiver(null, new IntentFilter(Intent.ACTION_BATTERY_CHANGED));
            if (battery != null) {
                int rawLevel = battery.getIntExtra(BatteryManager.EXTRA_LEVEL, -1);
                int scale = battery.getIntExtra(BatteryManager.EXTRA_SCALE, 100);
                if (rawLevel >= 0 && scale > 0) {
                    out.level = (int) Math.round(rawLevel * 100.0 / scale);
                }

                int tempTenths = battery.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, Integer.MIN_VALUE);
                if (tempTenths != Integer.MIN_VALUE && tempTenths != 0) {
                    out.temperatureC = tempTenths / 10.0;
                }

                int voltageMv = battery.getIntExtra(BatteryManager.EXTRA_VOLTAGE, -1);
                if (voltageMv > 0) out.voltageV = voltageMv / 1000.0;

                int status = battery.getIntExtra(BatteryManager.EXTRA_STATUS, BatteryManager.BATTERY_STATUS_UNKNOWN);
                switch (status) {
                    case BatteryManager.BATTERY_STATUS_CHARGING:
                        out.status = "Charging";
                        break;
                    case BatteryManager.BATTERY_STATUS_DISCHARGING:
                        out.status = "Discharging";
                        break;
                    case BatteryManager.BATTERY_STATUS_FULL:
                        out.status = "Full";
                        break;
                    case BatteryManager.BATTERY_STATUS_NOT_CHARGING:
                        out.status = "Not Charging";
                        break;
                    default:
                        out.status = "Unknown";
                }

                int rawHealth = battery.getIntExtra(BatteryManager.EXTRA_HEALTH, BatteryManager.BATTERY_HEALTH_UNKNOWN);
                switch (rawHealth) {
                    case BatteryManager.BATTERY_HEALTH_GOOD:
                        out.healthStatus = "Good";
                        break;
                    case BatteryManager.BATTERY_HEALTH_OVERHEAT:
                        out.healthStatus = "Overheat";
                        break;
                    case BatteryManager.BATTERY_HEALTH_DEAD:
                        out.healthStatus = "Dead";
                        break;
                    case BatteryManager.BATTERY_HEALTH_OVER_VOLTAGE:
                        out.healthStatus = "Over Voltage";
                        break;
                    case BatteryManager.BATTERY_HEALTH_COLD:
                        out.healthStatus = "Cold";
                        break;
                    default:
                        out.healthStatus = "Unknown";
                }
            }
        } catch (Throwable ignored) {}

        try {
            BatteryManager bm = (BatteryManager) context.getSystemService(Context.BATTERY_SERVICE);
            if (bm != null) {
                try {
                    int chargeCounterUah = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CHARGE_COUNTER);
                    if (validBatteryProperty(chargeCounterUah) && chargeCounterUah > 0) {
                        out.chargeCounterMah = chargeCounterUah / 1000.0;
                    }
                } catch (Throwable ignored) {}

                try {
                    int currentNowUa = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CURRENT_NOW);
                    if (validBatteryProperty(currentNowUa)) out.currentNowMa = currentNowUa / 1000.0;
                } catch (Throwable ignored) {}

                try {
                    int currentAvgUa = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CURRENT_AVERAGE);
                    if (validBatteryProperty(currentAvgUa)) out.currentAverageMa = currentAvgUa / 1000.0;
                } catch (Throwable ignored) {}

                if (Build.VERSION.SDK_INT >= 34) {
                    try {
                        int cycles = bm.getIntProperty(7);
                        if (validBatteryProperty(cycles) && cycles >= 0) {
                            out.cycleCount = cycles;
                        }
                    } catch (Throwable ignored) {}
                }
            }
        } catch (Throwable ignored) {}

        // 1. Cek Node Sysfs Kernel (MediaTek MTK node)
        if (out.cycleCount < 0) {
            String[] cyclePaths = {
                    "/sys/class/power_supply/battery/cycle_count",
                    "/sys/class/power_supply/bms/cycle_count",
                    "/sys/class/power_supply/battery/battery_cycle",
                    "/sys/devices/platform/charger/power_supply/battery/cycle_count",
                    "/sys/devices/platform/mtk-battery/power_supply/battery/cycle_count"
            };
            for (String path : cyclePaths) {
                try {
                    Double val = readNumber(path);
                    if (val != null && val >= 0) {
                        out.cycleCount = val.intValue();
                        break;
                    }
                } catch (Throwable ignored) {}
            }
        }

        // 2. Design Spec: Tetap laporkan 4800 mAh dari data Android
        try {
            double manual = AgentConfig.getDesignCapacityMah(context);
            if (isPositive(manual)) {
                out.designCapacityMah = manual;
                out.designCapacitySource = "Manual Configuration";
            } else {
                double profileVal = readPowerProfileCapacityMah(context);
                if (isPositive(profileVal)) {
                    out.designCapacityMah = profileVal;
                    out.designCapacitySource = "Android System (" + Math.round(profileVal) + " mAh)";
                } else {
                    out.designCapacityMah = isMt93 ? 4800.0 : 5000.0;
                    out.designCapacitySource = "Factory Spec (" + Math.round(out.designCapacityMah) + " mAh)";
                }
            }
        } catch (Throwable ignored) {
            out.designCapacityMah = isMt93 ? 4800.0 : 5000.0;
            out.designCapacitySource = "Factory Spec";
        }

        // 3. Kapasitas acuan full charger: 2946 mAh untuk kalkulasi MT93
        final double CALCULATION_FULL_SCALE = isMt93 ? 2946.0 : out.designCapacityMah;

        if (!isPositive(out.chargeCounterMah) && out.level >= 0) {
            out.chargeCounterMah = Math.round(CALCULATION_FULL_SCALE * (out.level / 100.0));
        }

        // Simpan sesi pengisian untuk tracking akumulator siklus
        BatteryHistory.updateChargeSession(context, out.level, out.status, out.chargeCounterMah, out.voltageV);
        out.estimateSamples = BatteryHistory.getSampleCount(context);

        // Fallback Cycles untuk Android 11: Akumulasi mAh dibagi 2946 mAh
        if (out.cycleCount < 0) {
            out.cycleCount = BatteryHistory.getEstimatedCycles(context, CALCULATION_FULL_SCALE);
        }

        // 4. Evaluasi Kesehatan Berdasarkan Kapasitas Full Charger (2946 mAh)
        if (isMt93) {
            out.fullCapacityMah = CALCULATION_FULL_SCALE; // 2946 mAh
            if (out.level == 100 || "Full".equalsIgnoreCase(out.status)) {
                out.fullChargeVoltageV = !Double.isNaN(out.voltageV) ? out.voltageV : 4.34;
                out.healthPercent = 100.0;
                out.fullCapacitySource = "100% Full Cut-off (2946 mAh)";
            } else if (out.level >= 15 && isPositive(out.chargeCounterMah)) {
                double estimatedDynamic = out.chargeCounterMah / (out.level / 100.0);
                out.healthPercent = Math.min(100.0, (estimatedDynamic / CALCULATION_FULL_SCALE) * 100.0);
                out.fullCapacitySource = "Hardware Normal (" + out.level + "% State)";
            } else {
                out.healthPercent = 100.0;
                out.fullCapacitySource = "System Baseline";
            }
        } else {
            if (out.level == 100 || "Full".equalsIgnoreCase(out.status)) {
                out.fullCapacityMah = (isPositive(out.chargeCounterMah) && out.chargeCounterMah > 2000.0)
                        ? out.chargeCounterMah : out.designCapacityMah;
                out.fullChargeVoltageV = !Double.isNaN(out.voltageV) ? out.voltageV : 4.35;
                out.healthPercent = Math.min(100.0, (out.fullCapacityMah / out.designCapacityMah) * 100.0);
                out.fullCapacitySource = "100% Full Cut-off";
            } else if (out.level >= 15 && isPositive(out.chargeCounterMah)) {
                out.fullCapacityMah = out.chargeCounterMah / (out.level / 100.0);
                out.healthPercent = Math.min(100.0, (out.fullCapacityMah / out.designCapacityMah) * 100.0);
                out.fullCapacitySource = "Dynamic Estimate (" + out.level + "% State)";
                out.fullCapacityEstimated = true;
            } else {
                out.fullCapacityMah = out.designCapacityMah;
                out.healthPercent = 100.0;
                out.fullCapacitySource = "System Baseline";
            }
        }

        return out;
    }

    public static UsageInfo readRam(Context context) {
        ActivityManager am = (ActivityManager) context.getSystemService(Context.ACTIVITY_SERVICE);
        ActivityManager.MemoryInfo mi = new ActivityManager.MemoryInfo();
        if (am != null) am.getMemoryInfo(mi);

        UsageInfo out = new UsageInfo();
        out.totalGb = bytesToGb(mi.totalMem);
        out.freeGb = bytesToGb(mi.availMem);
        out.usedGb = Math.max(0, out.totalGb - out.freeGb);
        out.usedPercent = out.totalGb > 0 ? (out.usedGb / out.totalGb * 100.0) : 0.0;
        return out;
    }

    public static UsageInfo readStorage() {
        StatFs stat = new StatFs(Environment.getDataDirectory().getAbsolutePath());
        UsageInfo out = new UsageInfo();
        out.totalGb = bytesToGb(stat.getTotalBytes());
        out.freeGb = bytesToGb(stat.getAvailableBytes());
        out.usedGb = Math.max(0, out.totalGb - out.freeGb);
        out.usedPercent = out.totalGb > 0 ? (out.usedGb / out.totalGb * 100.0) : 0.0;
        return out;
    }

    @SuppressWarnings("deprecation")
    public static WifiStatus readWifi(Context context) {
        WifiStatus out = new WifiStatus();
        out.ip = getLocalIpv4();

        WifiManager wm = null;
        try {
            wm = (WifiManager) context.getApplicationContext()
                    .getSystemService(Context.WIFI_SERVICE);
            ConnectivityManager cm = (ConnectivityManager) context
                    .getSystemService(Context.CONNECTIVITY_SERVICE);

            Network wifiNetwork = null;
            NetworkCapabilities wifiCaps = null;

            if (cm != null) {
                Network[] networks = cm.getAllNetworks();
                if (networks != null) {
                    for (Network network : networks) {
                        NetworkCapabilities caps = cm.getNetworkCapabilities(network);
                        if (caps != null && caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) {
                            wifiNetwork = network;
                            wifiCaps = caps;
                            break;
                        }
                    }
                }
            }

            if (wifiNetwork != null) {
                out.connected = true;
                out.detectionSource = "ConnectivityManager Wi-Fi transport";

                LinkProperties lp = cm.getLinkProperties(wifiNetwork);
                String ip = ipv4FromLinkProperties(lp);
                if (ip != null) out.ip = ip;

                WifiInfo info = wifiInfoFromCapabilities(wifiCaps);
                if (info != null) {
                    fillWifiInfo(out, info, "NetworkCapabilities WifiInfo");
                }
            }

            if (!out.connected) {
                String wlanIp = getWifiInterfaceIpv4();
                if (wlanIp != null) {
                    out.connected = true;
                    out.ip = wlanIp;
                    out.detectionSource = "wlan interface";
                }
            }

            if (wm != null && wm.isWifiEnabled()) {
                WifiInfo legacy = wm.getConnectionInfo();
                if (legacy != null) {
                    if (!out.connected && hasUsefulWifiInfo(legacy)) {
                        out.connected = true;
                        out.detectionSource = "WifiManager connection info";
                    }
                    if (out.connected && "Unavailable".equals(out.detailsSource)) {
                        fillWifiInfo(out, legacy, "WifiManager connection info");
                    }
                }
            }

            if (out.connected && "Not Connected".equals(out.ssid)) {
                out.ssid = "Connected (SSID restricted by Android)";
            }
        } catch (SecurityException e) {
            String wlanIp = getWifiInterfaceIpv4();
            if (wlanIp != null) {
                out.connected = true;
                out.ip = wlanIp;
                out.detectionSource = "wlan interface (permission fallback)";
                out.ssid = "Connected (permission restricted)";
            }
        } catch (Exception ignored) {
            String wlanIp = getWifiInterfaceIpv4();
            if (wlanIp != null) {
                out.connected = true;
                out.ip = wlanIp;
                out.detectionSource = "wlan interface (fallback)";
                out.ssid = "Connected (details unavailable)";
            }
        }
        return out;
    }

    private static WifiInfo wifiInfoFromCapabilities(NetworkCapabilities caps) {
        if (caps == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null;
        try {
            Object transportInfo = caps.getTransportInfo();
            return transportInfo instanceof WifiInfo ? (WifiInfo) transportInfo : null;
        } catch (Exception ignored) {
            return null;
        }
    }

    private static void fillWifiInfo(WifiStatus out, WifiInfo info, String source) {
        if (info == null) return;
        out.detailsSource = source;

        String ssid = info.getSSID();
        if (ssid != null && !ssid.isEmpty()
                && !"<unknown ssid>".equalsIgnoreCase(ssid)
                && !WifiManager.UNKNOWN_SSID.equals(ssid)) {
            if (ssid.startsWith("\"") && ssid.endsWith("\"") && ssid.length() >= 2) {
                ssid = ssid.substring(1, ssid.length() - 1);
            }
            out.ssid = ssid;
        }

        int rssi = info.getRssi();
        if (isUsableRssi(rssi)) {
            out.rssi = rssi;
        }

        int speed = info.getLinkSpeed();
        if (speed >= 0) out.linkSpeedMbps = speed;

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            int frequency = info.getFrequency();
            if (frequency > 0) out.frequencyMhz = frequency;
        }
    }

    private static boolean hasUsefulWifiInfo(WifiInfo info) {
        if (info == null) return false;
        int rssi = info.getRssi();
        if (isUsableRssi(rssi)) return true;
        if (info.getLinkSpeed() > 0) return true;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP && info.getFrequency() > 0) return true;
        String ssid = info.getSSID();
        return ssid != null && !ssid.isEmpty()
                && !"<unknown ssid>".equalsIgnoreCase(ssid)
                && !WifiManager.UNKNOWN_SSID.equals(ssid);
    }

    private static String ipv4FromLinkProperties(LinkProperties lp) {
        if (lp == null) return null;
        for (LinkAddress la : lp.getLinkAddresses()) {
            if (la.getAddress() instanceof Inet4Address && !la.getAddress().isLoopbackAddress()) {
                String ip = la.getAddress().getHostAddress();
                if (ip != null && !ip.startsWith("169.254.")) return ip;
            }
        }
        return null;
    }

    private static String getWifiInterfaceIpv4() {
        try {
            for (NetworkInterface ni : Collections.list(NetworkInterface.getNetworkInterfaces())) {
                String name = ni.getName() == null ? "" : ni.getName().toLowerCase(Locale.US);
                if (!ni.isUp() || ni.isLoopback()
                        || !(name.startsWith("wlan") || name.startsWith("wifi"))) {
                    continue;
                }
                for (java.net.InetAddress addr : Collections.list(ni.getInetAddresses())) {
                    if (addr instanceof Inet4Address && !addr.isLoopbackAddress()) {
                        String ip = addr.getHostAddress();
                        if (ip != null && !ip.startsWith("169.254.")) return ip;
                    }
                }
            }
        } catch (Exception ignored) {}
        return null;
    }

    public static DeviceInfo readDeviceInfo() {
        DeviceInfo out = new DeviceInfo();
        out.manufacturer = safe(Build.MANUFACTURER);
        out.model = safe(Build.MODEL);
        out.androidVersion = safe(Build.VERSION.RELEASE);
        out.sdk = Build.VERSION.SDK_INT;
        out.uptimeMs = SystemClock.elapsedRealtime();
        out.profile = out.manufacturer + " " + out.model;
        out.hardwareSoc = safe(Build.HARDWARE);
        out.board = safe(Build.BOARD);
        out.arch = safe(System.getProperty("os.arch"));
        out.kernelVersion = safe(System.getProperty("os.version"));
        return out;
    }

    public static String getLocalIpv4() {
        try {
            for (NetworkInterface ni : Collections.list(NetworkInterface.getNetworkInterfaces())) {
                if (!ni.isUp() || ni.isLoopback()) continue;
                for (java.net.InetAddress addr : Collections.list(ni.getInetAddresses())) {
                    if (addr instanceof Inet4Address && !addr.isLoopbackAddress()) {
                        String ip = addr.getHostAddress();
                        if (ip != null && !ip.startsWith("169.254.")) return ip;
                    }
                }
            }
        } catch (Exception ignored) {}
        return "N/A";
    }

    public static boolean isNewlandMt93() {
        String joined = (safe(Build.MANUFACTURER) + " " + safe(Build.MODEL) + " "
                + safe(Build.PRODUCT) + " " + safe(Build.DEVICE)).toUpperCase(Locale.US);
        return joined.contains("NEWLAND") || joined.contains("MT93") || joined.contains("NLS-MT93");
    }

    private static boolean isUsableRssi(int rssi) {
        return rssi > -127 && rssi <= 0;
    }

    private static boolean validBatteryProperty(int value) {
        return value != Integer.MIN_VALUE && value != Integer.MAX_VALUE;
    }

    private static Double readNumber(String path) {
        try {
            File f = new File(path);
            if (!f.isFile() || !f.canRead()) return null;
            try (BufferedReader reader = new BufferedReader(new FileReader(f))) {
                String line = reader.readLine();
                if (line == null) return null;
                return Double.parseDouble(line.trim());
            }
        } catch (Throwable ignored) {
            return null;
        }
    }

    private static double readPowerProfileCapacityMah(Context context) {
        try {
            Class<?> clazz = Class.forName("com.android.internal.os.PowerProfile");
            Constructor<?> ctor = clazz.getConstructor(Context.class);
            Object profile = ctor.newInstance(context);
            Method method = clazz.getMethod("getBatteryCapacity");
            Object value = method.invoke(profile);
            if (value instanceof Double) {
                double mah = (Double) value;
                if (mah >= 500.0 && mah <= 30000.0) return mah;
            }
        } catch (Throwable ignored) {}
        return Double.NaN;
    }

    private static boolean isPositive(double value) {
        return !Double.isNaN(value) && !Double.isInfinite(value) && value > 0;
    }

    private static double bytesToGb(long bytes) {
        return bytes / 1024.0 / 1024.0 / 1024.0;
    }

    private static String safe(String value) {
        return value == null || value.trim().isEmpty() ? "Unknown" : value.trim();
    }

    public static String fmt1(double value) {
        return String.format(Locale.US, "%.1f", value);
    }

    public static String fmt2(double value) {
        return String.format(Locale.US, "%.2f", value);
    }
}
