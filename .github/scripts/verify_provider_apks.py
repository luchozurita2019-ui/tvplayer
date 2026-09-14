"""Verify signed release APKs before producing the installer's manifest."""

import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def build_tool(name):
    candidates = list(Path(os.environ["ANDROID_HOME"]).glob(f"build-tools/*/{name}"))
    require(candidates, f"Android build tool missing: {name}")
    return max(candidates, key=lambda path: tuple(
        int(part) for part in re.findall(r"\d+", path.parent.name)
    ))


def main():
    version = os.environ["BUILD_NAME"]
    number = int(os.environ["BUILD_NUMBER"])
    release_number = int(os.environ["RELEASE_NUMBER"])
    certificate = os.environ["CERT_SHA256"].lower()
    package = "com.tvfull.pro.tv.v10safe"
    tag = (f"tv-full-pro-v{release_number}-provider-json-"
           f"{os.environ['GITHUB_RUN_ID']}-{os.environ['GITHUB_RUN_ATTEMPT']}")
    release_url = f"https://github.com/{os.environ['GITHUB_REPOSITORY']}/releases/download/{tag}"
    artifact = Path("artifact")
    artifact.mkdir(exist_ok=True)
    manifest = {
        "versionName": version,
        "versionCode": number,
        "packageName": package,
        "certificateSha256": certificate,
    }
    signer, aapt = build_tool("apksigner"), build_tool("aapt")
    variants = (("arm32", "armeabi-v7a"), ("arm64", "arm64-v8a"))
    for label, abi in variants:
        apk = artifact / f"TV-FULL-PRO-V{release_number}-{label.upper()}.apk"
        shutil.copyfile(f"build/app/outputs/flutter-apk/app-{abi}-release.apk", apk)
    for label, abi in variants:
        apk = artifact / f"TV-FULL-PRO-V{release_number}-{label.upper()}.apk"
        signature = subprocess.check_output(
            [signer, "verify", "--verbose", "--print-certs", apk], text=True
        )
        apk.with_suffix(".apk.signature.txt").write_text(signature)
        # Build Tools now report "V2 Signer:"; older releases used "Signer #1".
        fingerprints = re.findall(
            r"^(?:Signer #\d+|V\d+(?:\.\d+)? Signer):? certificate SHA-256 digest: ([a-fA-F0-9:]+)$",
            signature, re.MULTILINE,
        )
        require(fingerprints, f"No signing certificate found in apksigner output: {apk.name}")
        require(all(value.replace(":", "").lower() == certificate for value in fingerprints),
                f"Historical certificate mismatch: {apk.name}")
        print(f"Verified historical certificate for {apk.name}: {certificate}")
        badging = subprocess.check_output([aapt, "dump", "badging", apk], text=True)
        apk.with_suffix(".apk.badging.txt").write_text(badging)
        package_line = next(line for line in badging.splitlines() if line.startswith("package: "))
        attributes = dict(re.findall(r"(\w+)='([^']*)'", package_line))
        require(attributes.get("name") == package, f"Package mismatch: {apk.name}")
        require(attributes.get("versionName") == version, f"Version name mismatch: {apk.name}")
        require(attributes.get("versionCode") == str(number), f"Version code mismatch: {apk.name}")
        native_line = next(line for line in badging.splitlines() if line.startswith("native-code: "))
        require(re.findall(r"'([^']*)'", native_line) == [abi], f"Architecture mismatch: {apk.name}")
        require("application-debuggable" not in badging, f"Debuggable release: {apk.name}")
        manifest[label] = {
            "url": f"{release_url}/{apk.name}",
            "sha256": hashlib.sha256(apk.read_bytes()).hexdigest(),
            "size": apk.stat().st_size,
        }
    (artifact / "latest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
