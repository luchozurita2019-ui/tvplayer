#!/usr/bin/env python3
"""Comprueba las dos URL y las arquitecturas dentro de la APK compilada."""
import sys
from zipfile import ZipFile

EXPECTED = (
    b"https://raw.githubusercontent.com/luchozurita2019-ui/mi-lista-iptv-4k/main/lista_clasica.m3u",
    b"https://raw.githubusercontent.com/luchozurita2019-ui/tvplayer/auto-update-json-test/update.json",
)
with ZipFile(sys.argv[1]) as archive:
    libraries = [name for name in archive.namelist() if name.endswith("/libapp.so")]
    for abi in ("armeabi-v7a", "arm64-v8a"):
        assert f"lib/{abi}/libapp.so" in libraries, f"Falta {abi}"
    for name in libraries:
        data = archive.read(name)
        for url in EXPECTED:
            assert url in data, f"Falta URL en {name}: {url.decode()}"
print("APK verificada: M3U remota, JSON de actualización y ARM32/ARM64")
