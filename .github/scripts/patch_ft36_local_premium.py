#!/usr/bin/env python3
from pathlib import Path
import re
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: patch_ft36_local_premium.py <decoded_apk_dir>")

root = Path(sys.argv[1])
o0 = root / "smali" / "Q1" / "O0.smali"
main = root / "smali" / "com" / "byrafael" / "streamapp" / "MainActivity.smali"

if not o0.exists() or not main.exists():
    raise SystemExit("FT 3.6 smali layout not found")

# 1) Authorized security test: force only the CLIENT-SIDE PRO boolean.
#    Any assignment to O0.f is rewritten to true. This intentionally does
#    not alter /sesion, /plat/get, signatures, anon_id, or server responses.
text = o0.read_text(encoding="utf-8")
pattern = re.compile(r"(?m)^(\s*)sput-boolean\s+([vp]\d+),\s+LQ1/O0;->f:Z\s*$")
matches = list(pattern.finditer(text))
if not matches:
    raise SystemExit("O0.f assignments not found")
text = pattern.sub(
    lambda m: f"{m.group(1)}const/4 {m.group(2)}, 0x1\n"
              f"{m.group(1)}sput-boolean {m.group(2)}, LQ1/O0;->f:Z",
    text,
)
o0.write_text(text, encoding="utf-8")

# 1b) Authorized test: disable the client-side ad gate completely.
#     This mirrors the local behavior of an activated/no-ads client while
#     leaving the Worker responses and Netflix server-side controls untouched.
text = o0.read_text(encoding="utf-8")
ad_gate = re.compile(
    r"(?ms)\.method public static c\(\)Z\n.*?\.end method"
)
match = ad_gate.search(text)
if not match:
    raise SystemExit("O0.c ad gate method not found")

replacement = """.method public static c()Z
    .registers 1

    const/4 v0, 0x0

    return v0
.end method"""

text = ad_gate.sub(replacement, text, count=1)
o0.write_text(text, encoding="utf-8")
print("patched client-side ad gate: disabled")

# 2) The repacked test APK is signed with the TV FULL test key, but Rafael's
#    native Guard expects the digest of the authorized FT 3.6 certificate.
#    Override only the byte[] supplied to Guard with Rafael's original public
#    certificate SHA-256 digest. No private key or account secret is embedded.
main_text = main.read_text(encoding="utf-8")
needle = "    sput-object v0, Lcom/byrafael/streamapp/Guard;->b:[B\n"
idx = main_text.find(needle)
if idx < 0:
    raise SystemExit("Guard certificate assignment not found")

override = (
    needle
    + "\n"
    + "    # Rafael-authorized repack test: preserve original FT certificate digest for Guard\n"
    + "    const-string v0, \"UXGOPSg0is9y/Fejlby58bGp/mO8H8+j9BuOi0A8rb4=\"\n"
    + "    const/4 v14, 0x2\n"
    + "    invoke-static {v0, v14}, Landroid/util/Base64;->decode(Ljava/lang/String;I)[B\n"
    + "    move-result-object v0\n"
    + "    sput-object v0, Lcom/byrafael/streamapp/Guard;->b:[B\n"
)

main_text = main_text[:idx] + main_text[idx:].replace(needle, override, 1)
main.write_text(main_text, encoding="utf-8")

print(f"patched {len(matches)} O0.f assignments")
print("patched Guard certificate digest source")
