from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old in text:
        return text.replace(old, new, 1)
    if new in text:
        return text
    raise RuntimeError(f"No se encontró el bloque esperado: {label}")


# ---------------------------------------------------------------------------
# 1) Version bump
# ---------------------------------------------------------------------------
pubspec_path = ROOT / "pubspec.yaml"
pubspec = pubspec_path.read_text(encoding="utf-8")
pubspec = replace_once(pubspec, "version: 1.2.3+15", "version: 1.2.4+16", "version")
pubspec = pubspec.replace(
    "# TV FULL PRO 1.2.3+15 live-speed validation marker.",
    "# TV FULL PRO 1.2.4+16 automatic-version-stamp marker.",
)
pubspec_path.write_text(pubspec, encoding="utf-8")


# ---------------------------------------------------------------------------
# 2) Native Android: expose actual installed versionName/versionCode.
# ---------------------------------------------------------------------------
kotlin_path = ROOT / "android/app/src/main/kotlin/com/example/iptv_player/MainActivity.kt"
kotlin = kotlin_path.read_text(encoding="utf-8")
kotlin = replace_once(
    kotlin,
    "import android.os.Handler\nimport android.os.Looper",
    "import android.os.Build\nimport android.os.Handler\nimport android.os.Looper",
    "Android Build import",
)

kotlin = replace_once(
    kotlin,
    '''                    "getDeviceProfile" -> {
                        val manager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
''',
    '''                    "getAppVersion" -> {
                        val info = packageManager.getPackageInfo(packageName, 0)
                        @Suppress("DEPRECATION")
                        val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            info.longVersionCode
                        } else {
                            info.versionCode.toLong()
                        }
                        result.success(
                            mapOf(
                                "versionName" to (info.versionName ?: ""),
                                "versionCode" to code,
                            )
                        )
                    }
                    "getDeviceProfile" -> {
                        val manager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
''',
    "native app version method",
)
kotlin_path.write_text(kotlin, encoding="utf-8")


# ---------------------------------------------------------------------------
# 3) Shared Dart service: one source of truth for current installed version.
# ---------------------------------------------------------------------------
version_service_path = ROOT / "lib/services/app_version_service.dart"
version_service_path.write_text(
    '''import 'package:flutter/services.dart';

class AppVersionInfo {
  final String versionName;
  final int versionCode;

  const AppVersionInfo({
    required this.versionName,
    required this.versionCode,
  });

  String get label => 'Versión $versionName • Build $versionCode';
  String get compactLabel => 'v$versionName+$versionCode';
}

class AppVersionService {
  AppVersionService._();

  static final AppVersionService instance = AppVersionService._();
  static const MethodChannel _channel = MethodChannel('tvfull/device_identity');

  AppVersionInfo? _cached;

  Future<AppVersionInfo> get current async {
    final cached = _cached;
    if (cached != null) return cached;

    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('getAppVersion');
      final versionName = '${raw?['versionName'] ?? ''}'.trim();
      final rawCode = raw?['versionCode'];
      final versionCode = rawCode is num
          ? rawCode.toInt()
          : int.tryParse('$rawCode') ?? 0;
      if (versionName.isNotEmpty && versionCode > 0) {
        return _cached = AppVersionInfo(
          versionName: versionName,
          versionCode: versionCode,
        );
      }
    } catch (_) {
      // La identificación visual no debe bloquear la aplicación.
    }

    return const AppVersionInfo(versionName: 'desconocida', versionCode: 0);
  }
}
''',
    encoding="utf-8",
)


# ---------------------------------------------------------------------------
# 4) Reusable unobtrusive version badge.
# ---------------------------------------------------------------------------
badge_path = ROOT / "lib/widgets/app_version_badge.dart"
badge_path.write_text(
    '''import 'package:flutter/material.dart';

import '../services/app_version_service.dart';

class AppVersionBadge extends StatefulWidget {
  final bool compact;

  const AppVersionBadge({super.key, this.compact = false});

  @override
  State<AppVersionBadge> createState() => _AppVersionBadgeState();
}

class _AppVersionBadgeState extends State<AppVersionBadge> {
  late final Future<AppVersionInfo> _version = AppVersionService.instance.current;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppVersionInfo>(
      future: _version,
      builder: (context, snapshot) {
        final info = snapshot.data;
        if (info == null || info.versionCode <= 0) {
          return const SizedBox.shrink();
        }
        return Text(
          widget.compact ? info.compactLabel : info.label,
          maxLines: 1,
          style: const TextStyle(
            color: Colors.white30,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: .2,
          ),
        );
      },
    );
  }
}
''',
    encoding="utf-8",
)


