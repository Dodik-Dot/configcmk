package com.bcp.checkmkagent;

import android.content.Context;
import android.content.SharedPreferences;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Locale;

public final class BatteryHistory {
    private static final String PREFS = "cmkagent_battery_history";
    // Gunakan v3 agar cache rusak (2946 mAh) otomatis ter-reset bersih
    private static final String KEY = "full_capacity_samples_v3";
    private static final String KEY_LAST_SAMPLE_TIME = "last_sample_time_ms";
    private static final int MAX_SAMPLES = 9;
    private static final long MIN_SAMPLE_INTERVAL_MS = 15 * 60 * 1000L; // 15 menit antar sampel

    private BatteryHistory() {}

    public static void clear(Context context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .remove(KEY)
                .remove(KEY_LAST_SAMPLE_TIME)
                .apply();
    }

    public static double addAndMedian(Context context, double value) {
        if (Double.isNaN(value) || Double.isInfinite(value) || value <= 0) return getMedian(context);
        SharedPreferences p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);

        long now = System.currentTimeMillis();
        long lastTime = p.getLong(KEY_LAST_SAMPLE_TIME, 0L);

        // Hanya tambahkan sampel baru jika jeda sudah lebih dari 15 menit
        if (now - lastTime >= MIN_SAMPLE_INTERVAL_MS || lastTime == 0L) {
            List<Double> samples = parse(p.getString(KEY, ""));
            samples.add(value);
            while (samples.size() > MAX_SAMPLES) samples.remove(0);

            StringBuilder saved = new StringBuilder();
            for (double sample : samples) {
                if (saved.length() > 0) saved.append(',');
                saved.append(String.format(Locale.US, "%.2f", sample));
            }
            p.edit()
                    .putString(KEY, saved.toString())
                    .putLong(KEY_LAST_SAMPLE_TIME, now)
                    .apply();
        }

        return getMedian(context);
    }

    public static double getMedian(Context context) {
        SharedPreferences p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        List<Double> samples = parse(p.getString(KEY, ""));
        if (samples.isEmpty()) return Double.NaN;

        List<Double> sorted = new ArrayList<>(samples);
        Collections.sort(sorted);
        int n = sorted.size();
        if (n % 2 == 1) return sorted.get(n / 2);
        return (sorted.get(n / 2 - 1) + sorted.get(n / 2)) / 2.0;
    }

    public static int size(Context context) {
        return parse(context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getString(KEY, "")).size();
    }

    private static List<Double> parse(String raw) {
        List<Double> values = new ArrayList<>();
        if (raw == null || raw.trim().isEmpty()) return values;
        for (String token : raw.split(",")) {
            try {
                double v = Double.parseDouble(token.trim());
                if (v > 0) values.add(v);
            } catch (Exception ignored) {}
        }
        return values;
    }
}
