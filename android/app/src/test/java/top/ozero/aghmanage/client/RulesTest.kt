package top.ozero.aghmanage.client

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RulesTest {

    @Test
    fun parsesAdblockHostsAndPlainLines() {
        val blocked = HashSet<String>()
        val allowed = HashSet<String>()

        RuleParser.parseLine("||ads.example.com^", blocked, allowed)
        RuleParser.parseLine("0.0.0.0 tracker.example.net # comment", blocked, allowed)
        RuleParser.parseLine("plain.example.org", blocked, allowed)
        RuleParser.parseLine("@@||good.example.com^", blocked, allowed)
        RuleParser.parseLine("! comment", blocked, allowed)
        RuleParser.parseLine("[Adblock Plus 2.0]", blocked, allowed)

        assertTrue(blocked.contains("ads.example.com"))
        assertTrue(blocked.contains("tracker.example.net"))
        assertTrue(blocked.contains("plain.example.org"))
        assertTrue(allowed.contains("good.example.com"))
        assertFalse(blocked.contains("good.example.com"))
    }

    @Test
    fun matchesDomainAndSubdomains() {
        val blocked = setOf("ads.example.com", "tracker.example.net")
        val matcher = DomainMatcher.build(blocked, emptySet())

        assertTrue(matcher.isBlocked("ads.example.com"))
        assertTrue(matcher.isBlocked("sub.ads.example.com"))
        assertTrue(matcher.isBlocked("TRACKER.EXAMPLE.NET."))
        assertFalse(matcher.isBlocked("notads.example.com"))
        assertFalse(matcher.isBlocked("example.com"))
    }

    @Test
    fun allowlistOverridesBlockedDomain() {
        val matcher = DomainMatcher.build(
            blocked = setOf("ads.example.com", "other.net"),
            allowed = setOf("example.com")
        )

        assertFalse(matcher.isBlocked("ads.example.com"))
        assertTrue(matcher.isBlocked("other.net"))
    }

    @Test
    fun parsesAllowFileAsAllowedDomains() {
        val allowed = HashSet<String>()
        RuleParser.parseAllowLine("good.example.com", allowed)
        RuleParser.parseAllowLine("@@||cdn.example.net^", allowed)

        assertTrue(allowed.contains("good.example.com"))
        assertTrue(allowed.contains("cdn.example.net"))
    }

    @Test
    fun ignoresNonDomainRules() {
        assertFalse(RuleParser.extract("||") != null)
        assertFalse(RuleParser.extract("/banner/*/img^") != null)
        assertFalse(RuleParser.extract("##.ad-banner") != null)
    }
}
