package com.tvfull.pro.installer;

import android.app.Activity;
import android.content.ClipData;
import android.content.Intent;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.pm.Signature;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.StatFs;
import android.provider.Settings;
import android.text.TextUtils;
import android.view.Gravity;
import android.view.View;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.TextView;

import org.json.JSONObject;

import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.security.MessageDigest;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public final class MainActivity extends Activity {
    private static final String MANIFEST_URL =
            "https://raw.githubusercontent.com/luchozurita2019-ui/tvplayer/android-tv-full-pro-clean-source/tv_full_installer/latest.json";
    private static final String TARGET_PACKAGE = "com.tvfull.pro.tv.v10safe";
    private static final String EXPECTED_CERT_SHA256 =
            "40de9b14a83adb7b070e316a241e7f5a7f5b1705fdc43b5f495b0e1e3fcab02a";
    private static final int CONNECT_TIMEOUT_MS = 8000;
    private static final int READ_TIMEOUT_MS = 30000;
    private static final long EXTRA_FREE_BYTES = 16L * 1024L * 1024L;

    private final ExecutorService io = Executors.newSingleThreadExecutor();

    private TextView architectureView;
    private TextView versionView;
    private TextView statusView;
    private ProgressBar progressBar;
    private Button actionButton;

    private String architectureKey;
    private String architectureLabel;
    private ReleaseInfo release;
    private File pendingInstallFile;
    private boolean busy;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        buildUi();
        detectArchitecture();
        if (architectureKey == null) {
            setStatus("Este dispositivo no usa una arquitectura ARM compatible.", true);
            actionButton.setEnabled(false);
            return;
        }
        loadManifest(false);
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (pendingInstallFile != null && canInstallPackages()) {
            File file = pendingInstallFile;
            pendingInstallFile = null;
            openPackageInstaller(file);
        }
    }

    @Override
    protected void onDestroy() {
        io.shutdownNow();
        super.onDestroy();
    }

    private void buildUi() {
        int pad = dp(28);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setGravity(Gravity.CENTER_VERTICAL);
        root.setPadding(dp(56), pad, dp(56), pad);
        root.setBackgroundColor(Color.rgb(7, 17, 31));

        TextView brand = text("TV FULL", 34, Color.WHITE, true);
        root.addView(brand, matchWrap());

        TextView subtitle = text("INSTALADOR INTELIGENTE", 16, Color.rgb(38, 217, 255), true);
        LinearLayout.LayoutParams subParams = matchWrap();
        subParams.topMargin = dp(2);
        root.addView(subtitle, subParams);

        TextView explain = text(
                "Detecta tu TV y descarga únicamente la versión compatible de TV FULL PRO.",
                18,
                Color.rgb(190, 204, 220),
                false
        );
        LinearLayout.LayoutParams explainParams = matchWrap();
        explainParams.topMargin = dp(22);
        root.addView(explain, explainParams);

        architectureView = text("Detectando arquitectura…", 20, Color.WHITE, true);
        LinearLayout.LayoutParams infoParams = matchWrap();
        infoParams.topMargin = dp(26);
        root.addView(architectureView, infoParams);

        versionView = text("Buscando versión disponible…", 16, Color.rgb(170, 186, 204), false);
        LinearLayout.LayoutParams versionParams = matchWrap();
        versionParams.topMargin = dp(8);
        root.addView(versionView, versionParams);

        progressBar = new ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal);
        progressBar.setMax(1000);
        progressBar.setIndeterminate(true);
        progressBar.setProgressTintList(ColorStateList.valueOf(Color.rgb(38, 217, 255)));
        LinearLayout.LayoutParams progressParams = new LinearLayout.LayoutParams(dp(520), dp(8));
        progressParams.topMargin = dp(24);
        root.addView(progressBar, progressParams);

        statusView = text("Conectando…", 16, Color.rgb(190, 204, 220), false);
        LinearLayout.LayoutParams statusParams = matchWrap();
        statusParams.topMargin = dp(14);
        root.addView(statusView, statusParams);

        actionButton = new Button(this);
        actionButton.setText("DESCARGAR TV FULL PRO");
        actionButton.setTextSize(17);
        actionButton.setTextColor(Color.WHITE);
        actionButton.setAllCaps(false);
        actionButton.setFocusable(true);
        actionButton.setFocusableInTouchMode(true);
        actionButton.setPadding(dp(28), dp(12), dp(28), dp(12));
        int[][] states = new int[][]{
                new int[]{android.R.attr.state_focused},
                new int[]{android.R.attr.state_pressed},
                new int[]{}
        };
        int[] colors = new int[]{
                Color.rgb(111, 72, 255),
                Color.rgb(86, 56, 210),
                Color.rgb(22, 110, 145)
        };
        actionButton.setBackgroundTintList(new ColorStateList(states, colors));
        actionButton.setOnClickListener(v -> onAction());
        actionButton.setEnabled(false);
        LinearLayout.LayoutParams buttonParams = new LinearLayout.LayoutParams(dp(330), dp(58));
        buttonParams.topMargin = dp(24);
        root.addView(actionButton, buttonParams);

        TextView security = text(
                "✓ Verificación SHA-256  •  ✓ Firma TV FULL PRO  •  ✓ ARM32 / ARM64 automático",
                13,
                Color.rgb(125, 151, 174),
                false
        );
        LinearLayout.LayoutParams securityParams = matchWrap();
        securityParams.topMargin = dp(18);
        root.addView(security, securityParams);

        setContentView(root);
    }

    private TextView text(String value, float sp, int color, boolean bold) {
        TextView view = new TextView(this);
        view.setText(value);
        view.setTextSize(sp);
        view.setTextColor(color);
        if (bold) view.setTypeface(view.getTypeface(), android.graphics.Typeface.BOLD);
        return view;
    }

    private LinearLayout.LayoutParams matchWrap() {
        return new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
        );
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    private void detectArchitecture() {
        boolean hasArm64 = false;
        boolean hasArm32 = false;
        StringBuilder raw = new StringBuilder();
        for (String abi : Build.SUPPORTED_ABIS) {
            if (raw.length() > 0) raw.append(", ");
            raw.append(abi);
            if ("arm64-v8a".equalsIgnoreCase(abi)) hasArm64 = true;
            if ("armeabi-v7a".equalsIgnoreCase(abi) || "armeabi".equalsIgnoreCase(abi)) hasArm32 = true;
        }
        if (hasArm64) {
            architectureKey = "arm64";
            architectureLabel = "ARM64";
        } else if (hasArm32) {
            architectureKey = "arm32";
            architectureLabel = "ARM32";
        } else {
            architectureKey = null;
            architectureLabel = "No compatible";
        }
        architectureView.setText("Tu TV: " + architectureLabel + "  ·  " + raw);
    }

    private void loadManifest(boolean downloadAfter) {
        if (busy) return;
        setBusy(true);
        progressBar.setIndeterminate(true);
        setStatus("Buscando la versión actual…", false);
        io.execute(() -> {
            try {
                String json = readSmallHttps(MANIFEST_URL);
                ReleaseInfo parsed = ReleaseInfo.parse(json, architectureKey);
                validateRelease(parsed);
                release = parsed;
                runOnUiThread(() -> {
                    updateVersionUi();
                    setBusy(false);
                    if (downloadAfter) downloadRelease();
                });
            } catch (Exception e) {
                runOnUiThread(() -> {
                    setBusy(false);
                    progressBar.setIndeterminate(false);
                    progressBar.setProgress(0);
                    setStatus("No se pudo consultar la versión. Revisá la conexión e intentá otra vez.", true);
                    actionButton.setText("REINTENTAR");
                    actionButton.setEnabled(true);
                });
            }
        });
    }

    private void updateVersionUi() {
        InstalledInfo installed = getInstalledInfo();
        String available = release.versionName + "+" + release.versionCode;
        if (installed == null) {
            versionView.setText("Disponible: " + available + "  ·  descarga " + architectureLabel);
            actionButton.setText("INSTALAR TV FULL PRO");
            setStatus("Lista para descargar sólo la APK compatible.", false);
        } else if (installed.versionCode < release.versionCode) {
            versionView.setText("Instalada: " + installed.versionName + "+" + installed.versionCode
                    + "  ·  disponible: " + available);
            actionButton.setText("ACTUALIZAR TV FULL PRO");
            setStatus("Hay una versión nueva disponible para tu TV.", false);
        } else {
            versionView.setText("Instalada: " + installed.versionName + "+" + installed.versionCode
                    + "  ·  actual: " + available);
            actionButton.setText("REINSTALAR TV FULL PRO");
            setStatus("TV FULL PRO ya está actualizada.", false);
        }
        progressBar.setIndeterminate(false);
        progressBar.setProgress(0);
        actionButton.setEnabled(true);
        actionButton.requestFocus();
    }

    private void onAction() {
        if (busy) return;
        if (release == null) {
            loadManifest(true);
            return;
        }
        downloadRelease();
    }

    private void downloadRelease() {
        ReleaseInfo selected = release;
        if (selected == null) return;
        setBusy(true);
        progressBar.setIndeterminate(false);
        progressBar.setProgress(0);
        setStatus("Preparando descarga " + architectureLabel + "…", false);
        io.execute(() -> {
            File temp = null;
            try {
                File dir = new File(getCacheDir(), "downloads");
                if (!dir.exists() && !dir.mkdirs()) throw new Exception("No cache directory");
                clearOldApks(dir);
                temp = new File(dir, "TV-FULL-PRO.part");
                File target = new File(dir, "TV-FULL-PRO-" + architectureLabel + ".apk");

                HttpURLConnection connection = open(selected.url);
                long contentLength = connection.getContentLengthLong();
                if (contentLength <= 0 && selected.size > 0) contentLength = selected.size;
                ensureFreeSpace(contentLength);

                try (InputStream input = new BufferedInputStream(connection.getInputStream(), 64 * 1024);
                     BufferedOutputStream output = new BufferedOutputStream(new FileOutputStream(temp), 64 * 1024)) {
                    byte[] buffer = new byte[64 * 1024];
                    long total = 0;
                    long lastUi = 0;
                    int count;
                    while ((count = input.read(buffer)) != -1) {
                        output.write(buffer, 0, count);
                        total += count;
                        long now = android.os.SystemClock.elapsedRealtime();
                        if (now - lastUi >= 180) {
                            lastUi = now;
                            publishProgress(total, contentLength);
                        }
                    }
                    output.flush();
                } finally {
                    connection.disconnect();
                }

                String actualSha = sha256(temp);
                if (!actualSha.equalsIgnoreCase(selected.sha256)) {
                    throw new SecurityException("SHA-256 mismatch");
                }
                if (target.exists() && !target.delete()) throw new Exception("Old target busy");
                if (!temp.renameTo(target)) {
                    copyFile(temp, target);
                    if (!temp.delete()) temp.deleteOnExit();
                }
                verifyDownloadedPackage(target);
                runOnUiThread(() -> {
                    progressBar.setProgress(1000);
                    setBusy(false);
                    setStatus("Descarga verificada. Abriendo el instalador de Android…", false);
                    requestInstall(target);
                });
            } catch (Exception e) {
                if (temp != null && temp.exists()) temp.delete();
                String message = e instanceof SecurityException
                        ? "La descarga no pasó la verificación de seguridad. No se instalará."
                        : "No se pudo completar la descarga. Comprobá Internet y espacio libre.";
                runOnUiThread(() -> {
                    setBusy(false);
                    progressBar.setIndeterminate(false);
                    progressBar.setProgress(0);
                    setStatus(message, true);
                    actionButton.setText("REINTENTAR DESCARGA");
                    actionButton.setEnabled(true);
                    actionButton.requestFocus();
                });
            }
        });
    }

    private void publishProgress(long downloaded, long total) {
        if (total <= 0) {
            runOnUiThread(() -> {
                progressBar.setIndeterminate(true);
                setStatus("Descargando " + architectureLabel + "…", false);
            });
            return;
        }
        int progress = (int) Math.min(1000L, downloaded * 1000L / total);
        int percent = progress / 10;
        runOnUiThread(() -> {
            progressBar.setIndeterminate(false);
            progressBar.setProgress(progress);
            setStatus("Descargando " + architectureLabel + "… " + percent + "%", false);
        });
    }

    private HttpURLConnection open(String rawUrl) throws Exception {
        URL url = new URL(rawUrl);
        if (!"https".equalsIgnoreCase(url.getProtocol())) throw new SecurityException("HTTPS required");
        HttpURLConnection connection = (HttpURLConnection) url.openConnection();
        connection.setInstanceFollowRedirects(true);
        connection.setConnectTimeout(CONNECT_TIMEOUT_MS);
        connection.setReadTimeout(READ_TIMEOUT_MS);
        connection.setRequestProperty("User-Agent", "TV-FULL-Installer/1.0 Android-TV");
        connection.setRequestProperty("Accept", "application/octet-stream,application/json;q=0.9,*/*;q=0.5");
        int code = connection.getResponseCode();
        if (code < 200 || code >= 300) {
            connection.disconnect();
            throw new Exception("HTTP " + code);
        }
        return connection;
    }

    private String readSmallHttps(String rawUrl) throws Exception {
        HttpURLConnection connection = open(rawUrl);
        try (InputStream input = new BufferedInputStream(connection.getInputStream());
             ByteArrayOutputStream output = new ByteArrayOutputStream()) {
            byte[] buffer = new byte[8192];
            int total = 0;
            int count;
            while ((count = input.read(buffer)) != -1) {
                total += count;
                if (total > 128 * 1024) throw new SecurityException("Manifest too large");
                output.write(buffer, 0, count);
            }
            return output.toString("UTF-8");
        } finally {
            connection.disconnect();
        }
    }

    private void validateRelease(ReleaseInfo info) throws Exception {
        if (!TARGET_PACKAGE.equals(info.packageName)) throw new SecurityException("Wrong package");
        if (!EXPECTED_CERT_SHA256.equalsIgnoreCase(info.certificateSha256)) {
            throw new SecurityException("Wrong certificate");
        }
        if (info.versionCode <= 0 || TextUtils.isEmpty(info.versionName)) throw new Exception("Bad version");
        if (TextUtils.isEmpty(info.url) || TextUtils.isEmpty(info.sha256)) throw new Exception("Bad asset");
        URL url = new URL(info.url);
        if (!"https".equalsIgnoreCase(url.getProtocol())) throw new SecurityException("HTTPS required");
        if (!info.sha256.matches("(?i)[0-9a-f]{64}")) throw new SecurityException("Bad SHA");
    }

    private void ensureFreeSpace(long downloadBytes) throws Exception {
        if (downloadBytes <= 0) return;
        StatFs stat = new StatFs(getCacheDir().getAbsolutePath());
        long available = stat.getAvailableBytes();
        if (available < downloadBytes + EXTRA_FREE_BYTES) {
            throw new Exception("Insufficient cache space");
        }
    }

    private void clearOldApks(File dir) {
        File[] files = dir.listFiles();
        if (files == null) return;
        for (File file : files) {
            String name = file.getName().toLowerCase(Locale.ROOT);
            if ((name.endsWith(".apk") || name.endsWith(".part")) && file.isFile()) file.delete();
        }
    }

    private String sha256(File file) throws Exception {
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        try (FileInputStream input = new FileInputStream(file)) {
            byte[] buffer = new byte[64 * 1024];
            int count;
            while ((count = input.read(buffer)) != -1) digest.update(buffer, 0, count);
        }
        return hex(digest.digest());
    }

    private void copyFile(File source, File target) throws Exception {
        try (FileInputStream input = new FileInputStream(source);
             FileOutputStream output = new FileOutputStream(target)) {
            byte[] buffer = new byte[64 * 1024];
            int count;
            while ((count = input.read(buffer)) != -1) output.write(buffer, 0, count);
            output.getFD().sync();
        }
    }

    @SuppressWarnings("deprecation")
    private void verifyDownloadedPackage(File apk) throws Exception {
        PackageManager pm = getPackageManager();
        int flags = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P
                ? PackageManager.GET_SIGNING_CERTIFICATES
                : PackageManager.GET_SIGNATURES;
        PackageInfo info = pm.getPackageArchiveInfo(apk.getAbsolutePath(), flags);
        if (info == null || !TARGET_PACKAGE.equals(info.packageName)) {
            throw new SecurityException("Downloaded package mismatch");
        }
        Signature[] signatures;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            if (info.signingInfo == null) throw new SecurityException("No signing info");
            signatures = info.signingInfo.hasMultipleSigners()
                    ? info.signingInfo.getApkContentsSigners()
                    : info.signingInfo.getSigningCertificateHistory();
        } else {
            signatures = info.signatures;
        }
        if (signatures == null || signatures.length == 0) throw new SecurityException("Unsigned APK");
        boolean valid = false;
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        for (Signature signature : signatures) {
            String hash = hex(digest.digest(signature.toByteArray()));
            digest.reset();
            if (EXPECTED_CERT_SHA256.equalsIgnoreCase(hash)) {
                valid = true;
                break;
            }
        }
        if (!valid) throw new SecurityException("Certificate mismatch");
    }

    private void requestInstall(File file) {
        if (!canInstallPackages()) {
            pendingInstallFile = file;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Intent settings = new Intent(
                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:" + getPackageName())
                );
                startActivity(settings);
                setStatus("Permití instalar apps desde TV FULL Installer y volvé atrás.", false);
                return;
            }
        }
        openPackageInstaller(file);
    }

    private boolean canInstallPackages() {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.O
                || getPackageManager().canRequestPackageInstalls();
    }

    private void openPackageInstaller(File file) {
        Uri uri = Uri.parse("content://" + getPackageName() + ".files/" + file.getName());
        Intent intent = new Intent(Intent.ACTION_VIEW);
        intent.setDataAndType(uri, "application/vnd.android.package-archive");
        intent.setClipData(ClipData.newRawUri("TV FULL PRO APK", uri));
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        try {
            startActivity(intent);
        } catch (Exception e) {
            setStatus("Android no pudo abrir el instalador de paquetes.", true);
        }
    }

    @SuppressWarnings("deprecation")
    private InstalledInfo getInstalledInfo() {
        try {
            PackageInfo info = getPackageManager().getPackageInfo(TARGET_PACKAGE, 0);
            long code = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P
                    ? info.getLongVersionCode()
                    : info.versionCode;
            return new InstalledInfo(info.versionName == null ? "?" : info.versionName, code);
        } catch (PackageManager.NameNotFoundException e) {
            return null;
        }
    }

    private void setBusy(boolean value) {
        busy = value;
        actionButton.setEnabled(!value && architectureKey != null);
    }

    private void setStatus(String message, boolean error) {
        statusView.setText(message);
        statusView.setTextColor(error ? Color.rgb(255, 108, 125) : Color.rgb(190, 204, 220));
    }

    private static String hex(byte[] bytes) {
        StringBuilder builder = new StringBuilder(bytes.length * 2);
        for (byte value : bytes) builder.append(String.format(Locale.ROOT, "%02x", value & 0xff));
        return builder.toString();
    }

    private static final class InstalledInfo {
        final String versionName;
        final long versionCode;
        InstalledInfo(String versionName, long versionCode) {
            this.versionName = versionName;
            this.versionCode = versionCode;
        }
    }

    private static final class ReleaseInfo {
        final String versionName;
        final long versionCode;
        final String packageName;
        final String certificateSha256;
        final String url;
        final String sha256;
        final long size;

        ReleaseInfo(String versionName, long versionCode, String packageName,
                    String certificateSha256, String url, String sha256, long size) {
            this.versionName = versionName;
            this.versionCode = versionCode;
            this.packageName = packageName;
            this.certificateSha256 = certificateSha256;
            this.url = url;
            this.sha256 = sha256;
            this.size = size;
        }

        static ReleaseInfo parse(String raw, String architectureKey) throws Exception {
            JSONObject root = new JSONObject(raw);
            JSONObject asset = root.getJSONObject(architectureKey);
            return new ReleaseInfo(
                    root.getString("versionName"),
                    root.getLong("versionCode"),
                    root.getString("packageName"),
                    root.getString("certificateSha256"),
                    asset.getString("url"),
                    asset.getString("sha256"),
                    asset.optLong("size", 0L)
            );
        }
    }
}
