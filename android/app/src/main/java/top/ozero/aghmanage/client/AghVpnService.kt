package top.ozero.aghmanage.client

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import androidx.core.app.NotificationCompat
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicLong
import top.ozero.aghmanage.MainActivity
import top.ozero.aghmanage.R

/**
 * 仅接管 DNS 的手机 VPN：系统把 DNS 查询送到 10.111.222.1，
 * 这里读取 tun 内的 UDP:53 报文，命中规则则直接返回 NXDOMAIN，
 * 其余转发到上游 DNS，不代理其它任何流量。
 */
class AghVpnService : VpnService() {

    private lateinit var prefs: ClientPrefs
    private val blocked = AtomicLong(0)
    private val handler = Handler(Looper.getMainLooper())
    private var executor = Executors.newFixedThreadPool(4)
    private val writeLock = Any()

    private var tun: ParcelFileDescriptor? = null
    private var input: FileInputStream? = null
    private var output: FileOutputStream? = null
    private var reader: Thread? = null
    private var lastUiUpdate = 0L
    private var cleaned = false

    private val ticker = object : Runnable {
        override fun run() {
            ClientState.update { it.copy(pausedUntil = prefs.pausedUntil) }
            updateNotification()
            if (prefs.pausedUntil > System.currentTimeMillis()) {
                handler.postDelayed(this, 1000)
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        prefs = ClientPrefs(this)
        blocked.set(prefs.blockedTotal)
        createChannel()
        ClientState.update {
            it.copy(
                blocked = prefs.blockedTotal,
                pausedUntil = prefs.pausedUntil
            )
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            cleanup()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }

        startForeground(NOTIF_ID, buildNotification())

        when (intent?.action) {
            ACTION_RESTART -> restartTunnel()
            ACTION_TOGGLE_PAUSE -> {
                startVpn()
                if (tun != null || reader != null) togglePause()
            }
            else -> startVpn()
        }
        return START_STICKY
    }

    private fun startVpn(reloadRules: Boolean = true) {
        if (reader != null) return

        reader = Thread {
            if (reloadRules) {
                RuleStore.load(this)
                ClientState.update { it.copy(rules = RuleStore.count) }
            }

            val builder = Builder()
                .setSession("AGHTools 客户端过滤")
                .setMtu(1500)
                .addAddress("10.111.222.2", 24)
                .addDnsServer("10.111.222.1")
                .addRoute("10.111.222.0", 24)
                .setBlocking(true)
            applySplitTunnel(builder)

            val fd = try {
                builder.establish()
            } catch (e: Exception) {
                null
            }

            if (fd == null) {
                prefs.enabled = false
                ClientState.update { it.copy(running = false) }
                handler.post {
                    (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).cancel(NOTIF_ID)
                    stopSelf()
                }
            } else {
                tun = fd
                input = FileInputStream(fd.fileDescriptor)
                output = FileOutputStream(fd.fileDescriptor)
                prefs.enabled = true
                ClientState.update {
                    it.copy(
                        running = true,
                        rules = RuleStore.count,
                        blocked = blocked.get(),
                        pausedUntil = prefs.pausedUntil
                    )
                }
                updateNotification()
                readLoop()
            }
        }.apply {
            name = "agh-vpn-dns"
            start()
        }
    }

    /** 应用分流：仅选中应用走 VPN，或让选中的应用直连。 */
    private fun applySplitTunnel(builder: Builder) {
        val packages = prefs.selectedApps
        if (packages.isEmpty()) return
        when (prefs.splitMode) {
            ClientPrefs.SPLIT_ALLOW -> packages.forEach {
                runCatching { builder.addAllowedApplication(it) }
            }
            ClientPrefs.SPLIT_DENY -> packages.forEach {
                runCatching { builder.addDisallowedApplication(it) }
            }
        }
    }

    private fun restartTunnel() {
        if (reader == null && tun == null) {
            startVpn()
            return
        }
        runCatching { tun?.close() }
        tun = null
        runCatching { input?.close() }
        runCatching { output?.close() }
        input = null
        output = null
        reader?.interrupt()
        reader = null
        executor.shutdownNow()
        executor = Executors.newFixedThreadPool(4)
        ClientState.update { it.copy(running = false) }
        handler.postDelayed({ startVpn(reloadRules = false) }, 300)
    }

    private fun readLoop() {
        val stream = input ?: return
        val buffer = ByteArray(32 * 1024)
        while (!Thread.currentThread().isInterrupted) {
            val read = try {
                stream.read(buffer)
            } catch (e: Exception) {
                break
            }
            if (read <= 0) break
            val packet = buffer.copyOf(read)
            try {
                executor.execute { handlePacket(packet) }
            } catch (e: Exception) {
                break
            }
        }
    }

    private fun handlePacket(packet: ByteArray) {
        if (packet.size < 28) return
        if (((packet[0].toInt() ushr 4) and 0x0f) != 4) return
        val ihl = (packet[0].toInt() and 0x0f) * 4
        if (ihl < 20 || packet.size < ihl + 8) return
        if ((packet[9].toInt() and 0xff) != 17) return

        val srcPort = u16(packet, ihl)
        val dstPort = u16(packet, ihl + 2)
        if (dstPort != 53) return

        val udpLength = u16(packet, ihl + 4)
        if (udpLength < 8 || ihl + udpLength > packet.size) return

        val payload = packet.copyOfRange(ihl + 8, ihl + udpLength)
        val query = DnsPacket.parse(payload) ?: return
        val response = resolve(query)
        val out = buildResponse(packet, srcPort, dstPort, response)

        val stream = output ?: return
        synchronized(writeLock) {
            runCatching { stream.write(out) }
        }
    }

    private fun resolve(query: DnsPacket.Query): ByteArray {
        val paused = prefs.pausedUntil > System.currentTimeMillis()
        if (!paused && RuleStore.isBlocked(query.name)) {
            countBlocked()
            BlockLog.add(applicationContext, query.name, qtypeName(query.type))
            return DnsPacket.errorResponse(query, DnsPacket.RCODE_NXDOMAIN)
        }

        for (server in upstreamServers()) {
            forward(query.payload, server)?.let { return it }
        }
        return DnsPacket.errorResponse(query, DnsPacket.RCODE_SERVFAIL)
    }

    private fun forward(payload: ByteArray, server: String): ByteArray? = try {
        DatagramSocket().use { socket ->
            if (!protect(socket)) return null
            socket.soTimeout = 1800
            val address = InetAddress.getByName(server)
            socket.send(DatagramPacket(payload, payload.size, address, 53))
            val buffer = ByteArray(4096)
            val received = DatagramPacket(buffer, buffer.size)
            socket.receive(received)
            buffer.copyOfRange(0, received.length)
        }
    } catch (e: Exception) {
        null
    }

    private fun upstreamServers(): List<String> {
        val servers = prefs.upstreamServers()
        return if (servers.isEmpty()) listOf("223.5.5.5", "119.29.29.29") else servers
    }

    private fun buildResponse(
        request: ByteArray,
        requestSrcPort: Int,
        requestDstPort: Int,
        payload: ByteArray
    ): ByteArray {
        val total = 20 + 8 + payload.size
        val out = ByteArray(total)
        out[0] = 0x45
        out[2] = (total ushr 8).toByte()
        out[3] = total.toByte()
        out[6] = 0x40
        out[8] = 64
        out[9] = 17

        // 源地址 = 请求目的地址，目的地址 = 请求源地址
        System.arraycopy(request, 16, out, 12, 4)
        System.arraycopy(request, 12, out, 16, 4)

        var sum = 0
        var i = 0
        while (i < 20) {
            sum += ((out[i].toInt() and 0xff) shl 8) or (out[i + 1].toInt() and 0xff)
            i += 2
        }
        while (sum shr 16 != 0) sum = (sum and 0xffff) + (sum shr 16)
        val checksum = sum.inv() and 0xffff
        out[10] = (checksum ushr 8).toByte()
        out[11] = checksum.toByte()

        out[20] = (requestDstPort ushr 8).toByte()
        out[21] = requestDstPort.toByte()
        out[22] = (requestSrcPort ushr 8).toByte()
        out[23] = requestSrcPort.toByte()
        val udpLength = 8 + payload.size
        out[24] = (udpLength ushr 8).toByte()
        out[25] = udpLength.toByte()
        System.arraycopy(payload, 0, out, 28, payload.size)
        return out
    }

    private fun countBlocked() {
        val value = blocked.incrementAndGet()
        val now = System.currentTimeMillis()
        if (now - lastUiUpdate < 1000) return
        lastUiUpdate = now
        handler.post {
            ClientState.update { it.copy(blocked = value) }
            updateNotification()
        }
    }

    private fun togglePause() {
        val now = System.currentTimeMillis()
        prefs.pausedUntil = if (prefs.pausedUntil > now) 0L else now + PAUSE_MS
        ClientState.update { it.copy(pausedUntil = prefs.pausedUntil) }
        handler.removeCallbacks(ticker)
        if (prefs.pausedUntil > now) handler.postDelayed(ticker, 1000)
        updateNotification()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "客户端过滤",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "客户端 DNS 过滤运行状态"
            setShowBadge(false)
        }
        (getSystemService(NOTIFICATION_SERVICE) as NotificationManager)
            .createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val now = System.currentTimeMillis()
        val paused = prefs.pausedUntil > now
        val text = if (paused) {
            val left = ((prefs.pausedUntil - now) / 1000).coerceAtLeast(0)
            "已暂停，${left} 秒后恢复"
        } else {
            "已拦截 ${blocked.get()} 个请求 · 规则 ${RuleStore.count} 条"
        }

        val pauseIntent = PendingIntent.getService(
            this,
            10,
            Intent(this, AghVpnService::class.java).setAction(ACTION_TOGGLE_PAUSE),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val stopIntent = PendingIntent.getService(
            this,
            11,
            Intent(this, AghVpnService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val contentIntent = PendingIntent.getActivity(
            this,
            12,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_agh)
            .setContentTitle("AGHTools 客户端过滤")
            .setContentText(text)
            .setContentIntent(contentIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .addAction(0, if (paused) "继续过滤" else "暂停 30 秒", pauseIntent)
            .addAction(0, "停止", stopIntent)
            .build()
    }

    private fun updateNotification() {
        if (tun == null) return
        runCatching {
            (getSystemService(NOTIFICATION_SERVICE) as NotificationManager)
                .notify(NOTIF_ID, buildNotification())
        }
    }

    private fun cleanup() {
        if (cleaned) return
        cleaned = true
        handler.removeCallbacksAndMessages(null)
        runCatching { tun?.close() }
        tun = null
        runCatching { input?.close() }
        runCatching { output?.close() }
        input = null
        output = null
        reader?.interrupt()
        reader = null
        executor.shutdownNow()
        prefs.blockedTotal = blocked.get()
        prefs.enabled = false
        ClientState.update { it.copy(running = false, blocked = blocked.get()) }
    }

    override fun onRevoke() {
        cleanup()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
        super.onRevoke()
    }

    override fun onDestroy() {
        cleanup()
        super.onDestroy()
    }

    private fun u16(bytes: ByteArray, offset: Int): Int =
        ((bytes[offset].toInt() and 0xff) shl 8) or (bytes[offset + 1].toInt() and 0xff)

    private fun qtypeName(type: Int): String = when (type) {
        1 -> "A"
        2 -> "NS"
        5 -> "CNAME"
        6 -> "SOA"
        12 -> "PTR"
        15 -> "MX"
        16 -> "TXT"
        28 -> "AAAA"
        33 -> "SRV"
        43 -> "DS"
        46 -> "RRSIG"
        64 -> "SVCB"
        65 -> "HTTPS"
        else -> "TYPE$type"
    }

    companion object {
        const val ACTION_START = "top.ozero.aghmanage.action.START"
        const val ACTION_STOP = "top.ozero.aghmanage.action.STOP"
        const val ACTION_TOGGLE_PAUSE = "top.ozero.aghmanage.action.TOGGLE_PAUSE"
        const val ACTION_RESTART = "top.ozero.aghmanage.action.RESTART"

        const val PAUSE_MS = 30_000L
        private const val NOTIF_ID = 1001
        private const val CHANNEL_ID = "agh_client"
    }
}
