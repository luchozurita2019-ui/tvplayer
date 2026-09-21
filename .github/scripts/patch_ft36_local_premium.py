#!/usr/bin/env python3
from pathlib import Path
import re
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: patch_ft36_local_premium.py <decoded_apk_dir>")

root = Path(sys.argv[1])

def find_class(descriptor: str) -> Path:
    for base in sorted(root.glob("smali*")):
        if not base.is_dir():
            continue
        for path in base.rglob("*.smali"):
            try:
                head = path.read_text(encoding="utf-8", errors="ignore")[:1200]
            except Exception:
                continue
            if descriptor in head:
                return path
    raise SystemExit(f"smali class not found: {descriptor}")

o0 = find_class("LQ1/O0;")
main = find_class("Lcom/byrafael/streamapp/MainActivity;")
n_file = find_class("LQ1/N;")
c0_file = find_class("LQ1/C0;")
b0_file = find_class("LQ1/B0;")

# 1) Authorized test client behavior: local PRO=true.
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

# Disable only FT's local ad gate for this authorized bridge build.
ad_gate = re.compile(r"(?ms)\.method public static c\(\)Z\n.*?\.end method")
if not ad_gate.search(text):
    raise SystemExit("O0.c ad gate method not found")
text = ad_gate.sub(
    """.method public static c()Z
    .registers 1

    const/4 v0, 0x0

    return v0
.end method""",
    text,
    count=1,
)
o0.write_text(text, encoding="utf-8")

# 2) Preserve Rafael's original public certificate digest for the native Guard
# while the authorized test APK is re-signed with TV FULL's test key.
main_text = main.read_text(encoding="utf-8")
guard_pattern = re.compile(
    r"(?m)^(?P<indent>\s*)sput-object\s+(?P<reg>[vp]\d+),\s*"
    r"Lcom/byrafael/streamapp/Guard;->b:\[B\s*$"
)
gm = guard_pattern.search(main_text)
if not gm:
    raise SystemExit("Guard certificate assignment not found")
indent = gm.group("indent")
reg = gm.group("reg")
override = (
    gm.group(0)
    + "\n\n"
    + indent + f"const-string {reg}, \"UXGOPSg0is9y/Fejlby58bGp/mO8H8+j9BuOi0A8rb4=\"\n"
    + indent + "const/4 v14, 0x2\n"
    + indent + f"invoke-static {{{reg}, v14}}, Landroid/util/Base64;->decode(Ljava/lang/String;I)[B\n"
    + indent + f"move-result-object {reg}\n"
    + indent + f"sput-object {reg}, Lcom/byrafael/streamapp/Guard;->b:[B"
)
main_text = main_text[:gm.start()] + override + main_text[gm.end():]

# 3) Bridge preparation runs immediately after Activity.onCreate super-call.
oncreate_pattern = re.compile(
    r"(\.method public final onCreate\(Landroid/os/Bundle;\)V.*?"
    r"invoke-super(?:/range)?\s+\{p0(?:\s*\.\.\s*p1|,\s*p1)\},\s*"
    r"Lh/l;->onCreate\(Landroid/os/Bundle;\)V)",
    re.S,
)
m = oncreate_pattern.search(main_text)
if not m:
    raise SystemExit("MainActivity.onCreate super-call not found")
if "TvFullBridge;->prepare" not in m.group(1):
    replacement = m.group(1) + (
        "\n\n    invoke-static {p0}, "
        "Lcom/byrafael/streamapp/TvFullBridge;->prepare("
        "Lcom/byrafael/streamapp/MainActivity;)V"
    )
    main_text = main_text[:m.start()] + replacement + main_text[m.end():]

# 4) When TV FULL launches FT in bridge mode, press the ORIGINAL Netflix card.
card_pattern = re.compile(
    r"(const/16\s+([vp]\d+),\s+0x1b\s*\n\s*"
    r"invoke-direct\s+\{([vp]\d+),\s*([vp]\d+),\s*\2\},\s*"
    r"LQ1/N;-><init>\(Lcom/byrafael/streamapp/MainActivity;I\)V\s*\n\s*"
    r"invoke-virtual\s+\{([vp]\d+),\s*\3\},\s*"
    r"Landroid/view/View;->setOnClickListener\(Landroid/view/View\$OnClickListener;\)V)"
)
cm = card_pattern.search(main_text)
if not cm:
    # Exact layout used by FT 3.6: listener=v2, activity=v1, card=v0.
    exact = """    const/16 v3, 0x1b

    invoke-direct {v2, v1, v3}, LQ1/N;-><init>(Lcom/byrafael/streamapp/MainActivity;I)V

    invoke-virtual {v0, v2}, Landroid/view/View;->setOnClickListener(Landroid/view/View$OnClickListener;)V"""
    if exact not in main_text:
        raise SystemExit("Netflix card listener not found")
    patched = exact + """

    invoke-static {v1}, Lcom/byrafael/streamapp/TvFullBridge;->isBridge(Lcom/byrafael/streamapp/MainActivity;)Z
    move-result v3
    if-eqz v3, :tvfull_bridge_card_done
    invoke-virtual {v0}, Landroid/view/View;->performClick()Z
    :tvfull_bridge_card_done"""
    main_text = main_text.replace(exact, patched, 1)
