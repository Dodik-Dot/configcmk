package com.bcp.checkmkagent;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Intent;
import android.os.Build;
import android.os.IBinder;

import java.io.BufferedWriter;
import java.io.OutputStreamWriter;
import java.net.InetSocketAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public class CheckmkAgentService extends Service {
    public static final String CHANNEL_ID = "cmkagent_service";
    private static final int NOTIFICATION_ID = 6556;

    private volatile boolean running = false;
    private ServerSocket serverSocket;
    private ExecutorService executor;

    @Override
    public void onCreate() {
        super.onCreate();
        createNotificationChannel();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        startForeground(NOTIFICATION_ID, buildNotification("Starting agent..."));
        startListenerIfNeeded();
        return START_STICKY;
    }

    private synchronized void startListenerIfNeeded() {
        if (running) return;
        running = true;
        AgentStats.recordStart(this);
        executor = Executors.newSingleThreadExecutor();
        executor.execute(() -> {
            int port = AgentConfig.getPort(this);
            try {
                serverSocket = new ServerSocket();
                serverSocket.setReuseAddress(true);
                serverSocket.bind(new InetSocketAddress("0.0.0.0", port));
                updateNotification("Listening on TCP " + port);

                while (running) {
                    try {
                        Socket client = serverSocket.accept();
                        client.setSoTimeout(5000);
                        serveClient(client);
                    } catch (Exception e) {
                        if (running) updateNotification("Client error: " + shortMessage(e));
                    }
                }
            } catch (Exception e) {
                updateNotification("Agent error: " + shortMessage(e));
            } finally {
                running = false;
                closeServerSocket();
            }
        });
    }

    private void serveClient(Socket client) {
        String remoteIp = client.getInetAddress() == null
                ? "unknown" : client.getInetAddress().getHostAddress();

        if (!AgentConfig.isClientAllowed(this, remoteIp)) {
            AgentStats.recordRejected(this, remoteIp);
            try { client.close(); } catch (Exception ignored) {}
            return;
        }

        AgentStats.recordAccepted(this, remoteIp);
        try (Socket socket = client;
             BufferedWriter writer = new BufferedWriter(
                     new OutputStreamWriter(socket.getOutputStream(), StandardCharsets.UTF_8))) {
            writer.write(CheckmkOutput.build(this));
            writer.flush();
        } catch (Exception ignored) {}
    }

    @Override
    public void onDestroy() {
        running = false;
        AgentStats.recordStop(this);
        closeServerSocket();
        if (executor != null) executor.shutdownNow();
        super.onDestroy();
    }

    private void closeServerSocket() {
        try {
            if (serverSocket != null) serverSocket.close();
        } catch (Exception ignored) {}
    }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationManager nm = getSystemService(NotificationManager.class);
            if (nm != null) {
                NotificationChannel channel = new NotificationChannel(
                        CHANNEL_ID,
                        "cmkagent service",
                        NotificationManager.IMPORTANCE_LOW
                );
                channel.setDescription("Checkmk Android pull agent on TCP 6556");
                nm.createNotificationChannel(channel);
            }
        }
    }

    private Notification buildNotification(String text) {
        Intent open = new Intent(this, MainActivity.class);
        PendingIntent pi = PendingIntent.getActivity(
                this, 0, open,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );

        Notification.Builder builder = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                ? new Notification.Builder(this, CHANNEL_ID)
                : new Notification.Builder(this);

        return builder
                .setContentTitle("cmkagent")
                .setContentText(text)
                .setSmallIcon(R.drawable.ic_stat_cmkagent)
                .setContentIntent(pi)
                .setOngoing(true)
                .build();
    }

    private void updateNotification(String text) {
        NotificationManager nm = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
        if (nm != null) nm.notify(NOTIFICATION_ID, buildNotification(text));
    }

    private static String shortMessage(Exception e) {
        String m = e.getMessage();
        return m == null || m.isEmpty() ? e.getClass().getSimpleName() : m;
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}
