package top.ozero.aghmanage.client

import android.content.Context
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

data class BlockedEntry(
    val time: Long,
    val domain: String,
    val qtype: String
)

/**
 * 手机端过滤的拦截日志。
 *
 * 内存中保留最近 [MAX] 条，延迟合并写入应用私有目录，避免每个查询都落盘。
 * 只记录被拦截的请求，不记录放行请求。
 */
object BlockLog {

    private const val MAX = 300
    private const val FILE = "client_block_log.tsv"

    private val lock = Any()
    private val entries = ArrayDeque<BlockedEntry>()
    private val io = Executors.newSingleThreadExecutor()
    private val flushScheduled = AtomicBoolean(false)
    private var loaded = false

    fun add(context: Context, domain: String, qtype: String) {
        ensureLoaded(context)
        synchronized(lock) {
            entries.addLast(BlockedEntry(System.currentTimeMillis(), domain, qtype))
            while (entries.size > MAX) entries.removeFirst()
        }
        scheduleFlush(context.applicationContext)
    }

    /** 返回按时间倒序排列的记录。 */
    fun snapshot(context: Context): List<BlockedEntry> {
        ensureLoaded(context)
        synchronized(lock) {
            return entries.reversed()
        }
    }

    fun clear(context: Context) {
        ensureLoaded(context)
        synchronized(lock) {
            entries.clear()
        }
        scheduleFlush(context.applicationContext)
    }

    private fun ensureLoaded(context: Context) {
        if (loaded) return
        synchronized(lock) {
            if (loaded) return
            loaded = true
            runCatching {
                File(context.filesDir, FILE).forEachLine { line ->
                    val parts = line.split('\t')
                    if (parts.size >= 3) {
                        val time = parts[0].toLongOrNull() ?: return@forEachLine
                        entries.addLast(BlockedEntry(time, parts[1], parts[2]))
                    }
                }
                while (entries.size > MAX) entries.removeFirst()
            }
        }
    }

    private fun scheduleFlush(context: Context) {
        if (!flushScheduled.compareAndSet(false, true)) return
        io.execute {
            // 合并短时间内的多次写入
            runCatching { Thread.sleep(1500) }
            flushScheduled.set(false)
            val copy = synchronized(lock) { entries.toList() }
            runCatching {
                File(context.filesDir, FILE).bufferedWriter().use { writer ->
                    copy.forEach {
                        writer.write("${it.time}\t${it.domain}\t${it.qtype}")
                        writer.newLine()
                    }
                }
            }
        }
    }
}
