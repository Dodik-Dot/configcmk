package com.bcp.checkmkagent;

import android.app.ActivityManager;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
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
        public String fullCapacitySource = "Unavailable";
        public boolean fullCapacityEstimated = false;
        public double healthPercent = Double.NaN;
        public int estimateSamples = 0;
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

            int status = battery.getIntExtra(BatteryManager.EXTRA_STATUS,
                    BatteryManager.BATTERY_STATUS_UNKNOWN);
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

        BatteryManager bm = (BatteryManager) context.getSystemService(Context.BATTERY_SERVICE);
        if (bm != null) {
            int chargeCounterUah = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CHARGE_COUNTER);
            if (validBatteryProperty(chargeCounterUah) && chargeCounterUah > 0) {
                out.chargeCounterMah = chargeCounterUah / 1000.0;
            }

            int currentNowUa = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CURRENT_NOW);
            if (validBatteryProperty(currentNowUa)) out.currentNowMa = currentNowUa / 1000.0;

            int currentAvgUa = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CURRENT_AVERAGE);
            if (validBatteryProperty(currentAvgUa)) out.currentAverageMa = currentAvgUa / 1000.0;
        }

        // A manually configured value wins. It is useful when a vendor exposes an incorrect profile.
        double manual = AgentConfig.getDesignCapacityMah(context);
        if (isPositive(manual)) {
            out.designCapacityMah = manual;
            out.designCapacitySource = "Manual";
        } else {
            double value = readChargeCapacityMah("/sys/class/power_supply/battery/charge_full_design");
            if (isPositive(value)) {
                out.designCapacityMah = value;
                out.designCapacitySource = "Kernel charge_full_design";
            } else {
                value = readEnergyCapacityMah(
                        "/sys/class/power_supply/battery/energy_full_design", out.voltageV);
                if (isPositive(value)) {
                    out.designCapacityMah = value;
                    out.designCapacitySource = "Kernel energy_full_design";
                } else {
                    value = readPowerProfileCapacityMah(context);
                    if (isPositive(value)) {
                        out.designCapacityMah = value;
                        out.designCapacitySource = "Android PowerProfile";
                    } else if (isNewlandMt93()) {
                        out.designCapacityMah = 5000.0;
                        out.designCapacitySource = "Newland MT93 profile";
                    }
                }
            }
        }

        double full = readChargeCapacityMah("/sys/class/power_supply/battery/charge_full");
        if (isPositive(full)) {
            out.fullCapacityMah = full;
            out.fullCapacitySource = "Kernel charge_full";
        } else {
            full = readEnergyCapacityMah("/sys/class/power_supply/battery/energy_full", out.voltageV);
            if (isPositive(full)) {
                out.fullCapacityMah = full;
                out.fullCapacitySource = "Kernel energy_full";
            }
        }

        // Fallback estimate. Mid-charge samples are typically more useful than samples near 0/100%.
        if (!isPositive(out.fullCapacityMah)
                && isPositive(out.chargeCounterMah)
                && out.level >= 20 && out.level <= 95) {
            double estimate = out.chargeCounterMah / (out.level / 100.0);
            boolean plausible = !isPositive(out.designCapacityMah)
                    || (estimate >= out.designCapacityMah * 0.30
                    && estimate <= out.designCapacityMah * 1.20);
            if (plausible) {
                out.fullCapacityMah = BatteryHistory.addAndMedian(context, estimate);
                out.estimateSamples = BatteryHistory.size(context);
                out.fullCapacityEstimated = true;
                out.fullCapacitySource = "Estimated median (" + out.estimateSamples + " samples)";
            }
        }

        if (isPositive(out.designCapacityMah) && isPositive(out.fullCapacityMah)) {
            out.healthPercent = clamp(
                    out.fullCapacityMah / out.designCapacityMah * 100.0, 0.0, 120.0);
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
        try {
            WifiManager manager = (WifiManager) context.getApplicationContext()
                    .getSystemService(Context.WIFI_SERVICE);
            if (manager == null || !manager.isWifiEnabled()) return out;
            WifiInfo info = manager.getConnectionInfo();
            if (info == null || info.getNetworkId() == -1) return out;

            out.connected = true;
            String ssid = info.getSSID();
            if (ssid != null && !ssid.isEmpty() && !"<unknown ssid>".equalsIgnoreCase(ssid)) {
                if (ssid.startsWith("\"") && ssid.endsWith("\"") && ssid.length() >= 2) {
                    ssid = ssid.substring(1, ssid.length() - 1);
                }
                out.ssid = ssid;
            } else {
                out.ssid = "Connected (SSID permission unavailable)";
            }
            out.rssi = info.getRssi();
            out.linkSpeedMbps = info.getLinkSpeed();
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                out.frequencyMhz = info.getFrequency();
            }
        } catch (SecurityException ignored) {
            out.ssid = "Permission required";
        } catch (Exception ignored) {}
        return out;
    }

    public static DeviceInfo readDeviceInfo() {
        DeviceInfo out = new DeviceInfo();
        out.manufacturer = safe(Build.MANUFACTURER);
        out.model = safe(Build.MODEL);
        out.androidVersion = safe(Build.VERSION.RELEASE);
        out.sdk = Build.VERSION.SDK_INT;
        out.uptimeMs = SystemClock.elapsedRealtime();
        out.profile = isNewlandMt93() ? "Newland MT93" : "Generic Android";
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
                + safe(Build.PRODUCT)).toUpperCase(Locale.US);
        return joined.contains("NEWLAND") && joined.contains("MT93") || joined.contains("MT93");
    }

    private static boolean validBatteryProperty(int value) {
        return value != Integer.MIN_VALUE && value != Integer.MAX_VALUE;
    }

    private static double readChargeCapacityMah(String path) {
        Double raw = readNumber(path);
        if (raw == null || raw <= 0) return Double.NaN;
        // Most Android kernels expose charge_* in uAh. Some expose mAh directly.
        if (raw > 100000) return raw / 1000.0;
        if (raw > 1000 && raw < 30000) return raw;
        return Double.NaN;
    }

    private static double readEnergyCapacityMah(String path, double voltageV) {
        Double raw = readNumber(path);
        if (raw == null || raw <= 0 || !isPositive(voltageV)) return Double.NaN;
        // Most energy_* nodes are uWh. mAh = uWh / mV.
        double voltageMv = voltageV * 1000.0;
        if (raw > 100000) return raw / voltageMv;
        return Double.NaN;
    }

    private static Double readNumber(String path) {
        File f = new File(path);
        if (!f.isFile() || !f.canRead()) return null;
        try (BufferedReader reader = new BufferedReader(new FileReader(f))) {
            String line = reader.readLine();
            if (line == null) return null;
            return Double.parseDouble(line.trim());
        } catch (Exception ignored) {
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
                return mah > 0 ? mah : Double.NaN;
            }
        } catch (Throwable ignored) {
            // Hidden/vendor APIs can be blocked. Other fallbacks are intentional.
        }
        return Double.NaN;
    }

    private static boolean isPositive(double value) {
        return !Double.isNaN(value) && !Double.isInfinite(value) && value > 0;
    }

    private static double clamp(double value, double min, double max) {
        return Math.max(min, Math.min(max, value));
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
