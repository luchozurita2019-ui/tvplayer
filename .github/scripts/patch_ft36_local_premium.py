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


# 3) TV FULL bridge: when TV FULL launches FT with tvfull_netflix_bridge=true,
#    automatically open the ORIGINAL Netflix card. The card's click handler,
#    /plat/get flow and q3.a.z generator remain untouched.
main_text = main.read_text(encoding="utf-8")
listener_needle = """    invoke-virtual {v0, v2}, Landroid/view/View;->setOnClickListener(Landroid/view/View$OnClickListener;)V

    iget-object v0, v1, Lcom/byrafael/streamapp/MainActivity;->S0:Landroid/widget/TextView;
"""
if listener_needle not in main_text:
    raise SystemExit("Netflix card listener anchor not found")

listener_patch = """    invoke-virtual {v0, v2}, Landroid/view/View;->setOnClickListener(Landroid/view/View$OnClickListener;)V

    # TV FULL bridge: auto-open the original Netflix card only for an explicit bridge launch.
    invoke-virtual {v1}, Landroid/app/Activity;->getIntent()Landroid/content/Intent;
    move-result-object v2

    const-string v3, "tvfull_netflix_bridge"
    const/4 v4, 0x0
    invoke-virtual {v2, v3, v4}, Landroid/content/Intent;->getBooleanExtra(Ljava/lang/String;Z)Z
    move-result v2

    if-eqz v2, :tvfull_bridge_skip_auto_netflix

    iget-object v0, v1, Lcom/byrafael/streamapp/MainActivity;->w1:Landroid/view/View;
    if-eqz v0, :tvfull_bridge_skip_auto_netflix

    const/4 v2, 0x0
    invoke-virtual {v0, v2}, Landroid/view/View;->setVisibility(I)V
    invoke-virtual {v0}, Landroid/view/View;->performClick()Z
    move-result v2

    :tvfull_bridge_skip_auto_netflix
    iget-object v0, v1, Lcom/byrafael/streamapp/MainActivity;->S0:Landroid/widget/TextView;
"""
main_text = main_text.replace(listener_needle, listener_patch, 1)
main.write_text(main_text, encoding="utf-8")
print("patched TV FULL bridge auto-open into original Netflix card")

# 4) Return ONLY the already-generated final phone/tv URLs to TV FULL.
#    q3.a.z remains completely unchanged; this patch runs after it returned W0.
c0 = root / "smali" / "Q1" / "C0.smali"
if not c0.exists():
    raise SystemExit("Q1/C0.smali not found")
c0_text = c0.read_text(encoding="utf-8")
success_needle = """:cond_63
    iput-boolean v9, v1, Lcom/byrafael/streamapp/MainActivity;->z1:Z

    .line 101
"""
if success_needle not in c0_text:
    raise SystemExit("Netflix success anchor not found in C0.smali")

success_patch = """:cond_63
    iput-boolean v9, v1, Lcom/byrafael/streamapp/MainActivity;->z1:Z

    # If this generation was launched from TV FULL, return the final W0 URLs.
    invoke-virtual {v1}, Landroid/app/Activity;->getIntent()Landroid/content/Intent;
    move-result-object v10

    const-string v11, "tvfull_netflix_bridge"
    const/4 v12, 0x0
    invoke-virtual {v10, v11, v12}, Landroid/content/Intent;->getBooleanExtra(Ljava/lang/String;Z)Z
    move-result v10

    if-eqz v10, :tvfull_bridge_continue_ft_ui

    new-instance v10, Landroid/content/Intent;
    invoke-direct {v10}, Landroid/content/Intent;-><init>()V

    const-string v11, "com.tvfull.pro.tv.v10safe"
    const-string v12, "com.example.iptv_player.MainActivity"
    invoke-virtual {v10, v11, v12}, Landroid/content/Intent;->setClassName(Ljava/lang/String;Ljava/lang/String;)Landroid/content/Intent;
    move-result-object v10

    const-string v11, "tvfull_netflix_phone"
    iget-object v12, v0, LQ1/W0;->b:Ljava/lang/String;
    invoke-virtual {v10, v11, v12}, Landroid/content/Intent;->putExtra(Ljava/lang/String;Ljava/lang/String;)Landroid/content/Intent;
    move-result-object v10

    const-string v11, "tvfull_netflix_tv"
    iget-object v12, v0, LQ1/W0;->c:Ljava/lang/String;
    invoke-virtual {v10, v11, v12}, Landroid/content/Intent;->putExtra(Ljava/lang/String;Ljava/lang/String;)Landroid/content/Intent;
    move-result-object v10

    const-string v11, "tvfull_netflix_expira"
    iget-wide v8, v0, LQ1/W0;->d:J
    invoke-virtual {v10, v11, v8, v9}, Landroid/content/Intent;->putExtra(Ljava/lang/String;J)Landroid/content/Intent;
    move-result-object v10

    const/high16 v11, 0x20000
    invoke-virtual {v10, v11}, Landroid/content/Intent;->addFlags(I)Landroid/content/Intent;
    move-result-object v10

    invoke-virtual {v1, v10}, Landroid/app/Activity;->startActivity(Landroid/content/Intent;)V
    invoke-virtual {v1}, Landroid/app/Activity;->finish()V

    goto :goto_91

    :tvfull_bridge_continue_ft_ui
    const/4 v9, 0x0

    .line 101
"""
c0_text = c0_text.replace(success_needle, success_patch, 1)
c0.write_text(c0_text, encoding="utf-8")
print("patched TV FULL bridge return of final Netflix URLs; generator untouched")
