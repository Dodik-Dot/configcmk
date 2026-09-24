package com.bcp.checkmkagent;

import android.Manifest;
import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Build;
import android.os.Bundle;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.EditText;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Locale;

public class MainActivity extends Activity {
    private static final int C_BG = Color.rgb(15, 23, 32);
    private static final int C_CARD = Color.rgb(24, 35, 46);
    private static final int C_CARD_ALT = Color.rgb(20, 30, 40);
    private static final int C_TEXT = Color.rgb(244, 247, 249);
    private static final int C_MUTED = Color.rgb(170, 183, 195);
    private static final int C_GREEN = Color.rgb(91, 207, 126);
    private static final int C_WARN = Color.rgb(246, 200, 95);
    private static final int C_CRIT = Color.rgb(230, 106, 106);
    private static final int C_LINE = Color.rgb(45, 61, 75);

    private EditText hostnameInput;
    private EditText portInput;
    private EditText designCapacityInput;
    private EditText allowedServerInput;
    private CheckBox autoStartInput;

    private TextView agentBadge;
    private TextView agentText;
    private TextView batteryHeadline;
    private TextView batteryText;
    private TextView systemText;
    private TextView networkText;
    private TextView deviceText;
    private TextView diagnosticsText;
    private ProgressBar batteryProgress;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().setStatusBarColor(C_BG);
        getWindow().setNavigationBarColor(C_BG);
        setContentView(buildUi());
        loadConfig();
        requestRuntimePermissionsIfNeeded();
        updateDashboard();
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (agentText != null) updateDashboard();
    }

    private ScrollView buildUi() {
        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        scroll.setBackgroundColor(C_BG);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(16), dp(18), dp(16), dp(28));
        scroll.addView(root, new ScrollView.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT));

        root.addView(buildHeader());
        root.addView(space(14));

        LinearLayout agentCard = card("AGENT", "Pull listener & connection status");
        agentBadge = badge("STARTING", C_WARN);
        agentCard.addView(agentBadge, wrap());
        agentText = bodyText();
        agentText.setPadding(0, dp(12), 0, 0);
        agentCard.addView(agentText, wrap());
        root.addView(agentCard, matchWrapMargin(0, 0, 0, 12));

        LinearLayout batteryCard = card("BATTERY", "Level, health estimate & thermal status");
        batteryHeadline = new TextView(this);
        batteryHeadline.setTextColor(C_TEXT);
        batteryHeadline.setTextSize(25);
        batteryHeadline.setTypeface(Typeface.DEFAULT_BOLD);
        batteryCard.addView(batteryHeadline, wrap());
        batteryProgress = new ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal);
        batteryProgress.setMax(100);
        batteryProgress.setProgressTintList(ColorStateList.valueOf(C_GREEN));
        batteryProgress.setProgressBackgroundTintList(ColorStateList.valueOf(C_LINE));
        LinearLayout.LayoutParams bp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, dp(8));
        bp.setMargins(0, dp(10), 0, dp(10));
        batteryCard.addView(batteryProgress, bp);
        batteryText = bodyText();
        batteryCard.addView(batteryText, wrap());
        root.addView(batteryCard, matchWrapMargin(0, 0, 0, 12));

        LinearLayout systemCard = card("SYSTEM", "RAM & internal storage");
        systemText = bodyText();
        systemCard.addView(systemText, wrap());
        root.addView(systemCard, matchWrapMargin(0, 0, 0, 12));

        LinearLayout networkCard = card("NETWORK", "Warehouse Wi-Fi visibility");
        networkText = bodyText();
        networkCard.addView(networkText, wrap());
        root.addView(networkCard, matchWrapMargin(0, 0, 0, 12));

        LinearLayout deviceCard = card("DEVICE", "Hardware & Android profile");
        deviceText = bodyText();
        deviceCard.addView(deviceText, wrap());
        root.addView(deviceCard, matchWrapMargin(0, 0, 0, 12));

        LinearLayout settingsCard = card("SETTINGS", "Changes take effect after Save & Start");
        hostnameInput = input(settingsCard, "Hostname Checkmk", InputType.TYPE_CLASS_TEXT,
                "Contoh: PDA-10-FAUZI");
        portInput = input(settingsCard, "TCP Port", InputType.TYPE_CLASS_NUMBER, "6556");
        designCapacityInput = input(settingsCard,
                "Design Capacity (mAh, 0 = auto)",
                InputType.TYPE_CLASS_NUMBER | InputType.TYPE_NUMBER_FLAG_DECIMAL,
                "MT93 auto profile = 5000 mAh");
        allowedServerInput = input(settingsCard,
                "Allowed Checkmk Server IP",
                InputType.TYPE_CLASS_TEXT,
                "Kosong = semua IP; produksi: 192.168.55.112");

        autoStartInput = new CheckBox(this);
        autoStartInput.setText("Start agent otomatis setelah boot");
        autoStartInput.setTextColor(C_TEXT);
        autoStartInput.setButtonTintList(ColorStateList.valueOf(C_GREEN));
        autoStartInput.setPadding(0, dp(6), 0, dp(8));
        settingsCard.addView(autoStartInput, matchWrap());

        Button start = actionButton("SAVE & START AGENT", C_GREEN, Color.rgb(10, 32, 18));
        start.setOnClickListener(v -> saveAndStart());
        settingsCard.addView(start, matchWrapMargin(0, 4, 0, 8));

        LinearLayout actions = new LinearLayout(this);
        actions.setOrientation(LinearLayout.HORIZONTAL);
        Button refresh = actionButton("REFRESH", C_CARD_ALT, C_TEXT);
        refresh.setOnClickListener(v -> updateDashboard());
        Button preview = actionButton("AGENT OUTPUT", C_CARD_ALT, C_TEXT);
        preview.setOnClickListener(v -> showAgentOutput());
        actions.addView(refresh, weightButton());
        LinearLayout.LayoutParams second = weightButton();
        second.setMargins(dp(8), 0, 0, 0);
        actions.addView(preview, second);
        settingsCard.addView(actions, matchWrapMargin(0, 0, 0, 8));

        Button stop = actionButton("STOP AGENT", Color.rgb(82, 42, 47), Color.rgb(255, 205, 210));
        stop.setOnClickListener(v -> {
            stopService(new Intent(this, CheckmkAgentService.class));
            AgentStats.recordStop(this);
            Toast.makeText(this, "Agent dihentikan", Toast.LENGTH_SHORT).show();
            agentText.postDelayed(this::updateDashboard, 250);
        });
        settingsCard.addView(stop, matchWrap());
        root.addView(settingsCard, matchWrapMargin(0, 0, 0, 12));

        LinearLayout diagCard = card("DIAGNOSTICS", "Useful when Checkmk cannot pull the PDA");
        diagnosticsText = bodyText();
        diagnosticsText.setTextIsSelectable(true);
        diagCard.addView(diagnosticsText, wrap());
        root.addView(diagCard, matchWrapMargin(0, 0, 0, 12));

        TextView footer = new TextView(this);
        footer.setText("Collection mode: on-demand Checkmk pull. Recommended monitoring interval: 60 seconds. No background metric polling loop is used.");
        footer.setTextColor(C_MUTED);
        footer.setTextSize(12);
        footer.setGravity(Gravity.CENTER);
        footer.setPadding(dp(12), dp(4), dp(12), 0);
        root.addView(footer, matchWrap());

        return scroll;
    }

    private View buildHeader() {
        LinearLayout header = new LinearLayout(this);
        header.setOrientation(LinearLayout.HORIZONTAL);
        header.setGravity(Gravity.CENTER_VERTICAL);

        ImageView icon = new ImageView(this);
        icon.setImageResource(R.drawable.ic_cmkagent);
        LinearLayout.LayoutParams ip = new LinearLayout.LayoutParams(dp(58), dp(58));
        ip.setMargins(0, 0, dp(14), 0);
        header.addView(icon, ip);

        LinearLayout text = new LinearLayout(this);
        text.setOrientation(LinearLayout.VERTICAL);
        TextView title = new TextView(this);
        title.setText("cmkagent");
        title.setTextColor(C_TEXT);
        title.setTextSize(29);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        TextView subtitle = new TextView(this);
        subtitle.setText("Checkmk Android pull agent  •  v" + CheckmkOutput.VERSION);
        subtitle.setTextColor(C_MUTED);
        subtitle.setTextSize(13);
        text.addView(title);
        text.addView(subtitle);
        header.addView(text, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        return header;
    }

    private void loadConfig() {
        hostnameInput.setText(AgentConfig.getHostname(this));
        portInput.setText(String.valueOf(AgentConfig.getPort(this)));
        double design = AgentConfig.getDesignCapacityMah(this);
        designCapacityInput.setText(design > 0
                ? String.format(Locale.US, "%.0f", design) : "0");
        allowedServerInput.setText(AgentConfig.getAllowedServer(this));
        autoStartInput.setChecked(AgentConfig.isAutoStart(this));
    }

    private boolean saveConfigOnly() {
        try {
            String hostname = hostnameInput.getText().toString().trim();
            int port = Integer.parseInt(portInput.getText().toString().trim());
            String designRaw = designCapacityInput.getText().toString().trim();
            double design = designRaw.isEmpty() ? 0.0 : Double.parseDouble(designRaw);
            String allowed = allowedServerInput.getText().toString().trim();
            if (port < 1 || port > 65535) throw new IllegalArgumentException("Port tidak valid");
            if (design < 0 || design > 50000) throw new IllegalArgumentException("Design capacity tidak valid");
            AgentConfig.save(this, hostname, port, design, autoStartInput.isChecked(), allowed);
            return true;
        } catch (Exception e) {
            Toast.makeText(this, "Konfigurasi tidak valid: " + e.getMessage(), Toast.LENGTH_LONG).show();
            return false;
        }
    }

    private void saveAndStart() {
        if (!saveConfigOnly()) return;
        stopService(new Intent(this, CheckmkAgentService.class));
        Intent service = new Intent(this, CheckmkAgentService.class);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(service);
        else startService(service);
        Toast.makeText(this, "cmkagent berjalan", Toast.LENGTH_SHORT).show();
        agentText.postDelayed(this::updateDashboard, 500);
    }

    private void updateDashboard() {
        DeviceMetrics.BatteryInfo b = DeviceMetrics.readBattery(this);
        DeviceMetrics.UsageInfo ram = DeviceMetrics.readRam(this);
        DeviceMetrics.UsageInfo storage = DeviceMetrics.readStorage();
        DeviceMetrics.WifiStatus wifi = DeviceMetrics.readWifi(this);
        DeviceMetrics.DeviceInfo device = DeviceMetrics.readDeviceInfo();
        AgentStats.Snapshot stats = AgentStats.read(this);

        agentBadge.setText(stats.running ? "● AGENT RUNNING" : "● AGENT STOPPED");
        styleBadge(agentBadge, stats.running ? C_GREEN : C_CRIT);
        String lastPull = stats.lastPullMs > 0 ? formatDate(stats.lastPullMs) : "Belum ada";
        String allow = AgentConfig.getAllowedServer(this);
        if (allow.isEmpty()) allow = "Any source";
        agentText.setText(
                "Hostname     : " + AgentConfig.getHostname(this) + "\n"
                        + "Listen       : 0.0.0.0:" + AgentConfig.getPort(this) + "\n"
                        + "Device IP    : " + DeviceMetrics.getLocalIpv4() + "\n"
                        + "Last pull    : " + lastPull + "\n"
                        + "Last client  : " + stats.lastClient + "\n"
                        + "Allowed IP   : " + allow + "\n"
                        + "Mode         : On-demand pull (recommended every 60s)"
        );

        int level = Math.max(0, b.level);
        batteryProgress.setProgress(level);
        int batteryColor = level < 15 ? C_CRIT : level < 30 ? C_WARN : C_GREEN;
        batteryProgress.setProgressTintList(ColorStateList.valueOf(batteryColor));
        batteryHeadline.setText((b.level >= 0 ? b.level + "%" : "N/A") + "  •  " + b.status);
        batteryHeadline.setTextColor(batteryColor);

        String health = Double.isNaN(b.healthPercent) ? "N/A"
                : String.format(Locale.US, "%.1f%%", b.healthPercent);
        String full = Double.isNaN(b.fullCapacityMah) ? "N/A"
                : Math.round(b.fullCapacityMah) + " mAh";
        String design = Double.isNaN(b.designCapacityMah) ? "N/A"
                : Math.round(b.designCapacityMah) + " mAh";
        String temp = Double.isNaN(b.temperatureC) ? "N/A"
                : String.format(Locale.US, "%.1f C", b.temperatureC);
        String voltage = Double.isNaN(b.voltageV) ? "N/A"
                : String.format(Locale.US, "%.2f V", b.voltageV);
        String current = Double.isNaN(b.currentNowMa) ? "N/A"
                : String.format(Locale.US, "%.0f mA", b.currentNowMa);
        batteryText.setText(
                "Estimated health : " + health + "\n"
                        + "Design capacity : " + design + "\n"
                        + "Design source   : " + b.designCapacitySource + "\n"
                        + (b.fullCapacityEstimated ? "Estimated full   : " : "Full capacity    : ") + full + "\n"
                        + "Capacity source : " + b.fullCapacitySource + "\n"
                        + "Temperature     : " + temp + "\n"
                        + "Voltage         : " + voltage + "\n"
                        + "Current now     : " + current
        );

        systemText.setText(
                "RAM      : " + Math.round(ram.usedPercent) + "% used  •  "
                        + DeviceMetrics.fmt2(ram.freeGb) + " GB free / "
                        + DeviceMetrics.fmt2(ram.totalGb) + " GB\n"
                        + "Storage  : " + Math.round(storage.usedPercent) + "% used  •  "
                        + DeviceMetrics.fmt2(storage.freeGb) + " GB free / "
                        + DeviceMetrics.fmt2(storage.totalGb) + " GB"
        );

        String rssi = wifi.rssi == Integer.MIN_VALUE ? "N/A" : wifi.rssi + " dBm";
        String speed = wifi.linkSpeedMbps < 0 ? "N/A" : wifi.linkSpeedMbps + " Mbps";
        String freq = wifi.frequencyMhz < 0 ? "N/A" : wifi.frequencyMhz + " MHz";
        networkText.setText(
                "Wi-Fi      : " + (wifi.connected ? "Connected" : "Unavailable") + "\n"
                        + "SSID       : " + wifi.ssid + "\n"
                        + "Signal     : " + rssi + "\n"
                        + "Link speed : " + speed + "\n"
                        + "Frequency  : " + freq + "\n"
                        + "IP         : " + wifi.ip
        );

        deviceText.setText(
                "Manufacturer : " + device.manufacturer + "\n"
                        + "Model        : " + device.model + "\n"
                        + "Profile      : " + device.profile + "\n"
                        + "Android      : " + device.androidVersion + " (SDK " + device.sdk + ")\n"
                        + "Device uptime: " + CheckmkOutput.formatDuration(device.uptimeMs)
        );

        diagnosticsText.setText(
                "Accepted pulls : " + stats.accepted + "\n"
                        + "Rejected pulls : " + stats.rejected + "\n"
                        + "Last rejected  : " + stats.lastRejected + "\n"
                        + "Foreground svc : " + (stats.running ? "running" : "stopped") + "\n"
                        + "Battery samples: " + b.estimateSamples + "\n"
                        + "Package        : com.bcp.checkmkagent"
        );
    }

    private void showAgentOutput() {
        if (!saveConfigOnly()) return;
        TextView text = new TextView(this);
        text.setText(CheckmkOutput.build(this));
        text.setTextIsSelectable(true);
        text.setTypeface(Typeface.MONOSPACE);
        text.setTextColor(C_TEXT);
        text.setTextSize(12);
        text.setPadding(dp(16), dp(16), dp(16), dp(16));
        text.setBackgroundColor(C_BG);

        ScrollView scroller = new ScrollView(this);
        scroller.setBackgroundColor(C_BG);
        scroller.addView(text);

        AlertDialog dialog = new AlertDialog.Builder(this)
                .setTitle("Checkmk agent output")
                .setView(scroller)
                .setPositiveButton("CLOSE", null)
                .create();
        dialog.setOnShowListener(d -> {
            if (dialog.getButton(AlertDialog.BUTTON_POSITIVE) != null) {
                dialog.getButton(AlertDialog.BUTTON_POSITIVE).setTextColor(C_GREEN);
            }
        });
        dialog.show();
        updateDashboard();
    }

    private void requestRuntimePermissionsIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return;
        List<String> needed = new ArrayList<>();
        if (Build.VERSION.SDK_INT >= 33
                && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED) {
            needed.add(Manifest.permission.POST_NOTIFICATIONS);
        }
        if (Build.VERSION.SDK_INT >= 33
                && checkSelfPermission(Manifest.permission.NEARBY_WIFI_DEVICES)
                != PackageManager.PERMISSION_GRANTED) {
            needed.add(Manifest.permission.NEARBY_WIFI_DEVICES);
        }
        if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION)
                != PackageManager.PERMISSION_GRANTED) {
            needed.add(Manifest.permission.ACCESS_FINE_LOCATION);
        }
        if (!needed.isEmpty()) requestPermissions(needed.toArray(new String[0]), 1001);
    }

    private LinearLayout card(String titleText, String subtitleText) {
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setPadding(dp(16), dp(15), dp(16), dp(16));
        card.setBackground(rounded(C_CARD, 16, C_LINE, 1));

        TextView title = new TextView(this);
        title.setText(titleText);
        title.setTextColor(C_GREEN);
        title.setTextSize(13);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        card.addView(title, wrap());

        TextView subtitle = new TextView(this);
        subtitle.setText(subtitleText);
        subtitle.setTextColor(C_MUTED);
        subtitle.setTextSize(12);
        subtitle.setPadding(0, dp(2), 0, dp(12));
        card.addView(subtitle, wrap());
        return card;
    }

    private EditText input(LinearLayout parent, String label, int type, String hint) {
        TextView l = new TextView(this);
        l.setText(label);
        l.setTextColor(C_MUTED);
        l.setTextSize(12);
        l.setTypeface(Typeface.DEFAULT_BOLD);
        l.setPadding(0, dp(6), 0, dp(3));
        parent.addView(l, wrap());

        EditText e = new EditText(this);
        e.setSingleLine(true);
        e.setInputType(type);
        e.setTextColor(C_TEXT);
        e.setHintTextColor(Color.rgb(102, 119, 133));
        e.setHint(hint);
        e.setTextSize(15);
        e.setPadding(dp(12), 0, dp(12), 0);
        e.setBackground(rounded(C_CARD_ALT, 10, C_LINE, 1));
        parent.addView(e, matchHeightMargin(48, 0, 0, 0, 8));
        return e;
    }

    private TextView bodyText() {
        TextView v = new TextView(this);
        v.setTextColor(C_TEXT);
        v.setTextSize(14);
        v.setLineSpacing(0, 1.15f);
        return v;
    }

    private TextView badge(String text, int color) {
        TextView v = new TextView(this);
        v.setText(text);
        v.setTextSize(12);
        v.setTypeface(Typeface.DEFAULT_BOLD);
        v.setPadding(dp(10), dp(5), dp(10), dp(5));
        styleBadge(v, color);
        return v;
    }

    private void styleBadge(TextView v, int color) {
        v.setTextColor(color);
        v.setBackground(rounded(withAlpha(color, 35), 20, withAlpha(color, 110), 1));
    }

    private Button actionButton(String text, int bg, int fg) {
        Button b = new Button(this);
        b.setText(text);
        b.setTextColor(fg);
        b.setTextSize(12);
        b.setTypeface(Typeface.DEFAULT_BOLD);
        b.setAllCaps(false);
        b.setGravity(Gravity.CENTER);
        b.setBackground(rounded(bg, 10, bg, 0));
        return b;
    }

    private GradientDrawable rounded(int fill, int radiusDp, int stroke, int strokeDp) {
        GradientDrawable d = new GradientDrawable();
        d.setColor(fill);
        d.setCornerRadius(dp(radiusDp));
        if (strokeDp > 0) d.setStroke(dp(strokeDp), stroke);
        return d;
    }

    private int withAlpha(int color, int alpha) {
        return Color.argb(alpha, Color.red(color), Color.green(color), Color.blue(color));
    }

    private View space(int height) {
        View v = new View(this);
        v.setLayoutParams(new LinearLayout.LayoutParams(1, dp(height)));
        return v;
    }

    private String formatDate(long millis) {
        return new SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault())
                .format(new Date(millis));
    }

    private LinearLayout.LayoutParams wrap() {
        return new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT);
    }

    private LinearLayout.LayoutParams matchWrap() {
        return new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT);
    }

    private LinearLayout.LayoutParams matchWrapMargin(int l, int t, int r, int b) {
        LinearLayout.LayoutParams p = matchWrap();
        p.setMargins(dp(l), dp(t), dp(r), dp(b));
        return p;
    }

    private LinearLayout.LayoutParams matchHeightMargin(int height, int l, int t, int r, int b) {
        LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, dp(height));
        p.setMargins(dp(l), dp(t), dp(r), dp(b));
        return p;
    }

    private LinearLayout.LayoutParams weightButton() {
        return new LinearLayout.LayoutParams(0, dp(46), 1f);
    }

    private int dp(int value) {
        return (int) (value * getResources().getDisplayMetrics().density + 0.5f);
    }
}
