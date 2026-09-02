from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PATH = ROOT / "lib/services/channel_logo_resolver_service.dart"
content = PATH.read_text(encoding="utf-8")

replacements = [
    ("    var completed = false;\n", ""),
    ("      completed = true;\n", ""),
    ("\n    if (!completed) return;\n", "\n"),
]
for old, new in replacements:
    if old not in content:
        raise SystemExit(f"Expected v25 generated block not found: {old!r}")
    content = content.replace(old, new, 1)

PATH.write_text(content, encoding="utf-8")
print("Fixed TV FULL PRO v25 generated resolver")
