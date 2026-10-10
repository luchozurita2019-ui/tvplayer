#!/usr/bin/env python3
"""Valida los metadatos y las invariantes de la base oficial de Android TV."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = "com.tvfull.pro.tv.v10safe"
CERTIFICATE = "40de9b14a83adb7b070e316a241e7f5a7f5b1705fdc43b5f495b0e1e3fcab02a"
PLAYLIST = "https://raw.githubusercontent.com/luchozurita2019-ui/mi-lista-iptv-4k/main/lista_clasica.m3u"
UPDATES = "https://raw.githubusercontent.com/luchozurita2019-ui/tvplayer/auto-update-json-test/update.json"


def require(condition, message):
    if not condition:
        raise SystemExit(message)


def main():
    pubspec = (ROOT / "pubspec.yaml").read_text()
    match = re.search(r"^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$", pubspec, re.MULTILINE)
    require(match is not None, "pubspec.yaml debe incluir versionName+versionCode")
    version_name, version_code = match.group(1), int(match.group(2))
    require(version_code >= 3054, "La base oficial no puede volver a una versión anterior a V54")

    update = json.loads((ROOT / "update.json").read_text())
    installer = json.loads((ROOT / "tv_full_installer/latest.json").read_text())
    require(type(update["version_code"]) is int and update["version_code"] >= 3054,
            "El manifiesto publicado no puede volver a una versión anterior a V54")
    require(installer["versionCode"] == update["version_code"], "Los manifiestos tienen versionCode distintos")
    require(installer["versionName"] == update["version_name"], "Los manifiestos tienen versionName distintos")
    require(version_code >= update["version_code"], "El código es más antiguo que la APK publicada")
    if version_code == update["version_code"]:
        require(version_name == update["version_name"], "La misma versión debe conservar su versionName")
    require(installer["packageName"] == PACKAGE, "Se cambió el identificador de la aplicación")
    require(installer["certificateSha256"] == CERTIFICATE, "Se cambió la firma histórica")
    require(re.fullmatch(r"[0-9a-f]{64}", update["sha256"]) is not None, "SHA-256 inválido")
    prefix = "https://github.com/luchozurita2019-ui/tvplayer/releases/download/"
    require(update["apk_url"].startswith(prefix) and update["apk_url"].endswith(".apk"),
            "La APK debe apuntar a una release del repositorio")
    for abi in ("arm32", "arm64"):
        asset = installer[abi]
        require(asset["url"] == update["apk_url"], f"La APK universal no coincide para {abi}")
        require(asset["sha256"] == update["sha256"], f"El SHA-256 no coincide para {abi}")
        require(type(asset["size"]) is int and asset["size"] > 0, f"Tamaño de APK inválido para {abi}")

    provider = (ROOT / "lib/providers/iptv_provider.dart").read_text()
    updater = (ROOT / "lib/services/app_update_service.dart").read_text()
    gradle = (ROOT / "android/app/build.gradle.kts").read_text()
    require(PLAYLIST in provider, "Se cambió la M3U remota")
    require(UPDATES in updater, "Se cambió el JSON activo de actualizaciones")
    require(f'applicationId = "{PACKAGE}"' in gradle, "Se cambió el packageName de Android")
    require('signingConfigs.getByName("release")' in gradle, "Falta la configuración de firma release")
    print(f"Base oficial verificada: {version_name}+{version_code}, M3U, JSON, paquete y firma histórica")


if __name__ == "__main__":
    main()
