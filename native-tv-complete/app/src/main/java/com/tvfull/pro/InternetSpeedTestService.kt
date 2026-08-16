package com.tvfull.pro

import java.net.HttpURLConnection
import java.net.URL
import kotlin.math.max

data class InternetSpeedTestResult(
    val downloadMbps: Double,
    val latencyMs: Long,
    val bytesTransferred: Long,
    val transferDurationMs: Long
)

object InternetSpeedTestService {
    private const val ENDPOINT = "https://speed.cloudflare.com/__down"
    private const val UA = "TV FULL Internet Test/1.0"

    fun run(): InternetSpeedTestResult {
        val latencies = mutableListOf<Long>()
        repeat(3) { index ->
            val sample = download(1024, 6_000, "latency-$index")
            latencies += sample.elapsedMs.coerceIn(1, 60_000)
        }
        latencies.sort()
        val latency = latencies[latencies.size / 2]

        download(256 * 1024, 12_000, "warmup")

        val samples = listOf(
            download(2 * 1024 * 1024, 15_000, "download-2m"),
            download(8 * 1024 * 1024, 15_000, "download-8m")
        ).filter { it.bytes > 0 && it.elapsedMs > 0 }

        if (samples.isEmpty()) throw IllegalStateException("No se recibieron datos suficientes")

        var best = 0.0
        var totalBytes = 0L
        var totalDuration = 0L
        for (sample in samples) {
            val seconds = sample.elapsedMs / 1000.0
            val mbps = (sample.bytes * 8.0) / seconds / 1_000_000.0
            best = max(best, mbps)
            totalBytes += sample.bytes
            totalDuration += sample.elapsedMs
        }
        if (best <= 0.0) throw IllegalStateException("No se pudo calcular la velocidad")

        return InternetSpeedTestResult(best, latency, totalBytes, totalDuration)
    }

    private fun download(bytes: Int, timeoutMs: Int, sampleId: String): Sample {
        val url = URL("$ENDPOINT?bytes=$bytes&tvfull=${System.nanoTime()}-$sampleId")
        val conn = (url.openConnection() as HttpURLConnection).apply {
            connectTimeout = timeoutMs.coerceAtMost(8_000)
            readTimeout = timeoutMs
            instanceFollowRedirects = true
            useCaches = false
            setRequestProperty("User-Agent", UA)
            setRequestProperty("Accept", "application/octet-stream,*/*")
            setRequestProperty("Cache-Control", "no-cache")
        }
        val start = System.nanoTime()
        try {
            val status = conn.responseCode
            if (status !in 200..299) throw IllegalStateException("Test HTTP $status")
            var total = 0L
            val buffer = ByteArray(32 * 1024)
            conn.inputStream.use { input ->
                while (true) {
                    val n = input.read(buffer)
                    if (n <= 0) break
                    total += n
                }
            }
            val elapsed = ((System.nanoTime() - start) / 1_000_000L).coerceAtLeast(1L)
            return Sample(total, elapsed)
        } finally {
            conn.disconnect()
        }
    }

    private data class Sample(val bytes: Long, val elapsedMs: Long)
}
