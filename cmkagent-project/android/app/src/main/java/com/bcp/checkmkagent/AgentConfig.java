package com.bcp.checkmkagent;

import android.content.Context;
import android.content.SharedPreferences;
import android.os.Build;

import java.util.Locale;

public final class AgentConfig {
    public static final String PREFS = "cmkagent_prefs";
    public static final String KEY_HOSTNAME = "hostname";
    public static final String KEY_PORT = "port";
    public static final String KEY_DESIGN_CAPACITY = "design_capacity_mah";
    public static final String KEY_AUTOSTART = "autostart";

    private AgentConfig() {}

    public static String getHostname(Context context) {
        SharedPreferences p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        String fallback = sanitizeHostname("PDA-" + Build.MODEL);
        String value = p.getString(KEY_HOSTNAME, fallback);
        if (value == null || value.trim().isEmpty()) return fallback;
        return sanitizeHostname(value.trim());
    }

    public static int getPort(Context context) {
        SharedPreferences p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        int port = p.getInt(KEY_PORT, 6556);
        return (port >= 1 && port <= 65535) ? port : 6556;
    }

    public static double getDesignCapacityMah(Context context) {
        SharedPreferences p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        long bits = p.getLong(KEY_DESIGN_CAPACITY, Double.doubleToRawLongBits(0.0));
        double value = Double.longBitsToDouble(bits);
        return value > 0 ? value : 0.0;
    }

    public static boolean isAutoStart(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getBoolean(KEY_AUTOSTART, true);
    }

    public static void save(Context context, String hostname, int port,
                            double designCapacityMah, boolean autoStart) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putString(KEY_HOSTNAME, sanitizeHostname(hostname))
                .putInt(KEY_PORT, port)
                .putLong(KEY_DESIGN_CAPACITY, Double.doubleToRawLongBits(Math.max(0.0, designCapacityMah)))
                .putBoolean(KEY_AUTOSTART, autoStart)
                .apply();
    }

    public static String sanitizeHostname(String value) {
        if (value == null) return "ANDROID-PDA";
        String cleaned = value.trim().toUpperCase(Locale.US)
                .replaceAll("[^A-Z0-9._-]", "-")
                .replaceAll("-+", "-");
        if (cleaned.isEmpty()) return "ANDROID-PDA";
        return cleaned.length() > 63 ? cleaned.substring(0, 63) : cleaned;
    }
}
