from pathlib import Path


def main() -> None:
    path = Path('lib/services/json_catalog_service.dart')
    text = path.read_text(encoding='utf-8')

    replacements = (
        ("final cleanPath = parsed.path.toLowerCase();", "final fullUrl = parsed.toString().toLowerCase();"),
        ("cleanPath.endsWith('.mpd')", "fullUrl.contains('.mpd')"),
        ("cleanPath.endsWith('.m3u8')", "fullUrl.contains('.m3u8')"),
    )

    for old, new in replacements:
        if old not in text:
            raise SystemExit(f'V45 source detection marker not found: {old}')
        text = text.replace(old, new, 1)

    path.write_text(text, encoding='utf-8')


if __name__ == '__main__':
    main()
