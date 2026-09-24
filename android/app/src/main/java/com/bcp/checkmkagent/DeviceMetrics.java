package com.bcp.checkmkagent;

import android.app.ActivityManager;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.BatteryManager;
import android.os.Environment;
import android.os.StatFs;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.lang.reflect.Constructor;
import java.lang.reflect.Method;
import java.util.Locale;

public final class DeviceMetrics {
    private DeviceMetrics() {}

    public static final class BatteryInfo {
        public int level = -1;
        public double temperatureC = Double.NaN;
        public double voltageV = Double.NaN;
        public String status = "Unknown";
        public double chargeCounterMah = Double.NaN;
        public double designCapacityMah = Double.NaN;
        public double fullCapacityMah = Double.NaN;
        public boolean fullCapacityEstimated = false;
        public double healthPercent = Double.NaN;
    }

    public static final class UsageInfo {
        public double totalGb;
        public double freeGb;
        public double usedGb;
        public double usedPercent;
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

        BatteryManager bm = (BatteryManager) context.getSystemService(Context.BATTERY_SERVICE);
        if (bm != null) {
            int chargeCounterUah = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CHARGE_COUNTER);
            if (chargeCounterUah > 0 && chargeCounterUah != Integer.MIN_VALUE) {
                out.chargeCounterMah = chargeCounterUah / 1000.0;
            }
        }

        // Prefer vendor/kernel values when readable.
        out.designCapacityMah = firstValid(
                readChargeCapacityMah("/sys/class/power_supply/battery/charge_full_design"),
                readEnergyCapacityMah("/sys/class/power_supply/battery/energy_full_design", out.voltageV),
                readPowerProfileCapacityMah(context),
                AgentConfig.getDesignCapacityMah(context)
        );

        out.fullCapacityMah = firstValid(
                readChargeCapacityMah("/sys/class/power_supply/battery/charge_full"),
                readEnergyCapacityMah("/sys/class/power_supply/battery/energy_full", out.voltageV)
        );

        if (!isPositive(out.fullCapacityMah)
                && isPositive(out.chargeCounterMah)
                && out.level >= 5 && out.level <= 100) {
            out.fullCapacityMah = out.chargeCounterMah / (out.level / 100.0);
            out.fullCapacityEstimated = true;
        }

        if (isPositive(out.designCapacityMah) && isPositive(out.fullCapacityMah)) {
            out.healthPercent = clamp(out.fullCapacityMah / out.designCapacityMah * 100.0, 0.0, 120.0);
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

    private static double readChargeCapacityMah(String path) {
        Double raw = readNumber(path);
        if (raw == null || raw <= 0) return Double.NaN;
        // Most Android kernels expose charge_* in uAh. Some expose mAh.
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
            // Hidden/vendor APIs can be blocked. Fallbacks are intentional.
        }
        return Double.NaN;
    }

    private static double firstValid(double... values) {
        for (double value : values) {
            if (isPositive(value)) return value;
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

    public static String fmt1(double value) {
        return String.format(Locale.US, "%.1f", value);
    }

    public static String fmt2(double value) {
        return String.format(Locale.US, "%.2f", value);
    }
}
