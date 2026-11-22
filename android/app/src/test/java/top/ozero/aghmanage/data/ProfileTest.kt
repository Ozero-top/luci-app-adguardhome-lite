package top.ozero.aghmanage.data

import org.junit.Assert.assertEquals
import org.junit.Test

class ProfileTest {

    @Test
    fun defaultHttpPortIsOmitted() {
        assertEquals("http://192.168.1.1", Profile(host = "192.168.1.1").baseUrl)
    }

    @Test
    fun customPortIsIncluded() {
        assertEquals("http://192.168.100.254:8080", Profile(host = "192.168.100.254", port = 8080).baseUrl)
    }

    @Test
    fun httpsDefaultPortIsOmitted() {
        assertEquals("https://router.local", Profile(host = "router.local", port = 443, https = true).baseUrl)
    }

    @Test
    fun hostIsTrimmed() {
        assertEquals("http://10.0.0.1", Profile(host = " 10.0.0.1 ").baseUrl)
    }

    @Test
    fun apiBasePointsToPluginEndpoints() {
        assertEquals(
            "http://192.168.1.1/cgi-bin/luci/admin/services/adguardhome_lite",
            Profile(host = "192.168.1.1").apiBase
        )
    }
}
