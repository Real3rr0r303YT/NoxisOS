package com.noxis.launcher

import java.text.Normalizer
import java.util.Locale

/** Pure launcher logic (no Android types) – covered by unit tests. */
data class AppKey(val key: String, val label: String, val pkg: String)

object Logic {
    const val MAX_PINNED = 8    // home grid: 2 rows × 4, like Noxis Shell on Linux
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

    /** Tile monogram: first letter or digit of the label, upper case ("?" if none). */
    fun monogram(label: String): String =
        label.firstOrNull { it.isLetterOrDigit() }?.uppercaseChar()?.toString() ?: "?"

    /** Drawer sections: (header letter, apps) – letters A–Z, everything else under "#". */
    fun <T> sections(items: List<T>, label: (T) -> String): List<Pair<String, List<T>>> =
        items.groupBy { val c = normalize(label(it)).firstOrNull(); if (c != null && c in 'a'..'z') c.uppercase() else "#" }
            .toList()

    /** "MI, 11 NOV" / "WED, 11 NOV" – the Noxis date line. */
    fun shortDate(d: java.util.Date, locale: Locale): String =
        java.text.SimpleDateFormat("EEE, dd MMM", locale).format(d).replace(".", "").uppercase(locale)

    /** Status line parts after the battery: network, then VPN marker. */
    fun netParts(wifi: Boolean, cellular: Boolean, vpn: Boolean): List<String> = buildList {
        add(when { wifi -> "WLAN"; cellular -> "MOBIL"; else -> "OFFLINE" })
        if (vpn) add("VPN")
    }

    fun clock(hour: Int, minute: Int, h24: Boolean): String {
        val h = if (h24) hour else ((hour + 11) % 12) + 1
        return "%02d:%02d".format(h, minute)
    }
}

/** A home-screen widget: a system app widget (id) or a built-in Noxis widget (name). */
data class WidgetSpec(val kind: Char, val ref: String, val heightDp: Int) {
    val builtin get() = kind == 'b'
    fun encode() = "$kind:$ref:$heightDp"

    companion object {
        const val MIN_H = 80
        const val MAX_H = 480
        const val STEP = 40
        val BUILTINS = listOf("battery", "alarm", "storage")

        fun decode(s: String): WidgetSpec? {
            val p = s.split(':')
            if (p.size != 3 || p[0].length != 1 || p[0][0] !in "wb") return null
            val h = p[2].toIntOrNull() ?: return null
            if (p[0] == "w" && p[1].toIntOrNull() == null) return null
            if (p[0] == "b" && p[1] !in BUILTINS) return null
            return WidgetSpec(p[0][0], p[1], h.coerceIn(MIN_H, MAX_H))
        }

        fun decodeAll(list: List<String>) = list.mapNotNull(::decode)

        fun system(id: Int, minHeightDp: Int) = WidgetSpec('w', id.toString(), minHeightDp.coerceIn(MIN_H + 30, MAX_H))
        fun builtin(name: String) = WidgetSpec('b', name, 150)

        fun resize(w: WidgetSpec, steps: Int) = w.copy(heightDp = (w.heightDp + steps * STEP).coerceIn(MIN_H, MAX_H))

        /** Layout rows: built-in widgets pair up two per row (Nothing style), system widgets get a full row. */
        fun rows(list: List<WidgetSpec>): List<List<WidgetSpec>> {
            val out = mutableListOf<List<WidgetSpec>>()
            var pending: WidgetSpec? = null
            for (w in list) {
                if (w.builtin) {
                    if (pending != null) { out += listOf(pending, w); pending = null } else pending = w
                } else {
                    pending?.let { out += listOf(it); pending = null }
                    out += listOf(w)
                }
            }
            pending?.let { out += listOf(it) }
            return out
        }
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
        '%' to listOf("11001", "11010", "00010", "00100", "01000", "01011", "10011"),
        '-' to listOf("00000", "00000", "00000", "11111", "00000", "00000", "00000"),
        ':' to listOf("0", "0", "1", "0", "1", "0", "0"),
        ' ' to listOf("0", "0", "0", "0", "0", "0", "0"),
    )

    fun columns(text: String): Int = text.sumOf { (glyphs[it]?.first()?.length ?: 0) + 1 } - 1
}