else:
    block = cm.group(1)
    activity_reg = cm.group(4)
    card_reg = cm.group(5)
    temp_reg = cm.group(2)
    patched = block + (
        f"\n\n    invoke-static {{{activity_reg}}}, "
        "Lcom/byrafael/streamapp/TvFullBridge;->isBridge("
        "Lcom/byrafael/streamapp/MainActivity;)Z"
        f"\n    move-result {temp_reg}"
        f"\n    if-eqz {temp_reg}, :tvfull_bridge_card_done"
        f"\n    invoke-virtual {{{card_reg}}}, Landroid/view/View;->performClick()Z"
        "\n    :tvfull_bridge_card_done"
    )
    main_text = main_text[:cm.start()] + patched + main_text[cm.end():]

main.write_text(main_text, encoding="utf-8")

# 5) Inside the ORIGINAL Netflix screen, press its ORIGINAL GENERAR ACCESO button.
n_text = n_file.read_text(encoding="utf-8")
gen_listener = """    invoke-virtual {v2, v0}, Landroid/view/View;->setOnClickListener(Landroid/view/View$OnClickListener;)V

    new-instance v0, Landroid/widget/ScrollView;"""
if gen_listener not in n_text:
    raise SystemExit("Netflix GENERAR ACCESO listener not found")
n_text = n_text.replace(
    gen_listener,
    """    invoke-virtual {v2, v0}, Landroid/view/View;->setOnClickListener(Landroid/view/View$OnClickListener;)V

    invoke-static {v11}, Lcom/byrafael/streamapp/TvFullBridge;->isBridge(Lcom/byrafael/streamapp/MainActivity;)Z
    move-result v0
    if-eqz v0, :tvfull_bridge_generate_done
    invoke-virtual {v2}, Landroid/view/View;->performClick()Z
    :tvfull_bridge_generate_done

    new-instance v0, Landroid/widget/ScrollView;""",
    1,
)
n_file.write_text(n_text, encoding="utf-8")

# 6) After q3.a.z(...) returns the ORIGINAL W0 result, bridge only final phone/tv URLs.
c0_text = c0_file.read_text(encoding="utf-8")
success = """    :cond_63
    iput-boolean v9, v1, Lcom/byrafael/streamapp/MainActivity;->z1:Z"""
if success not in c0_text:
    raise SystemExit("C0 Netflix success branch not found")
c0_text = c0_text.replace(
    success,
    """    :cond_63
    invoke-static {v1, v0}, Lcom/byrafael/streamapp/TvFullBridge;->sendSuccess(Lcom/byrafael/streamapp/MainActivity;LQ1/W0;)Z
    move-result v10
    if-eqz v10, :tvfull_bridge_continue_success
    return-void
    :tvfull_bridge_continue_success
    iput-boolean v9, v1, Lcom/byrafael/streamapp/MainActivity;->z1:Z""",
    1,
)

failure = """    const-string v0, "No se pudo con esa cuenta. Toc\u00e1 de nuevo y sale otra."

    .line 95"""
if failure in c0_text:
    c0_text = c0_text.replace(
        failure,
        """    const-string v0, "No se pudo con esa cuenta. Toc\u00e1 de nuevo y sale otra."

    invoke-static {v1, v0}, Lcom/byrafael/streamapp/TvFullBridge;->sendFailure(Lcom/byrafael/streamapp/MainActivity;Ljava/lang/String;)Z

    .line 95""",
        1,
    )
c0_file.write_text(c0_text, encoding="utf-8")

# 7) If the FT map has no Netflix account/code, return a sanitized failure.
b0_text = b0_file.read_text(encoding="utf-8")
no_accounts = """    const-string v1, "No hay cuentas disponibles ahora mismo. Prob\u00e1 de nuevo en un rato."

    .line 120"""
