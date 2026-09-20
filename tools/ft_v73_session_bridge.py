#!/usr/bin/env python3
"""
Puente local autorizado FT -> TV FULL para la prueba V73.

Lee el anon_id de la instalación original de Fútbol Total dentro de su propio
proceso mediante Frida y lo entrega a la build aislada de TV FULL usando un
Intent ADB. No imprime ni guarda el identificador en disco.
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import threading
import time
import uuid

FT_PACKAGE = "com.byrafael.streamapp"
TVFULL_PACKAGE = "com.tvfull.pro.tv.v10safe"
TVFULL_ACTIVITY = "com.example.iptv_player.MainActivity"

FRIDA_JS = r"""
Java.perform(function () {
    try {
        var ActivityThread = Java.use("android.app.ActivityThread");
        var app = ActivityThread.currentApplication();
        if (app === null) {
            send({type: "error", message: "sin Application"});
            return;
        }
        var ctx = app.getApplicationContext();
        var prefs = ctx.getSharedPreferences("ft_state", 0);
        var id = prefs.getString("anon_id", null);
        if (id === null || String(id).length === 0) {
            send({type: "error", message: "anon_id ausente"});
            return;
        }
        send({type: "ft_id", value: String(id)});
    } catch (e) {
        send({type: "error", message: String(e)});
    }
});
"""


def run(cmd: list[str], check: bool = True, timeout: float = 20.0) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        cmd,
        check=check,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
    )


def find_adb(explicit: str | None) -> str:
    candidates = []
    if explicit:
        candidates.append(explicit)
    candidates.append(os.path.expanduser("~/Downloads/platform-tools/adb"))
    candidates.append("adb")
    for candidate in candidates:
        try:
            run([candidate, "version"], timeout=5)
            return candidate
        except Exception:
            continue
    raise RuntimeError("No encuentro adb. Usá --adb /ruta/al/adb")


def ensure_ft_running(adb: str) -> int:
    out = run([adb, "shell", "pidof", FT_PACKAGE], check=False, timeout=5).stdout.strip()
    if not out:
        run(
            [adb, "shell", "monkey", "-p", FT_PACKAGE, "-c", "android.intent.category.LAUNCHER", "1"],
            check=False,
            timeout=15,
        )
        time.sleep(1.5)
        out = run([adb, "shell", "pidof", FT_PACKAGE], check=False, timeout=5).stdout.strip()
    if not out:
        raise RuntimeError("Fútbol Total no está ejecutándose en el dispositivo")
    return int(out.split()[0])


def extract_id_with_frida(pid: int) -> str:
    try:
        import frida  # type: ignore
    except Exception as exc:
        raise RuntimeError("Falta el módulo Python frida. Instalalo con: python3 -m pip install frida-tools") from exc

    device = frida.get_usb_device(timeout=7)
    session = device.attach(pid)
    done = threading.Event()
    result: dict[str, str] = {}

    def on_message(message, data):
        if message.get("type") == "send":
            payload = message.get("payload") or {}
            if payload.get("type") == "ft_id":
                result["id"] = str(payload.get("value") or "")
                done.set()
            elif payload.get("type") == "error":
                result["error"] = str(payload.get("message") or "error")
                done.set()
        elif message.get("type") == "error":
            result["error"] = str(message.get("description") or "error Frida")
            done.set()

    script = session.create_script(FRIDA_JS)
    script.on("message", on_message)
    script.load()
    done.wait(10)
    try:
        script.unload()
    except Exception:
        pass
    try:
        session.detach()
    except Exception:
        pass

    if "error" in result:
        raise RuntimeError(result["error"])
    raw = result.get("id", "").strip()
    try:
        parsed = str(uuid.UUID(raw))
    except Exception as exc:
        raise RuntimeError("El anon_id recibido no es un UUID válido") from exc
    return parsed


def import_into_tvfull(adb: str, anon_id: str) -> None:
    component = f"{TVFULL_PACKAGE}/{TVFULL_ACTIVITY}"
    proc = run(
        [
            adb,
            "shell",
            "am",
            "start",
            "-n",
            component,
            "--es",
            "ft_bridge",
            "1",
            "--es",
            "ft_anon_id",
            anon_id,
        ],
        check=False,
        timeout=15,
    )
    combined = (proc.stdout + "\n" + proc.stderr).lower()
    if proc.returncode != 0 or "error" in combined:
        raise RuntimeError("No pude entregar el ID a TV FULL por ADB")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--adb", default=None)
    args = parser.parse_args()

    try:
        adb = find_adb(args.adb)
        devices = run([adb, "devices"], timeout=5).stdout
        if "\tdevice" not in devices:
            raise RuntimeError("No hay un dispositivo ADB autorizado")

        print("[1/3] Abriendo/ubicando Fútbol Total...")
        pid = ensure_ft_running(adb)

        print("[2/3] Leyendo el identificador de sesión dentro de Fútbol Total...")
        anon_id = extract_id_with_frida(pid)

        print("[3/3] Entregando la sesión a TV FULL V73...")
        import_into_tvfull(adb, anon_id)

        print("[OK] Sesión FT transferida sin mostrar ni guardar el identificador.")
        print("[OK] Abrí Streaming Premium y probá Prime primero.")
        return 0
    except Exception as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
