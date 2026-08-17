package com.tvfull.pro.tvcore

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import com.tvfull.pro.ContentSection

class TvCatalogDatabase(context: Context) : SQLiteOpenHelper(context, DB_NAME, null, DB_VERSION) {
    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """CREATE TABLE sources(
                source_id TEXT PRIMARY KEY,
                source_name TEXT NOT NULL,
                mode TEXT NOT NULL,
                server TEXT NOT NULL DEFAULT '',
                username TEXT NOT NULL DEFAULT '',
                m3u_url TEXT NOT NULL DEFAULT '',
                final_server TEXT NOT NULL DEFAULT '',
                updated_at INTEGER NOT NULL DEFAULT 0
            )"""
        )
        db.execSQL(
            """CREATE TABLE categories(
                source_id TEXT NOT NULL,
                section TEXT NOT NULL,
                category_id TEXT NOT NULL,
                name TEXT NOT NULL,
                sort_order INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY(source_id, section, category_id)
            )"""
        )
        db.execSQL(
            """CREATE TABLE items(
                source_id TEXT NOT NULL,
                section TEXT NOT NULL,
                item_id TEXT NOT NULL,
                category_id TEXT NOT NULL DEFAULT '',
                name TEXT NOT NULL,
                playback_url TEXT NOT NULL DEFAULT '',
                direct_source TEXT NOT NULL DEFAULT '',
                logo TEXT NOT NULL DEFAULT '',
                tvg_id TEXT NOT NULL DEFAULT '',
                extension TEXT NOT NULL DEFAULT '',
                series_id TEXT NOT NULL DEFAULT '',
                season_number INTEGER,
                episode_number INTEGER,
                metadata_json TEXT NOT NULL DEFAULT '{}',
                sort_order INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY(source_id, section, item_id)
            )"""
        )
        db.execSQL("CREATE INDEX idx_items_category ON items(source_id, section, category_id, sort_order)")
        db.execSQL("CREATE INDEX idx_items_series ON items(source_id, section, series_id, season_number, episode_number)")
        db.execSQL(
            """CREATE TABLE progress(
                source_id TEXT NOT NULL,
                section TEXT NOT NULL,
                item_id TEXT NOT NULL,
                position_ms INTEGER NOT NULL DEFAULT 0,
                duration_ms INTEGER NOT NULL DEFAULT 0,
                updated_at INTEGER NOT NULL,
                PRIMARY KEY(source_id, section, item_id)
            )"""
        )
        db.execSQL(
            """CREATE TABLE sync_state(
                source_id TEXT PRIMARY KEY,
                last_success_at INTEGER NOT NULL DEFAULT 0,
                last_error TEXT NOT NULL DEFAULT '',
                live_count INTEGER NOT NULL DEFAULT 0,
                movie_count INTEGER NOT NULL DEFAULT 0,
                series_count INTEGER NOT NULL DEFAULT 0,
                episode_count INTEGER NOT NULL DEFAULT 0
            )"""
        )
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        if (oldVersion < 1) onCreate(db)
    }

    fun replaceSection(sourceId: String, section: ContentSection, categories: List<CatalogCategory>, items: List<CatalogItem>) {
        writableDatabase.inTransaction {
            delete("categories", "source_id=? AND section=?", arrayOf(sourceId, section.name))
            delete("items", "source_id=? AND section=?", arrayOf(sourceId, section.name))
            categories.forEach { category -> insertCategory(this, category) }
            items.forEach { item -> insertItem(this, item) }
        }
    }

    fun upsertSource(source: ProvisionedSource, finalServer: String = "") {
        val values = ContentValues().apply {
            put("source_id", source.serviceId)
            put("source_name", source.serviceName)
            put("mode", source.config.mode.name)
            put("server", source.config.server)
            put("username", source.config.username)
            put("m3u_url", source.config.m3uUrl.ifBlank { source.config.fallbackM3uUrl })
            put("final_server", finalServer)
            put("updated_at", System.currentTimeMillis())
        }
        writableDatabase.insertWithOnConflict("sources", null, values, SQLiteDatabase.CONFLICT_REPLACE)
    }

    fun categories(sourceId: String, section: ContentSection): List<CatalogCategory> {
        val result = ArrayList<CatalogCategory>()
        readableDatabase.query(
            "categories",
            arrayOf("category_id", "name", "sort_order"),
            "source_id=? AND section=?",
            arrayOf(sourceId, section.name),
            null,
            null,
            "sort_order ASC, name COLLATE NOCASE ASC"
        ).use { c ->
            while (c.moveToNext()) {
                result += CatalogCategory(
                    sourceId = sourceId,
                    section = section,
                    categoryId = c.getString(0),
                    name = c.getString(1),
                    sortOrder = c.getInt(2)
                )
            }
        }
        return result
    }

    fun items(sourceId: String, section: ContentSection, categoryId: String? = null): List<CatalogItem> {
        val result = ArrayList<CatalogItem>()
        val selection = if (categoryId.isNullOrBlank()) "source_id=? AND section=?" else "source_id=? AND section=? AND category_id=?"
        val args = if (categoryId.isNullOrBlank()) arrayOf(sourceId, section.name) else arrayOf(sourceId, section.name, categoryId)
        readableDatabase.query(
            "items",
            ITEM_COLUMNS,
            selection,
            args,
            null,
            null,
            "sort_order ASC, name COLLATE NOCASE ASC"
        ).use { c ->
            while (c.moveToNext()) result += readItem(c, sourceId, section)
        }
        return result
    }

    fun seriesEpisodes(sourceId: String, seriesId: String): List<CatalogItem> {
        val result = ArrayList<CatalogItem>()
        readableDatabase.query(
            "items",
            ITEM_COLUMNS,
            "source_id=? AND section=? AND series_id=?",
            arrayOf(sourceId, ContentSection.SERIES.name, seriesId),
            null,
            null,
            "season_number ASC, episode_number ASC, sort_order ASC"
        ).use { c ->
            while (c.moveToNext()) result += readItem(c, sourceId, ContentSection.SERIES)
        }
        return result
    }

    fun saveProgress(sourceId: String, section: ContentSection, itemId: String, positionMs: Long, durationMs: Long) {
        val values = ContentValues().apply {
            put("source_id", sourceId)
            put("section", section.name)
            put("item_id", itemId)
            put("position_ms", positionMs.coerceAtLeast(0L))
            put("duration_ms", durationMs.coerceAtLeast(0L))
            put("updated_at", System.currentTimeMillis())
        }
        writableDatabase.insertWithOnConflict("progress", null, values, SQLiteDatabase.CONFLICT_REPLACE)
    }

    fun progress(sourceId: String, section: ContentSection, itemId: String): Long {
        readableDatabase.query(
            "progress",
            arrayOf("position_ms"),
            "source_id=? AND section=? AND item_id=?",
            arrayOf(sourceId, section.name, itemId),
            null,
            null,
            null,
            "1"
        ).use { c -> return if (c.moveToFirst()) c.getLong(0) else 0L }
    }

    fun saveSyncReport(report: SyncReport, error: String = "") {
        val values = ContentValues().apply {
            put("source_id", report.sourceId)
            put("last_success_at", if (error.isBlank()) System.currentTimeMillis() else 0L)
            put("last_error", error)
            put("live_count", report.liveCount)
            put("movie_count", report.movieCount)
            put("series_count", report.seriesCount)
            put("episode_count", report.episodeCount)
        }
        writableDatabase.insertWithOnConflict("sync_state", null, values, SQLiteDatabase.CONFLICT_REPLACE)
    }

    private fun insertCategory(db: SQLiteDatabase, category: CatalogCategory) {
        val v = ContentValues().apply {
            put("source_id", category.sourceId)
            put("section", category.section.name)
            put("category_id", category.categoryId)
            put("name", category.name)
            put("sort_order", category.sortOrder)
        }
        db.insertWithOnConflict("categories", null, v, SQLiteDatabase.CONFLICT_REPLACE)
    }

    private fun insertItem(db: SQLiteDatabase, item: CatalogItem) {
        val v = ContentValues().apply {
            put("source_id", item.sourceId)
            put("section", item.section.name)
            put("item_id", item.itemId)
            put("category_id", item.categoryId)
            put("name", item.name)
            put("playback_url", item.playbackUrl)
            put("direct_source", item.directSource)
            put("logo", item.logo)
            put("tvg_id", item.tvgId)
            put("extension", item.extension)
            put("series_id", item.seriesId)
            if (item.seasonNumber == null) putNull("season_number") else put("season_number", item.seasonNumber)
            if (item.episodeNumber == null) putNull("episode_number") else put("episode_number", item.episodeNumber)
            put("metadata_json", item.metadataJson)
            put("sort_order", item.sortOrder)
        }
        db.insertWithOnConflict("items", null, v, SQLiteDatabase.CONFLICT_REPLACE)
    }

    private fun readItem(c: android.database.Cursor, sourceId: String, section: ContentSection): CatalogItem {
        return CatalogItem(
            sourceId = sourceId,
            section = section,
            itemId = c.getString(0),
            categoryId = c.getString(1),
            name = c.getString(2),
            playbackUrl = c.getString(3),
            directSource = c.getString(4),
            logo = c.getString(5),
            tvgId = c.getString(6),
            extension = c.getString(7),
            seriesId = c.getString(8),
            seasonNumber = if (c.isNull(9)) null else c.getInt(9),
            episodeNumber = if (c.isNull(10)) null else c.getInt(10),
            metadataJson = c.getString(11),
            sortOrder = c.getInt(12)
        )
    }

    private inline fun SQLiteDatabase.inTransaction(block: SQLiteDatabase.() -> Unit) {
        beginTransaction()
        try {
            block()
            setTransactionSuccessful()
        } finally {
            endTransaction()
        }
    }

    companion object {
        private const val DB_NAME = "tvfull_catalog.db"
        private const val DB_VERSION = 1
        private val ITEM_COLUMNS = arrayOf(
            "item_id", "category_id", "name", "playback_url", "direct_source", "logo", "tvg_id",
            "extension", "series_id", "season_number", "episode_number", "metadata_json", "sort_order"
        )
    }
}
