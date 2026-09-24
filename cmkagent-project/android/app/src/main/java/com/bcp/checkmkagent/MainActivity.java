package com.bcp.checkmkagent;

import android.Manifest;
import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Typeface;
import android.os.Build;
import android.os.Bundle;
import android.text.InputType;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import java.net.Inet4Address;
import java.net.NetworkInterface;
import java.util.Collections;
import java.util.Locale;

public class MainActivity extends Activity {
    private EditText hostnameInput;
    private EditText portInput;
    private EditText designCapacityInput;
    private CheckBox autoStartInput;
    private TextView statusText;
    private TextView previewText;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(buildUi());
        loadConfig();
        requestNotificationPermissionIfNeeded();
        updateStatus();
    }

    private ScrollView buildUi() {
        int pad = dp(16);
        ScrollView scroll = new ScrollView(this);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(pad, pad, pad, pad);
        scroll.addView(root, new ScrollView.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT));

        TextView title = new TextView(this);
        title.setText("cmkagent");
        title.setTextSize(28);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        root.addView(title);

        TextView subtitle = new TextView(this);
        subtitle.setText("Checkmk Community Android pull agent (TCP 6556)");
        subtitle.setTextSize(15);
        subtitle.setPadding(0, 0, 0, dp(16));
        root.addView(subtitle);

        root.addView(label("Hostname Checkmk"));
        hostnameInput = new EditText(this);
        hostnameInput.setSingleLine(true);
        root.addView(hostnameInput, matchWrap());

        root.addView(label("TCP Port"));
        portInput = new EditText(this);
        portInput.setSingleLine(true);
        portInput.setInputType(InputType.TYPE_CLASS_NUMBER);
        root.addView(portInput, matchWrap());

        root.addView(label("Design Capacity baterai (mAh, 0 = auto)"));
        designCapacityInput = new EditText(this);
        designCapacityInput.setSingleLine(true);
        designCapacityInput.setInputType(InputType.TYPE_CLASS_NUMBER | InputType.TYPE_NUMBER_FLAG_DECIMAL);
        root.addView(designCapacityInput, matchWrap());

        autoStartInput = new CheckBox(this);
        autoStartInput.setText("Jalankan otomatis setelah boot");
        root.addView(autoStartInput, matchWrap());

        Button start = new Button(this);
        start.setText("Simpan & Start Agent");
        start.setOnClickListener(v -> saveAndStart());
        root.addView(start, matchWrap());

        Button stop = new Button(this);
        stop.setText("Stop Agent");
        stop.setOnClickListener(v -> {
            stopService(new Intent(this, CheckmkAgentService.class));
            Toast.makeText(this, "Agent dihentikan", Toast.LENGTH_SHORT).show();
            updateStatus();
        });
        root.addView(stop, matchWrap());

        Button preview = new Button(this);
        preview.setText("Preview Output Checkmk");
        preview.setOnClickListener(v -> {
            saveConfigOnly();
            previewText.setText(CheckmkOutput.build(this));
            updateStatus();
        });
        root.addView(preview, matchWrap());

        statusText = new TextView(this);
        statusText.setPadding(0, dp(14), 0, dp(8));
        statusText.setTypeface(Typeface.DEFAULT_BOLD);
        root.addView(statusText, matchWrap());

        previewText = new TextView(this);
        previewText.setTextIsSelectable(true);
        previewText.setTypeface(Typeface.MONOSPACE);
        previewText.setTextSize(12);
        root.addView(previewText, matchWrap());
        return scroll;
    }

    private void loadConfig() {
        hostnameInput.setText(AgentConfig.getHostname(this));
        portInput.setText(String.valueOf(AgentConfig.getPort(this)));
        double design = AgentConfig.getDesignCapacityMah(this);
        designCapacityInput.setText(design > 0
                ? String.format(Locale.US, "%.0f", design) : "0");
        autoStartInput.setChecked(AgentConfig.isAutoStart(this));
    }

    private boolean saveConfigOnly() {
        try {
            String hostname = hostnameInput.getText().toString().trim();
            int port = Integer.parseInt(portInput.getText().toString().trim());
            double design = Double.parseDouble(designCapacityInput.getText().toString().trim());
            if (port < 1 || port > 65535) throw new IllegalArgumentException("Port tidak valid");
            AgentConfig.save(this, hostname, port, design, autoStartInput.isChecked());
            return true;
        } catch (Exception e) {
            Toast.makeText(this, "Konfigurasi tidak valid: " + e.getMessage(), Toast.LENGTH_LONG).show();
            return false;
        }
    }

    private void saveAndStart() {
        if (!saveConfigOnly()) return;
        // Restart so a changed TCP port is applied immediately.
        stopService(new Intent(this, CheckmkAgentService.class));
        Intent service = new Intent(this, CheckmkAgentService.class);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(service);
        else startService(service);
        Toast.makeText(this, "cmkagent berjalan", Toast.LENGTH_SHORT).show();
        updateStatus();
    }

    private void updateStatus() {
        statusText.setText(
                "IP perangkat : " + getLocalIpv4() + "\n"
                        + "Listen       : 0.0.0.0:" + AgentConfig.getPort(this) + "\n"
                        + "Hostname  : " + AgentConfig.getHostname(this)
        );
    }

    private String getLocalIpv4() {
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
        } catch (Exception ignored) {
        }
        return "N/A";
    }

    private void requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= 33
                && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, 1001);
        }
    }

    private TextView label(String text) {
        TextView v = new TextView(this);
        v.setText(text);
        v.setTypeface(Typeface.DEFAULT_BOLD);
        v.setPadding(0, dp(10), 0, 0);
        return v;
    }

    private LinearLayout.LayoutParams matchWrap() {
        return new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
        );
    }

    private int dp(int value) {
        return (int) (value * getResources().getDisplayMetrics().density + 0.5f);
    }
}
