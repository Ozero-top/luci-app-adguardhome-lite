package top.ozero.aghmanage.client

import java.io.ByteArrayOutputStream
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test

class DnsPacketTest {

    @Test
    fun parsesQuestionNameAndType() {
        val payload = query("ads.example.com")
        val query = DnsPacket.parse(payload)

        assertNotNull(query)
        assertEquals("ads.example.com", query!!.name)
        assertEquals(1, query.type)
    }

    @Test
    fun buildsNxdomainKeepingQuestion() {
        val payload = query("tracker.example.net")
        val query = DnsPacket.parse(payload)!!
        val response = DnsPacket.errorResponse(query, DnsPacket.RCODE_NXDOMAIN)

        assertEquals(0x81, response[2].toInt() and 0xff)
        assertEquals(0x83, response[3].toInt() and 0xff)
        assertArrayEquals(
            payload.copyOfRange(12, payload.size),
            response.copyOfRange(12, response.size)
        )
    }

    @Test
    fun rejectsTruncatedPayload() {
        assertEquals(null, DnsPacket.parse(ByteArray(4)))
    }

    private fun query(name: String): ByteArray {
        val out = ByteArrayOutputStream()
        out.write(0x12)
        out.write(0x34)
        out.write(0x01)
        out.write(0x00)
        out.write(0x00)
        out.write(0x01)
        out.write(0x00)
        out.write(0x00)
        out.write(0x00)
        out.write(0x00)
        out.write(0x00)
        out.write(0x00)
        name.split('.').forEach { label ->
            out.write(label.length)
            out.write(label.toByteArray(Charsets.US_ASCII))
        }
        out.write(0x00)
        out.write(0x00)
        out.write(0x01)
        out.write(0x00)
        out.write(0x01)
        return out.toByteArray()
    }
}
