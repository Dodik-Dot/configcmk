package com.bcp.checkmkagent;

import android.app.ActivityManager;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
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
import java.util.Locale;

public final class DeviceMetrics {

    private DeviceMetrics() {}

    public static final class BatteryInfo {
        public int level = -1;
        public double temperatureC = Double.NaN;
        public double voltageV = Double.NaN;
        public String status = "Unknown";
        public double chargeCounterMah = Double.NaN;
        public double currentNowMa = Double.NaN;
        public double currentAverageMa = Double.NaN;
        public double designCapacityMah = Double.NaN;
        public String designCapacitySource = "Unavailable";
        public double fullCapacityMah = Double.NaN;
        public double fullChargeVoltageV = Double.NaN;
        public String fullCapacitySource = "Unavailable";
        public boolean fullCapacityEstimated = false;
        public double healthPercent = Double.NaN;
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
        public String ssid = "Unavailable";
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
    }

    public static BatteryInfo readBattery(Context context) {
        BatteryInfo out = new BatteryInfo();
        if (context == null) return out;

        try {
            Intent battery = context.registerReceiver(null, new IntentFilter(Intent.ACTION_BATTERY_CHANGED));
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

        if (out.cycleCount < 0) {
            String[] cyclePaths = {
                    "/sys/class/power_supply/battery/cycle_count",
                    "/sys/class/power_supply/bms/cycle_count",
                    "/sys/class/power_supply/battery/battery_cycle",
                    "/sys/class/power_supply/battery/device/cycle_count",
                    "/sys/devices/platform/charger/power_supply/battery/cycle_count"
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

        BatteryHistory.updateChargeSession(context, out.level, out.status, out.chargeCounterMah, out.voltageV);
        out.estimateSamples = BatteryHistory.getSampleCount(context);

        try {
            double manual = AgentConfig.getDesignCapacityMah(context);
            if (isPositive(manual)) {
                out.designCapacityMah = manual;
                out.designCapacitySource = "Manual Override";
            } else {
                double profileVal = readPowerProfileCapacityMah(context);
                if (isPositive(profileVal)) {
                    out.designCapacityMah = profileVal;
                    out.designCapacitySource = "Android OS PowerProfile";
                } else {
                    String[] designPaths = {
                            "/sys/class/power_supply/battery/charge_full_design",
                            "/sys/class/power_supply/bms/charge_full_design",
                            "/sys/class/power_supply/battery/device/charge_full_design",
                            "/sys/devices/platform/charger/power_supply/battery/charge_full_design",
                            "/sys/class/power_supply/battery/design_capacity",
                            "/sys/class/power_supply/battery/battery_full_design"
                    };
                    for (String path : designPaths) {
                        double kernelDesign = readChargeCapacityMah(path);
                        if (isPositive(kernelDesign)) {
                            out.designCapacityMah = kernelDesign;
                            out.designCapacitySource = "Kernel (" + path.substring(path.lastIndexOf('/') + 1) + ")";
                            break;
                        }
                    }
                }
            }
        } catch (Throwable ignored) {}

        String[] hwSohPaths = {
                "/sys/class/power_supply/battery/soh",
                "/sys/class/power_supply/battery/battery_soh",
                "/sys/class/power_supply/bms/battery_soh"
        };
        for (String p : hwSohPaths) {
            Double soh = readNumber(p);
            if (soh != null && soh > 10.0 && soh <= 100.0) {
                out.healthPercent = soh;
                if (isPositive(out.designCapacityMah)) {
                    out.fullCapacityMah = (soh / 100.0) * out.designCapacityMah;
                }
                out.fullCapacitySource = "Hardware Fuel Gauge (BMS)";
                return out;
            }
        }

        double calibratedFull = BatteryHistory.getCalibratedFullChargeMah(context);
        double medianAccuMeter = BatteryHistory.getMedianCapacity(context);

        if (isPositive(calibratedFull) && ("Full".equalsIgnoreCase(out.status) || out.level == 100)) {
            out.fullCapacityMah = calibratedFull;
            out.fullChargeVoltageV = BatteryHistory.getCalibratedFullVoltage(context);
            out.fullCapacitySource = "100% Full Charge Calibration";
        } else if (isPositive(medianAccuMeter)) {
            out.fullCapacityMah = medianAccuMeter;
            out.fullChargeVoltageV = BatteryHistory.getCalibratedFullVoltage(context);
            out.fullCapacitySource = "AccuMeter Median (" + out.estimateSamples + " sessions)";
            out.fullCapacityEstimated = true;
        } else {
            String[] fullPaths = {
                    "/sys/class/power_supply/battery/charge_full",
                    "/sys/class/power_supply/bms/charge_full",
                    "/sys/class/power_supply/main/charge_full"
            };
            for (String path : fullPaths) {
                double full = readChargeCapacityMah(path);
                if (isPositive(full)) {
                    out.fullCapacityMah = full;
                    out.fullCapacitySource = "Kernel " + path.substring(path.lastIndexOf('/') + 1);
                    break;
                }
            }
        }

        if (!isPositive(out.fullCapacityMah)) {
            if (isPositive(calibratedFull)) {
                out.fullCapacityMah = calibratedFull;
                out.fullCapacitySource = "Historical Full Calibration";
            } else if (out.level >= 20 && isPositive(out.chargeCounterMah)) {
                out.fullCapacityMah = out.chargeCounterMah / (out.level / 100.0);
                out.fullCapacitySource = "Initial Dynamic (" + out.level + "% State)";
                out.fullCapacityEstimated = true;
            }
        }

        if (isPositive(out.designCapacityMah) && isPositive(out.fullCapacityMah)) {
            out.healthPercent = Math.min(100.0, (out.fullCapacityMah / out.designCapacityMah) * 100.0);
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

            if (out.connected && "Unavailable".equals(out.ssid)) {
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

    private static boolean isUsableRssi(int rssi) {
        return rssi > -127 && rssi <= 0;
    }

    private static boolean validBatteryProperty(int value) {
        return value != Integer.MIN_VALUE && value != Integer.MAX_VALUE;
    }

    private static double readChargeCapacityMah(String path) {
        Double raw = readNumber(path);
        if (raw == null || raw <= 0) return Double.NaN;
        if (raw > 100000) return raw / 1000.0;
        if (raw >= 500 && raw <= 30000) return raw;
        return Double.NaN;
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