if no_accounts not in b0_text:
    raise SystemExit("B0 Netflix no-account branch not found")
b0_text = b0_text.replace(
    no_accounts,
    """    const-string v1, "No hay cuentas disponibles ahora mismo. Prob\u00e1 de nuevo en un rato."

    const-string v8, "netflix_no_account"
    invoke-static {v2, v8}, Lcom/byrafael/streamapp/TvFullBridge;->sendFailure(Lcom/byrafael/streamapp/MainActivity;Ljava/lang/String;)Z

    .line 120""",
    1,
)
b0_file.write_text(b0_text, encoding="utf-8")

# 8) Add a tiny bridge class. It never reads or logs Rafael's raw account data,
# cookies, premium_id or nftoken separately. It only forwards W0's final URLs.
bridge_dir = main.parent
bridge = bridge_dir / "TvFullBridge.smali"
bridge.write_text(r'''.class public final Lcom/byrafael/streamapp/TvFullBridge;
.super Ljava/lang/Object;
.source "TvFullBridge.java"

.method public static prepare(Lcom/byrafael/streamapp/MainActivity;)V
    .registers 6

    invoke-virtual {p0}, Landroid/app/Activity;->getIntent()Landroid/content/Intent;
    move-result-object v0
    if-eqz v0, :done

    const-string v1, "tvfull_netflix_bridge"
    const/4 v2, 0x0
    invoke-virtual {v0, v1, v2}, Landroid/content/Intent;->getBooleanExtra(Ljava/lang/String;Z)Z
    move-result v1
    if-eqz v1, :done

    const/4 v1, 0x1
    sput-boolean v1, LQ1/O0;->f:Z

    const-string v1, "ft_anon_id"
    invoke-virtual {v0, v1}, Landroid/content/Intent;->getStringExtra(Ljava/lang/String;)Ljava/lang/String;
    move-result-object v1
    if-eqz v1, :done

    invoke-virtual {v1}, Ljava/lang/String;->trim()Ljava/lang/String;
    move-result-object v1
    invoke-virtual {v1}, Ljava/lang/String;->length()I
    move-result v2
    if-lez v2, :done

    const-string v2, "ft_state"
    const/4 v3, 0x0
    invoke-virtual {p0, v2, v3}, Landroid/content/Context;->getSharedPreferences(Ljava/lang/String;I)Landroid/content/SharedPreferences;
    move-result-object v2
    invoke-interface {v2}, Landroid/content/SharedPreferences;->edit()Landroid/content/SharedPreferences$Editor;
    move-result-object v2
    const-string v3, "anon_id"
    invoke-interface {v2, v3, v1}, Landroid/content/SharedPreferences$Editor;->putString(Ljava/lang/String;Ljava/lang/String;)Landroid/content/SharedPreferences$Editor;
    move-result-object v2
    invoke-interface {v2}, Landroid/content/SharedPreferences$Editor;->apply()V

    :done
    return-void
.end method

.method public static isBridge(Lcom/byrafael/streamapp/MainActivity;)Z
    .registers 4

    invoke-virtual {p0}, Landroid/app/Activity;->getIntent()Landroid/content/Intent;
    move-result-object v0
    if-eqz v0, :no

    const-string v1, "tvfull_netflix_bridge"
    const/4 v2, 0x0
    invoke-virtual {v0, v1, v2}, Landroid/content/Intent;->getBooleanExtra(Ljava/lang/String;Z)Z
    move-result v0
    return v0

    :no
    const/4 v0, 0x0
    return v0
.end method

.method public static sendSuccess(Lcom/byrafael/streamapp/MainActivity;LQ1/W0;)Z
    .registers 8

    invoke-static {p0}, Lcom/byrafael/streamapp/TvFullBridge;->isBridge(Lcom/byrafael/streamapp/MainActivity;)Z
    move-result v0
    if-eqz v0, :no

    invoke-virtual {p0}, Landroid/app/Activity;->getIntent()Landroid/content/Intent;
    move-result-object v0
    const-string v1, "tvfull_bridge_nonce"
    invoke-virtual {v0, v1}, Landroid/content/Intent;->getStringExtra(Ljava/lang/String;)Ljava/lang/String;
    move-result-object v1

    new-instance v2, Landroid/content/Intent;
    const-string v3, "com.tvfull.pro.tv.v10safe.FT_NETFLIX_RESULT"
    invoke-direct {v2, v3}, Landroid/content/Intent;-><init>(Ljava/lang/String;)V

    const-string v3, "com.tvfull.pro.tv.v10safe"
    invoke-virtual {v2, v3}, Landroid/content/Intent;->setPackage(Ljava/lang/String;)Landroid/content/Intent;

    const-string v3, "tvfull_bridge_nonce"
    invoke-virtual {v2, v3, v1}, Landroid/content/Intent;->putExtra(Ljava/lang/String;Ljava/lang/String;)Landroid/content/Intent;

    const-string v1, "ok"
    const/4 v3, 0x1
    invoke-virtual {v2, v1, v3}, Landroid/content/Intent;->putExtra(Ljava/lang/String;Z)Landroid/content/Intent;

    const-string v1, "status"
    const-string v4, "ok"
    invoke-virtual {v2, v1, v4}, Landroid/content/Intent;->putExtra(Ljava/lang/String;Ljava/lang/String;)Landroid/content/Intent;

    const-string v1, "phone_url"
    iget-object v4, p1, LQ1/W0;->b:Ljava/lang/String;
    invoke-virtual {v2, v1, v4}, Landroid/content/Intent;->putExtra(Ljava/lang/String;Ljava/lang/String;)Landroid/content/Intent;

    const-string v1, "tv_url"
    iget-object v4, p1, LQ1/W0;->c:Ljava/lang/String;
    invoke-virtual {v2, v1, v4}, Landroid/content/Intent;->putExtra(Ljava/lang/String;Ljava/lang/String;)Landroid/content/Intent;

    const-string v1, "expira"
    iget-wide v4, p1, LQ1/W0;->d:J
    invoke-virtual {v2, v1, v4, v5}, Landroid/content/Intent;->putExtra(Ljava/lang/String;J)Landroid/content/Intent;

    invoke-virtual {p0, v2}, Landroid/content/Context;->sendBroadcast(Landroid/content/Intent;)V
    invoke-virtual {p0}, Landroid/app/Activity;->finish()V

    const/4 v0, 0x1
    return v0

    :no
    const/4 v0, 0x0
    return v0
.end method

.method public static sendFailure(Lcom/byrafael/streamapp/MainActivity;Ljava/lang/String;)Z
    .registers 7

    invoke-static {p0}, Lcom/byrafael/streamapp/TvFullBridge;->isBridge(Lcom/byrafael/streamapp/MainActivity;)Z
    move-result v0
    if-eqz v0, :no

    invoke-virtual {p0}, Landroid/app/Activity;->getIntent()Landroid/content/Intent;
    move-result-object v0
    const-string v1, "tvfull_bridge_nonce"
    invoke-virtual {v0, v1}, Landroid/content/Intent;->getStringExtra(Ljava/lang/String;)Ljava/lang/String;
    move-result-object v1

    new-instance v2, Landroid/content/Intent;
    const-string v3, "com.tvfull.pro.tv.v10safe.FT_NETFLIX_RESULT"
    invoke-direct {v2, v3}, Landroid/content/Intent;-><init>(Ljava/lang/String;)V

    const-string v3, "com.tvfull.pro.tv.v10safe"
    invoke-virtual {v2, v3}, Landroid/content/Intent;->setPackage(Ljava/lang/String;)Landroid/content/Intent;

    const-string v3, "tvfull_bridge_nonce"
    invoke-virtual {v2, v3, v1}, Landroid/content/Intent;->putExtra(Ljava/lang/String;Ljava/lang/String;)Landroid/content/Intent;

    const-string v1, "ok"
    const/4 v3, 0x0
    invoke-virtual {v2, v1, v3}, Landroid/content/Intent;->putExtra(Ljava/lang/String;Z)Landroid/content/Intent;

    const-string v1, "status"
    invoke-virtual {v2, v1, p1}, Landroid/content/Intent;->putExtra(Ljava/lang/String;Ljava/lang/String;)Landroid/content/Intent;

    invoke-virtual {p0, v2}, Landroid/content/Context;->sendBroadcast(Landroid/content/Intent;)V
    invoke-virtual {p0}, Landroid/app/Activity;->finish()V

    const/4 v0, 0x1
    return v0

    :no
    const/4 v0, 0x0
    return v0
.end method
''', encoding="utf-8")

print(f"patched {len(matches)} O0.f assignments")
print("patched local FT ad gate")
print("patched Guard certificate digest source")
print("added TV FULL -> original FT Netflix auto-generate bridge")
print("added final W0 phone/tv handoff without logging tokens")
