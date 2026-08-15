package com.tvfull.pro

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.widget.ImageView
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.Collections
import java.util.WeakHashMap
import java.util.concurrent.Executors
import java.util.concurrent.Future

/**
 * Small image loader for TV lists/grids.
 *
 * Design goals:
 * - no third-party image dependency
 * - only starts a network request when a holder is attached/visible
 * - cancels work when a recycled ImageView leaves the screen
 * - keeps a very small memory cache
 * - keeps compressed source bytes in the app cache so logos/posters are not downloaded again
 */
class LiteImageLoader(context: Context) {
    private val appContext = context.applicationContext
    private val executor = Executors.newFixedThreadPool(2)
    private val memory = object : android.util.LruCache<String, Bitmap>(8 * 1024) {
        override fun sizeOf(key: String, value: Bitmap): Int = value.byteCount / 1024
    }
    private val running = Collections.synchronizedMap(WeakHashMap<ImageView, Future<*>>())
    private val diskDir = File(appContext.cacheDir, "tvfull_images").apply { mkdirs() }

    fun load(view: ImageView, url: String, targetWidth: Int, targetHeight: Int) {
        cancel(view)
        val clean = url.trim()
        view.tag = clean
        if (clean.isBlank()) {
            view.setImageDrawable(null)
            return
        }

        val key = "${clean}@${targetWidth}x${targetHeight}"
        memory.get(key)?.let {
            view.setImageBitmap(it)
            return
        }

        view.setImageDrawable(null)
        val future = executor.submit {
            runCatching {
                val source = cachedSource(clean)
                val bmp = decodeSampled(source, targetWidth, targetHeight) ?: return@runCatching
                memory.put(key, bmp)
                view.post {
                    if (view.tag == clean) view.setImageBitmap(bmp)
                }
            }
        }
        running[view] = future
    }

    fun cancel(view: ImageView) {
        running.remove(view)?.cancel(true)
    }

    fun shutdown() {
        executor.shutdownNow()
        memory.evictAll()
    }

    private fun cachedSource(url: String): File {
        val file = File(diskDir, sha256(url))
        if (file.exists() && file.length() > 0L) return file

        val conn = (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = 5_000
            readTimeout = 7_000
            instanceFollowRedirects = true
            setRequestProperty("User-Agent", "TV-FULL-PRO/1.3 AndroidTV")
            setRequestProperty("Accept", "image/*,*/*;q=0.5")
        }

        try {
            if (conn.responseCode !in 200..299) throw IllegalStateException("image_http_${conn.responseCode}")
            val output = ByteArrayOutputStream()
            val buffer = ByteArray(16 * 1024)
            var total = 0
            conn.inputStream.use { input ->
                while (true) {
                    if (Thread.currentThread().isInterrupted) throw InterruptedException()
                    val n = input.read(buffer)
                    if (n <= 0) break
                    total += n
                    if (total > 3 * 1024 * 1024) throw IllegalStateException("image_too_large")
                    output.write(buffer, 0, n)
                }
            }
            val bytes = output.toByteArray()
            val tmp = File(diskDir, "${file.name}.tmp")
            FileOutputStream(tmp).use { it.write(bytes) }
            if (!tmp.renameTo(file)) {
                FileOutputStream(file).use { it.write(bytes) }
                tmp.delete()
            }
            trimDiskCache()
            return file
        } finally {
            conn.disconnect()
        }
    }

    private fun decodeSampled(file: File, targetWidth: Int, targetHeight: Int): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.absolutePath, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null

        var sample = 1
        val safeW = targetWidth.coerceAtLeast(1)
        val safeH = targetHeight.coerceAtLeast(1)
        while (bounds.outWidth / (sample * 2) >= safeW && bounds.outHeight / (sample * 2) >= safeH) {
            sample *= 2
        }
        val opts = BitmapFactory.Options().apply {
            inSampleSize = sample
            inPreferredConfig = Bitmap.Config.RGB_565
        }
        return BitmapFactory.decodeFile(file.absolutePath, opts)
    }

    private fun trimDiskCache() {
        val files = diskDir.listFiles()?.filter { it.isFile && !it.name.endsWith(".tmp") } ?: return
        var total = files.sumOf { it.length() }
        val max = 48L * 1024L * 1024L
        if (total <= max) return
        for (file in files.sortedBy { it.lastModified() }) {
            total -= file.length()
            file.delete()
            if (total <= max) break
        }
    }

    private fun sha256(value: String): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(value.toByteArray(Charsets.UTF_8))
        return digest.joinToString("") { "%02x".format(it) }
    }
}
