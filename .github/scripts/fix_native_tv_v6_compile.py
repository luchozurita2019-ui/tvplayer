from pathlib import Path

ROOT = Path('native-tv-complete/app/src/main/java/com/tvfull/pro')
CAT = ROOT / 'CatalogRepository.kt'
PROV = ROOT / 'ProvisioningActivity.kt'

# 1) Keep backward compatibility for MainActivity and any older caller that still
# passes only a seriesId. TvHomeActivity uses the richer ContentItem overload.
cat = CAT.read_text(encoding='utf-8')
marker = '    fun loadShortEpg(streamId: String): List<EpgEntry> {'
overload = '''    fun loadSeriesEpisodes(seriesId: String): List<ContentItem> {
        if (seriesId.isBlank()) return emptyList()
        return loadSeriesEpisodes(
            ContentItem(
                id = seriesId,
                name = "",
                section = ContentSection.SERIES,
                seriesId = seriesId
            )
        )
    }

'''
if 'fun loadSeriesEpisodes(seriesId: String): List<ContentItem>' not in cat:
    if marker not in cat:
        raise SystemExit('Catalog loadShortEpg marker missing')
    cat = cat.replace(marker, overload + marker, 1)
CAT.write_text(cat, encoding='utf-8')

# 2) re.sub in the V6 generator interpreted \\n in the replacement. Normalize the
# generated Kotlin back to an escaped newline inside one valid string literal.
prov = PROV.read_text(encoding='utf-8')
broken = '''            text = "Vinculá este dispositivo desde el panel de TV FULL.
Las listas y servicios se cargarán automáticamente."
'''
fixed = '            text = "Vinculá este dispositivo desde el panel de TV FULL.\\nLas listas y servicios se cargarán automáticamente."\n'
if broken in prov:
    prov = prov.replace(broken, fixed, 1)
elif 'Vinculá este dispositivo desde el panel de TV FULL.\\nLas listas y servicios se cargarán automáticamente.' not in prov:
    raise SystemExit('Provisioning activation message marker missing')
PROV.write_text(prov, encoding='utf-8')

print('Native TV V6 Kotlin compatibility fixes applied successfully.')
