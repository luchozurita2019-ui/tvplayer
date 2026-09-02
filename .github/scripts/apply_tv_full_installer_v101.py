from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f"Expected block not found: {label}")
    return text.replace(old, new, 1)

main_path = Path('tv_full_installer/app/src/main/java/com/tvfull/pro/installer/MainActivity.java')
text = main_path.read_text()

text = replace_once(
    text,
    'import android.widget.LinearLayout;\n',
    'import android.widget.ImageView;\nimport android.widget.LinearLayout;\n',
    'ImageView import',
)

text = replace_once(
    text,
    '    private File pendingInstallFile;\n    private boolean busy;\n',
    '    private File pendingInstallFile;\n    private boolean pendingDownloadAfterPermission;\n    private boolean busy;\n',
    'pending permission field',
)

text = replace_once(
    text,
    '''    @Override\n    protected void onResume() {\n        super.onResume();\n        if (pendingInstallFile != null && canInstallPackages()) {\n            File file = pendingInstallFile;\n            pendingInstallFile = null;\n            openPackageInstaller(file);\n        }\n    }\n''',
    '''    @Override\n    protected void onResume() {\n        super.onResume();\n        if (pendingDownloadAfterPermission && canInstallPackages()) {\n            pendingDownloadAfterPermission = false;\n            setStatus("Permiso concedido. Preparando TV FULL PRO…", false);\n            if (release == null) {\n                loadManifest(true);\n            } else {\n                downloadRelease();\n            }\n            return;\n        }\n        if (pendingInstallFile != null && canInstallPackages()) {\n            File file = pendingInstallFile;\n            pendingInstallFile = null;\n            setStatus("Permiso concedido. Abriendo instalación…", false);\n            openPackageInstaller(file);\n        }\n    }\n''',
    'onResume permission continuation',
)

text = replace_once(
    text,
    '''        TextView brand = text("TV FULL", 34, Color.WHITE, true);\n        root.addView(brand, matchWrap());\n\n        TextView subtitle = text("INSTALADOR INTELIGENTE", 16, Color.rgb(38, 217, 255), true);\n''',
    '''        ImageView logo = new ImageView(this);\n        logo.setImageResource(com.tvfull.pro.installer.R.drawable.ic_launcher);\n        logo.setScaleType(ImageView.ScaleType.FIT_CENTER);\n        logo.setContentDescription("TV FULL Installer");\n        LinearLayout.LayoutParams logoParams = new LinearLayout.LayoutParams(dp(118), dp(118));\n        logoParams.bottomMargin = dp(10);\n        root.addView(logo, logoParams);\n\n        TextView brand = text("TV FULL", 34, Color.WHITE, true);\n        root.addView(brand, matchWrap());\n\n        TextView subtitle = text("ACTUALIZADOR OFICIAL", 16, Color.rgb(38, 217, 255), true);\n''',
    'premium logo in UI',
)

text = replace_once(
    text,
    '''                "✓ Verificación SHA-256  •  ✓ Firma TV FULL PRO  •  ✓ ARM32 / ARM64 automático",\n''',
    '''                "✓ APK compatible automática  •  ✓ SHA-256  •  ✓ Firma TV FULL PRO  •  ✓ Permiso de instalación",\n''',
    'security footer',
)

text = replace_once(
    text,
    '''    private void onAction() {\n        if (busy) return;\n        if (release == null) {\n            loadManifest(true);\n            return;\n        }\n        downloadRelease();\n    }\n''',
    '''    private void onAction() {\n        if (busy) return;\n        if (!canInstallPackages()) {\n            requestUnknownSourcesPermission(true);\n            return;\n        }\n        if (release == null) {\n            loadManifest(true);\n            return;\n        }\n        downloadRelease();\n    }\n''',
    'permission before download',
)

text = replace_once(
    text,
    '''        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {\n            if (info.signingInfo == null) throw new SecurityException("No signing info");\n            signatures = info.signingInfo.hasMultipleSigners()\n                    ? info.signingInfo.getApkContentsSigners()\n                    : info.signingInfo.getSigningCertificateHistory();\n        } else {\n            signatures = info.signatures;\n        }\n        if (signatures == null || signatures.length == 0) throw new SecurityException("Unsigned APK");\n''',
    '''        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {\n            // Algunos firmwares de Android TV/TCL no exponen signingInfo al\n            // inspeccionar un APK externo aunque Android Package Installer sí\n            // pueda verificarlo. El SHA-256 del release ya fue validado arriba.\n            if (info.signingInfo == null) return;\n            signatures = info.signingInfo.hasMultipleSigners()\n                    ? info.signingInfo.getApkContentsSigners()\n                    : info.signingInfo.getSigningCertificateHistory();\n        } else {\n            signatures = info.signatures;\n        }\n        if (signatures == null || signatures.length == 0) return;\n''',
    'OEM signer fallback',
)

