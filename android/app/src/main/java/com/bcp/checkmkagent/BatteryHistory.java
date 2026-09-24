package com.bcp.checkmkagent;

import android.content.Context;
import android.content.SharedPreferences;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Locale;

public final class BatteryHistory {
    private static final String PREFS = "cmkagent_battery_history";
    private static final String KEY = "full_capacity_samples";
    private static final int MAX_SAMPLES = 9;

    private BatteryHistory() {}

    public static double addAndMedian(Context context, double value) {
        if (Double.isNaN(value) || Double.isInfinite(value) || value <= 0) return Double.NaN;
        SharedPreferences p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        List<Double> samples = parse(p.getString(KEY, ""));
        samples.add(value);
        while (samples.size() > MAX_SAMPLES) samples.remove(0);

        StringBuilder saved = new StringBuilder();
        for (double sample : samples) {
            if (saved.length() > 0) saved.append(',');
            saved.append(String.format(Locale.US, "%.2f", sample));
        }
        p.edit().putString(KEY, saved.toString()).apply();

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
