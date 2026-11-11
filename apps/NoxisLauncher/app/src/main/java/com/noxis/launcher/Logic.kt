package com.noxis.launcher

import java.text.Normalizer
import java.util.Locale

/** Pure launcher logic (no Android types) – covered by unit tests. */
data class AppKey(val key: String, val label: String, val pkg: String)

object Logic {
    const val MAX_PINNED = 16   // home grid 4×4
    const val MAX_DOCK = 4

    fun normalize(s: String): String =
        Normalizer.normalize(s, Normalizer.Form.NFD).replace(Regex("\\p{Mn}+"), "").lowercase(Locale.ROOT).trim()

    private fun initials(label: String): String =
        label.split(Regex("[\\s\\-_.]+")).filter { it.isNotEmpty() }.joinToString("") { it.take(1) }.let(::normalize)

    /** Visible apps for a query: hidden apps out (unless shown), sorted by label, best matches first. */
    fun filter(apps: List<AppKey>, query: String, hidden: Set<String>, showHidden: Boolean): List<AppKey> {
        val q = normalize(query)
        val visible = apps.filter { showHidden || it.key !in hidden }
        val sorted = visible.sortedWith(compareBy({ normalize(it.label) }, { it.pkg }))
        if (q.isEmpty()) return sorted
        fun rank(a: AppKey): Int {
            val l = normalize(a.label)
            return when {
                l.startsWith(q) -> 0
                l.split(' ').any { it.startsWith(q) } -> 1
                initials(a.label).startsWith(q) -> 2
                l.contains(q) -> 3
                normalize(a.pkg).contains(q) -> 4
                else -> -1
            }
        }
        return sorted.map { it to rank(it) }.filter { it.second >= 0 }.sortedBy { it.second }.map { it.first }
    }

    /** Pin/unpin keeping order; at most MAX_PINNED apps on the home screen. */
    fun togglePin(pinned: List<String>, key: String, max: Int = MAX_PINNED): List<String> =
        if (key in pinned) pinned - key else (pinned + key).takeLast(max)

    /** First-run dock: default phone, messages, browser, camera (whatever exists, no duplicates). */
    fun defaultDock(candidates: List<String?>, existing: Set<String>): List<String> =
        candidates.filterNotNull().filter { it in existing }.distinct().take(MAX_DOCK)

    fun encode(list: List<String>): String = list.joinToString("|")
    fun decode(s: String?): List<String> = s?.split('|')?.filter { it.isNotBlank() } ?: emptyList()

    /** Drop pins/hidden entries of apps that no longer exist. */
    fun prune(keys: List<String>, existing: Set<String>): List<String> = keys.filter { it in existing }

    fun clock(hour: Int, minute: Int, h24: Boolean): String {
        val h = if (h24) hour else ((hour + 11) % 12) + 1
        return "%02d:%02d".format(h, minute)
    }
}

/** 5×7 dot-matrix glyphs for the home clock (1 = dot lit). */
object DotFont {
    val glyphs: Map<Char, List<String>> = mapOf(
        '0' to listOf("01110", "10001", "10011", "10101", "11001", "10001", "01110"),
        '1' to listOf("00100", "01100", "00100", "00100", "00100", "00100", "01110"),
        '2' to listOf("01110", "10001", "00001", "00010", "00100", "01000", "11111"),
        '3' to listOf("11110", "00001", "00001", "01110", "00001", "00001", "11110"),
        '4' to listOf("00010", "00110", "01010", "10010", "11111", "00010", "00010"),
        '5' to listOf("11111", "10000", "11110", "00001", "00001", "10001", "01110"),
        '6' to listOf("00110", "01000", "10000", "11110", "10001", "10001", "01110"),
        '7' to listOf("11111", "00001", "00010", "00100", "01000", "01000", "01000"),
        '8' to listOf("01110", "10001", "10001", "01110", "10001", "10001", "01110"),
        '9' to listOf("01110", "10001", "10001", "01111", "00001", "00010", "01100"),
        ':' to listOf("0", "0", "1", "0", "1", "0", "0"),
        ' ' to listOf("0", "0", "0", "0", "0", "0", "0"),
    )

    fun columns(text: String): Int = text.sumOf { (glyphs[it]?.first()?.length ?: 0) + 1 } - 1
}