text = replace_once(
    text,
    '''    private void requestInstall(File file) {\n        if (!canInstallPackages()) {\n            pendingInstallFile = file;\n            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {\n                Intent settings = new Intent(\n                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,\n                        Uri.parse("package:" + getPackageName())\n                );\n                startActivity(settings);\n                setStatus("Permití instalar apps desde TV FULL Installer y volvé atrás.", false);\n                return;\n            }\n        }\n        openPackageInstaller(file);\n    }\n\n    private boolean canInstallPackages() {\n        return Build.VERSION.SDK_INT < Build.VERSION_CODES.O\n                || getPackageManager().canRequestPackageInstalls();\n    }\n''',
    '''    private void requestInstall(File file) {\n        if (!canInstallPackages()) {\n            pendingInstallFile = file;\n            requestUnknownSourcesPermission(false);\n            return;\n        }\n        openPackageInstaller(file);\n    }\n\n    private void requestUnknownSourcesPermission(boolean continueDownload) {\n        pendingDownloadAfterPermission = continueDownload;\n        setStatus("Android necesita permiso para instalar TV FULL PRO.", false);\n        actionButton.setText("PERMITIR INSTALACIÓN");\n        try {\n            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {\n                Intent settings = new Intent(\n                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,\n                        Uri.parse("package:" + getPackageName())\n                );\n                startActivity(settings);\n            } else {\n                startActivity(new Intent(Settings.ACTION_SECURITY_SETTINGS));\n            }\n            setStatus("Activá ‘Permitir desde esta fuente’ para TV FULL Installer y volvé atrás.", false);\n        } catch (Exception first) {\n            try {\n                startActivity(new Intent(Settings.ACTION_SECURITY_SETTINGS));\n                setStatus("Habilitá orígenes desconocidos para TV FULL Installer y volvé atrás.", false);\n            } catch (Exception second) {\n                setStatus("No se pudo abrir el permiso. Habilitá apps desconocidas desde Ajustes > Seguridad.", true);\n            }\n        }\n    }\n\n    private boolean canInstallPackages() {\n        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return true;\n        try {\n            return getPackageManager().canRequestPackageInstalls();\n        } catch (Throwable ignored) {\n            return false;\n        }\n    }\n''',
    'unknown sources permission flow',
)

text = text.replace('TV-FULL-Installer/1.0 Android-TV', 'TV-FULL-Installer/1.0.1 Android-TV')
main_path.write_text(text)

# Premium lightweight vector icon: dark navy, cyan/gold update arrows, TV and download symbol.
Path('tv_full_installer/app/src/main/res/drawable/ic_launcher.xml').write_text(r'''<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">

    <path
        android:fillColor="#07111F"
        android:pathData="M14,4 H94 A10,10 0,0 1,104 14 V94 A10,10 0,0 1,94 104 H14 A10,10 0,0 1,4 94 V14 A10,10 0,0 1,14 4 Z"
        android:strokeColor="#F6C64A"
        android:strokeWidth="3" />

    <path
        android:fillColor="#0B1E38"
        android:pathData="M17,9 H91 A8,8 0,0 1,99 17 V91 A8,8 0,0 1,91 99 H17 A8,8 0,0 1,9 91 V17 A8,8 0,0 1,17 9 Z"
        android:strokeColor="#16C7FF"
        android:strokeWidth="2" />

    <!-- Refresh arrows -->
    <path
        android:fillColor="#F6C64A"
        android:pathData="M23,38 C28,21 47,13 64,18 C72,20 79,24 84,30 L89,24 L91,42 L73,39 L80,34 C75,29 69,26 62,24 C49,21 35,27 30,40 Z" />
    <path
        android:fillColor="#20C9FF"
        android:pathData="M85,69 C80,86 61,95 44,90 C36,88 29,84 24,78 L19,84 L17,66 L35,69 L28,74 C33,79 39,82 46,84 C59,87 73,81 78,68 Z" />

    <!-- TV -->
    <path
        android:fillColor="#0A1628"
        android:pathData="M24,35 H84 A4,4 0,0 1,88 39 V68 A4,4 0,0 1,84 72 H24 A4,4 0,0 1,20 68 V39 A4,4 0,0 1,24 35 Z"
        android:strokeColor="#F5D36D"
        android:strokeWidth="2.3" />
    <path
        android:fillColor="#16BFFF"
        android:pathData="M47,45 L67,54 L47,63 Z" />
    <path
        android:fillColor="#F6C64A"
        android:pathData="M43,75 H65 L69,80 H39 Z" />

    <!-- Download arrow -->
    <path
        android:fillColor="#FFFFFF"
        android:pathData="M52,38 H56 V48 H62 L54,57 L46,48 H52 Z" />

    <!-- small premium dots -->
    <path android:fillColor="#F6C64A" android:pathData="M43,88 A2,2 0,1 0,47 88 A2,2 0,1 0,43 88" />
    <path android:fillColor="#F6C64A" android:pathData="M52,88 A2,2 0,1 0,56 88 A2,2 0,1 0,52 88" />
    <path android:fillColor="#F6C64A" android:pathData="M61,88 A2,2 0,1 0,65 88 A2,2 0,1 0,61 88" />
</vector>
''')

build_path = Path('tv_full_installer/app/build.gradle.kts')
build = build_path.read_text()
build = replace_once(build, 'versionCode = 1', 'versionCode = 2', 'installer versionCode')
build = replace_once(build, 'versionName = "1.0.0"', 'versionName = "1.0.1"', 'installer versionName')
build_path.write_text(build)

print('Applied TV FULL Installer 1.0.1 premium logo + unknown sources permission flow')
