package top.ozero.aghmanage.client

/** 极简 DNS 报文解析 / 构造，只处理查询问题段与错误响应。 */
object DnsPacket {

    const val RCODE_SERVFAIL = 2
    const val RCODE_NXDOMAIN = 3

    class Query(
        val id: Int,
        val flags: Int,
        val name: String,
        val type: Int,
        val questionEnd: Int,
        val payload: ByteArray
    )

    fun parse(payload: ByteArray): Query? {
        if (payload.size < 12) return null
        val questions = u16(payload, 4)
        if (questions < 1) return null

        var pos = 12
        val name = StringBuilder()
        var labels = 0
        while (pos < payload.size) {
            val length = payload[pos].toInt() and 0xff
            pos++
            if (length == 0) break
            if (length and 0xc0 != 0) return null
            if (length > 63 || pos + length > payload.size || labels++ > 32) return null
            if (name.isNotEmpty()) name.append('.')
            name.append(String(payload, pos, length, Charsets.US_ASCII))
            pos += length
        }
        if (pos + 4 > payload.size) return null

        val type = u16(payload, pos)
        return Query(
            id = u16(payload, 0),
            flags = u16(payload, 2),
            name = name.toString(),
            type = type,
            questionEnd = pos + 4,
            payload = payload
        )
    }

    /** 生成 NXDOMAIN / SERVFAIL 响应，保留原问题段。 */
    fun errorResponse(query: Query, rcode: Int): ByteArray {
        val flags = (query.flags and 0x0100) or 0x8080 or (rcode and 0x0f)
        val out = ByteArray(query.questionEnd)
        System.arraycopy(query.payload, 0, out, 0, 12)
        out[2] = (flags ushr 8).toByte()
        out[3] = flags.toByte()
        for (i in 6..11) out[i] = 0
        System.arraycopy(query.payload, 12, out, 12, query.questionEnd - 12)
        return out
    }

    private fun u16(bytes: ByteArray, offset: Int): Int =
        ((bytes[offset].toInt() and 0xff) shl 8) or (bytes[offset + 1].toInt() and 0xff)
}
