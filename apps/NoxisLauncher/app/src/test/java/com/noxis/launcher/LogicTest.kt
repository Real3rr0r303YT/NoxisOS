package com.noxis.launcher

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class LogicTest {
    private val apps = listOf(
        AppKey("a/.C", "Calendar", "com.real3rr0r303yt.nothingcalendar"),
        AppKey("b/.C", "Calculator", "io.github.r3rr0r.rechner"),
        AppKey("c/.T", "Tor Browser", "org.torproject.torbrowser"),
        AppKey("d/.E", "Éditeur", "fr.example.editor"),
        AppKey("e/.M", "Mullvad VPN", "net.mullvad.mullvadvpn"),
    )

    @Test fun sortedByLabelWithoutQuery() =
        assertEquals(listOf("Calculator", "Calendar", "Éditeur", "Mullvad VPN", "Tor Browser"),
            Logic.filter(apps, "", emptySet(), false).map { it.label })

    @Test fun prefixBeatsContains() =
        assertEquals("Calendar", Logic.filter(apps, "cale", emptySet(), false).first().label)

    @Test fun wordStartMatches() =
        assertEquals(listOf("Mullvad VPN"), Logic.filter(apps, "vpn", emptySet(), false).map { it.label })

    @Test fun initialsMatch() =
        assertEquals("Tor Browser", Logic.filter(apps, "tb", emptySet(), false).first().label)

    @Test fun accentsIgnored() =
        assertEquals(listOf("Éditeur"), Logic.filter(apps, "edit", emptySet(), false).map { it.label })

    @Test fun packageNameSearch() =
        assertEquals(listOf("Calculator"), Logic.filter(apps, "rechner", emptySet(), false).map { it.label })

    @Test fun hiddenAppsFilteredUnlessShown() {
        assertTrue(Logic.filter(apps, "", setOf("c/.T"), false).none { it.key == "c/.T" })
        assertTrue(Logic.filter(apps, "", setOf("c/.T"), true).any { it.key == "c/.T" })
    }

    @Test fun pinToggleAndLimit() {
        var p = emptyList<String>()
        for (i in 1..20) p = Logic.togglePin(p, "k$i")
        assertEquals(Logic.MAX_PINNED, p.size)
        assertEquals("k20", p.last())
        assertEquals(p - "k10", Logic.togglePin(p, "k10"))
    }

    @Test fun dockLimitIsFour() {
        var d = emptyList<String>()
        for (i in 1..6) d = Logic.togglePin(d, "d$i", Logic.MAX_DOCK)
        assertEquals(listOf("d3", "d4", "d5", "d6"), d)
    }

    @Test fun defaultDockSkipsMissingAndDuplicates() =
        assertEquals(listOf("phone", "browser", "camera"),
            Logic.defaultDock(listOf("phone", null, "phone", "gone", "browser", "camera"), setOf("phone", "browser", "camera")))

    @Test fun encodeDecodeRoundTrip() {
        val l = listOf("com.a/.Main", "com.b/.X")
        assertEquals(l, Logic.decode(Logic.encode(l)))
        assertEquals(emptyList<String>(), Logic.decode(null))
        assertEquals(emptyList<String>(), Logic.decode(""))
    }

    @Test fun pruneRemovesUninstalled() =
        assertEquals(listOf("a"), Logic.prune(listOf("a", "gone"), setOf("a", "b")))

    @Test fun clockFormats() {
        assertEquals("09:05", Logic.clock(9, 5, true))
        assertEquals("13:42", Logic.clock(13, 42, true))
        assertEquals("01:42", Logic.clock(13, 42, false))
        assertEquals("12:00", Logic.clock(0, 0, false))
        assertEquals("12:30", Logic.clock(12, 30, false))
    }

    @Test fun dotFontComplete() {
        for (c in "0123456789: ") {
            val g = DotFont.glyphs.getValue(c)
            assertEquals(7, g.size)
            assertTrue(g.all { row -> row.length == g[0].length && row.all { it == '0' || it == '1' } })
        }
        assertEquals(5 + 1 + 5 + 1 + 1 + 1 + 5 + 1 + 5, DotFont.columns("12:34"))
    }
}
