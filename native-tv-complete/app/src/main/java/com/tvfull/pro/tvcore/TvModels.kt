package com.tvfull.pro.tvcore

import com.tvfull.pro.ContentSection
import com.tvfull.pro.SourceConfig

data class ProvisionedSource(
    val serviceId: String,
    val serviceName: String,
    val config: SourceConfig,
    val expiresAt: String = ""
)

data class CatalogCategory(
    val sourceId: String,
    val section: ContentSection,
    val categoryId: String,
    val name: String,
    val sortOrder: Int = 0
)

data class CatalogItem(
    val sourceId: String,
    val section: ContentSection,
    val itemId: String,
    val categoryId: String = "",
    val name: String,
    val playbackUrl: String = "",
    val directSource: String = "",
    val logo: String = "",
    val tvgId: String = "",
    val extension: String = "",
    val seriesId: String = "",
    val seasonNumber: Int? = null,
    val episodeNumber: Int? = null,
    val metadataJson: String = "{}",
    val sortOrder: Int = 0
)

data class PlaybackCandidate(
    val sourceId: String,
    val section: ContentSection,
    val itemId: String,
    val url: String,
    val containerHint: String = "",
    val isDirectSource: Boolean = false
)

enum class DecoderMode { AUTO, HARDWARE, SOFTWARE }

data class PlaybackPolicy(
    val decoderMode: DecoderMode = DecoderMode.AUTO,
    val liveBufferBytes: Long = 30L * 1024L * 1024L,
    val vodBufferBytes: Long = 50L * 1024L * 1024L,
    val reconnectEnabled: Boolean = true,
    val frameDrop: Int = 1
)

data class SyncReport(
    val sourceId: String,
    val liveCount: Int = 0,
    val movieCount: Int = 0,
    val seriesCount: Int = 0,
    val episodeCount: Int = 0,
    val warnings: List<String> = emptyList(),
    val finalServer: String = ""
)
