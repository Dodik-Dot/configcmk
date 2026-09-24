package com.bcp.checkmkagent;

import android.content.Context;

import java.util.Locale;

public final class CheckmkOutput {
    private CheckmkOutput() {}

    public static String build(Context context) {
        DeviceMetrics.BatteryInfo battery = DeviceMetrics.readBattery(context);
        DeviceMetrics.UsageInfo ram = DeviceMetrics.readRam(context);
        DeviceMetrics.UsageInfo storage = DeviceMetrics.readStorage();

        StringBuilder sb = new StringBuilder();
        sb.append("<<<check_mk>>>\n");
        sb.append("Version: 1.0.0\n");
        sb.append("AgentOS: android\n");
        sb.append("Hostname: ").append(AgentConfig.getHostname(context)).append("\n\n");
        sb.append("<<<local:sep(0)>>>\n");
        sb.append(buildBatteryLine(battery)).append('\n');
        sb.append(buildRamLine(ram)).append('\n');
        sb.append(buildStorageLine(storage)).append('\n');
        return sb.toString();
    }

    private static String buildBatteryLine(DeviceMetrics.BatteryInfo b) {
        int state = 0;
        if (b.level >= 0) {
            if (b.level < 15) state = Math.max(state, 2);
            else if (b.level < 30) state = Math.max(state, 1);
        }
        if (!Double.isNaN(b.healthPercent)) {
            if (b.healthPercent <= 20.0) state = Math.max(state, 2);
            else if (b.healthPercent < 60.0) state = Math.max(state, 1);
        }

        String status = stateName(state);
        String level = b.level >= 0 ? b.level + "%" : "N/A";
        String design = !Double.isNaN(b.designCapacityMah)
                ? Math.round(b.designCapacityMah) + " mAh" : "N/A";
        String full = !Double.isNaN(b.fullCapacityMah)
                ? Math.round(b.fullCapacityMah) + " mAh" + (b.fullCapacityEstimated ? " (Est.)" : "")
                : "N/A";
        String health = !Double.isNaN(b.healthPercent)
                ? String.format(Locale.US, "%.1f%%", b.healthPercent) : "N/A";
        String temp = !Double.isNaN(b.temperatureC)
                ? String.format(Locale.US, "%.1f C", b.temperatureC) : "N/A";
        String voltage = !Double.isNaN(b.voltageV)
                ? String.format(Locale.US, "%.2f V", b.voltageV) : "N/A";

        String metrics = b.level >= 0 ? "battery_level=" + b.level : "-";
        if (!Double.isNaN(b.healthPercent)) {
            metrics += "|battery_health=" + String.format(Locale.US, "%.1f", b.healthPercent);
        }

        return state + " \"Health_Battery\" " + metrics
                + " Status : " + status
                + " | Battery Level : " + level
                + " | Design Capacity : " + design
                + " | Current Full Capacity : " + full
                + " | Health : " + health
                + " | Temperature : " + temp
                + " | Voltage : " + voltage
                + " | Current Status Baterai : " + b.status;
    }

    private static String buildRamLine(DeviceMetrics.UsageInfo r) {
        int state = thresholdHigh(r.usedPercent, 85.0, 95.0);
        return state + " \"RAM_Usage\" ram_used=" + Math.round(r.usedPercent)
                + " Status : " + stateName(state)
                + " | Used : " + Math.round(r.usedPercent) + "%"
                + " | Free : " + DeviceMetrics.fmt2(r.freeGb) + " GB"
                + " | Total : " + DeviceMetrics.fmt2(r.totalGb) + " GB";
    }

    private static String buildStorageLine(DeviceMetrics.UsageInfo s) {
        int state = thresholdHigh(s.usedPercent, 85.0, 95.0);
        return state + " \"Storage_Usage\" storage_used=" + Math.round(s.usedPercent)
                + " Status : " + stateName(state)
                + " | Used : " + Math.round(s.usedPercent) + "%"
                + " | Free : " + DeviceMetrics.fmt2(s.freeGb) + " GB"
                + " | Total : " + DeviceMetrics.fmt2(s.totalGb) + " GB";
    }

    private static int thresholdHigh(double value, double warn, double crit) {
        if (value >= crit) return 2;
        if (value >= warn) return 1;
        return 0;
    }

    private static String stateName(int state) {
        switch (state) {
            case 1: return "WARNING";
            case 2: return "CRITICAL";
            case 3: return "UNKNOWN";
            default: return "OK";
        }
    }
}