# ---------------------------------------------------------------------------
# 5) Update checker: stop using stale hardcoded version values.
# ---------------------------------------------------------------------------
update_path = ROOT / "lib/services/app_update_service.dart"
update = update_path.read_text(encoding="utf-8")
update = replace_once(
    update,
    "import 'package:url_launcher/url_launcher.dart';\n",
    "import 'package:url_launcher/url_launcher.dart';\n\nimport 'app_version_service.dart';\n",
    "AppVersionService import",
)
update = update.replace(
    "  static const int currentVersionCode = 14;\n  static const String currentVersionName = '1.2.2';\n",
    "",
)
update = replace_once(
    update,
    "    _checked = true;\n    _checking = true;\n    try {\n      final response",
    "    _checked = true;\n    _checking = true;\n    try {\n      final installed = await AppVersionService.instance.current;\n      final response",
    "installed version lookup",
)
update = replace_once(
    update,
    "          versionCode > currentVersionCode &&",
    "          versionCode > installed.versionCode &&",
    "dynamic update version comparison",
)
update_path.write_text(update, encoding="utf-8")


# ---------------------------------------------------------------------------
# 6) Main screen: always-visible, low-profile installed version.
# ---------------------------------------------------------------------------
source_path = ROOT / "lib/screens/source_content_screen.dart"
source = source_path.read_text(encoding="utf-8")
source = replace_once(
    source,
    "import '../widgets/parental_lock_button.dart';",
    "import '../widgets/app_version_badge.dart';\nimport '../widgets/parental_lock_button.dart';",
    "source version badge import",
)
source = replace_once(
    source,
    "              const Spacer(),\n            ],",
    "              const Spacer(),\n              const Align(\n                alignment: Alignment.centerRight,\n                child: AppVersionBadge(),\n              ),\n            ],",
    "source version badge",
)
source_path.write_text(source, encoding="utf-8")


# ---------------------------------------------------------------------------
# 7) Startup / blocked screen also shows the installed build.
# ---------------------------------------------------------------------------
home_path = ROOT / "lib/screens/home_screen.dart"
home = home_path.read_text(encoding="utf-8")
home = replace_once(
    home,
    "import '../services/remote_access_guard.dart';\n",
    "import '../services/remote_access_guard.dart';\nimport '../widgets/app_version_badge.dart';\n",
    "home version badge import",
)
home = replace_once(
    home,
    "                  if (busy) ...[\n                    const SizedBox(height: 28),\n                    const SizedBox(\n                      width: 34,\n                      height: 34,\n                      child: CircularProgressIndicator(strokeWidth: 3),\n                    ),\n                  ],",
    "                  if (busy) ...[\n                    const SizedBox(height: 28),\n                    const SizedBox(\n                      width: 34,\n                      height: 34,\n                      child: CircularProgressIndicator(strokeWidth: 3),\n                    ),\n                  ],\n                  const SizedBox(height: 20),\n                  const AppVersionBadge(),",
    "startup version badge",
)
home_path.write_text(home, encoding="utf-8")


# Safety checks.
checks = {
    pubspec_path: ["version: 1.2.4+16"],
    kotlin_path: ['"getAppVersion"', '"versionName"', '"versionCode"'],
    update_path: ["installed.versionCode", "AppVersionService.instance.current"],
    source_path: ["AppVersionBadge"],
    home_path: ["AppVersionBadge"],
}
for path, markers in checks.items():
    text = path.read_text(encoding="utf-8")
    for marker in markers:
        if marker not in text:
            raise RuntimeError(f"Falta marcador {marker} en {path}")

print("TV FULL PRO 1.2.4+16: version stamp automático aplicado")
