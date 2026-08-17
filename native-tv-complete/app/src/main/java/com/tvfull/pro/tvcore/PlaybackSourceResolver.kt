package com.tvfull.pro.tvcore

class PlaybackSourceResolver {
    fun resolve(item: CatalogItem): PlaybackCandidate {
        val direct = item.directSource.trim()
        val stored = item.playbackUrl.trim()
        val selected = when {
            isHttp(direct) -> direct
            isHttp(stored) -> stored
            else -> error("El contenido no tiene una URL reproducible")
        }
        return PlaybackCandidate(
            sourceId = item.sourceId,
            section = item.section,
            itemId = item.itemId,
            url = selected,
            containerHint = item.extension,
            isDirectSource = isHttp(direct) && selected == direct
        )
    }

    private fun isHttp(value: String): Boolean = value.startsWith("http://", true) || value.startsWith("https://", true)
}
