package com.bcp.checkmkagent;

import android.content.Context;
import android.content.SharedPreferences;

public final class AgentStats {
    private static final String PREFS = "cmkagent_stats";
    private static final String K_START = "start_ms";
    private static final String K_LAST_PULL = "last_pull_ms";
    private static final String K_LAST_CLIENT = "last_client";
    private static final String K_ACCEPTED = "accepted";
    private static final String K_REJECTED = "rejected";
    private static final String K_LAST_REJECTED = "last_rejected";
    private static final String K_RUNNING = "running";

    private AgentStats() {}

    public static final class Snapshot {
        public long startMs;
        public long lastPullMs;
        public String lastClient = "-";
        public long accepted;
        public long rejected;
        public String lastRejected = "-";
        public boolean running;
    }

    public static void recordStart(Context context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit().putLong(K_START, System.currentTimeMillis()).putBoolean(K_RUNNING, true).apply();
    }

    public static void recordStop(Context context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit().putBoolean(K_RUNNING, false).apply();
    }

    public static void recordAccepted(Context context, String ip) {
        SharedPreferences p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        long count = p.getLong(K_ACCEPTED, 0L) + 1L;
        p.edit()
                .putLong(K_LAST_PULL, System.currentTimeMillis())
                .putString(K_LAST_CLIENT, ip == null ? "-" : ip)
                .putLong(K_ACCEPTED, count)
                .apply();
    }

    public static void recordRejected(Context context, String ip) {
        SharedPreferences p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        long count = p.getLong(K_REJECTED, 0L) + 1L;
        p.edit()
                .putLong(K_REJECTED, count)
                .putString(K_LAST_REJECTED, ip == null ? "-" : ip)
                .apply();
    }

    public static Snapshot read(Context context) {
        SharedPreferences p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        Snapshot s = new Snapshot();
        s.startMs = p.getLong(K_START, 0L);
        s.lastPullMs = p.getLong(K_LAST_PULL, 0L);
        s.lastClient = p.getString(K_LAST_CLIENT, "-");
        s.accepted = p.getLong(K_ACCEPTED, 0L);
        s.rejected = p.getLong(K_REJECTED, 0L);
        s.lastRejected = p.getString(K_LAST_REJECTED, "-");
        s.running = p.getBoolean(K_RUNNING, false);
        return s;
    }
}
