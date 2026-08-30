from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def fix_detail(path: Path, start_marker: str, end_marker: str, label: str) -> None:
    text = path.read_text(encoding="utf-8")
    start = text.find(start_marker)
    end = text.find(end_marker, start)
    if start < 0 or end < 0:
        raise RuntimeError(f"No se encontró región {label}")
    region = text[start:end]
    if "body: TvFullPremiumBackground(" not in region:
        raise RuntimeError(f"No se aplicó fondo premium en {label}")

    fixed_tail = "        ),\n      ),\n      ),\n    );\n  }\n\n  void _play"
    if fixed_tail not in region:
        old_tail = "        ),\n      ),\n    );\n  }\n\n  void _play"
        if old_tail not in region:
            raise RuntimeError(f"No se encontró cierre esperado en {label}")
        region = region.replace(old_tail, fixed_tail, 1)
        text = text[:start] + region + text[end:]

    path.write_text(text, encoding="utf-8")


fix_detail(
    ROOT / "lib/screens/xtream_movies_screen.dart",
    "class _MovieDetailScreen extends StatelessWidget {",
    "class _MovieCard extends StatefulWidget {",
    "MovieDetail",
)
fix_detail(
    ROOT / "lib/screens/xtream_series_screen.dart",
    "class _SeriesDetailScreenState extends State<_SeriesDetailScreen> {",
    "class _SeriesCard extends StatefulWidget {",
    "SeriesDetail",
)

source = ROOT / "lib/screens/source_content_screen.dart"
text = source.read_text(encoding="utf-8")
text = text.replace("Colors.white45", "Color(0x73FFFFFF)")
source.write_text(text, encoding="utf-8")

print("Cierres y colores premium corregidos")
