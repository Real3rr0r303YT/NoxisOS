package com.noxis.launcher

import android.app.AlarmManager
import android.appwidget.AppWidgetHost
import android.appwidget.AppWidgetHostView
import android.appwidget.AppWidgetProviderInfo
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.StatFs
import android.util.SizeF
import android.view.MotionEvent
import android.view.ViewConfiguration
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import java.util.Date

/* ------------------------------------------------------------------ system widgets */

/** AppWidgetHost whose views report a long press (widgets swallow normal touches). */
class NoxisWidgetHost(ctx: Context) : AppWidgetHost(ctx, HOST_ID) {
    var onLongPress: (Int) -> Unit = {}

    override fun onCreateView(ctx: Context, id: Int, info: AppWidgetProviderInfo?): AppWidgetHostView =
        NoxisWidgetView(ctx) { onLongPress(id) }

    companion object { const val HOST_ID = 0x4E58 }
}

class NoxisWidgetView(ctx: Context, private val onLong: () -> Unit) : AppWidgetHostView(ctx) {
    private val slop = ViewConfiguration.get(ctx).scaledTouchSlop
    private var downX = 0f
    private var downY = 0f
    private var fired = false
    private val longPress = Runnable { fired = true; performHapticFeedback(0); onLong() }

    override fun onInterceptTouchEvent(ev: MotionEvent): Boolean {
        when (ev.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                fired = false; downX = ev.x; downY = ev.y
                postDelayed(longPress, ViewConfiguration.getLongPressTimeout().toLong())
            }
            MotionEvent.ACTION_MOVE ->
                if (Math.abs(ev.x - downX) > slop || Math.abs(ev.y - downY) > slop) removeCallbacks(longPress)
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> removeCallbacks(longPress)
        }
        return fired
    }

    override fun onTouchEvent(ev: MotionEvent): Boolean {
        if (ev.actionMasked == MotionEvent.ACTION_UP || ev.actionMasked == MotionEvent.ACTION_CANCEL) removeCallbacks(longPress)
        return fired || super.onTouchEvent(ev)
    }

    /** Tell the widget how big it is so it picks the right layout. */
    fun setSizeDp(wDp: Int, hDp: Int) {
        if (Build.VERSION.SDK_INT >= 31) {
            updateAppWidgetSize(Bundle(), listOf(SizeF(wDp.toFloat(), hDp.toFloat())))
        } else {
            @Suppress("DEPRECATION")
            updateAppWidgetSize(null, wDp, hDp, wDp, hDp)
        }
    }
}

/* ------------------------------------------------------------------ built-in Noxis widgets */

private val Accent = Color(0xFFFF2A2A)
private val Ink = Color(0xFFF2F2F2)
private val Muted = Color(0xFF8A8A8A)
private val Mono = FontFamily.Monospace

@Composable
fun BuiltinWidget(name: String, battery: Int?, charging: Boolean, modifier: Modifier) {
    Box(modifier.padding(16.dp)) {
        when (name) {
            "battery" -> BatteryWidget(battery, charging)
            "alarm" -> AlarmWidget()
            "storage" -> StorageWidget()
        }
    }
}

@Composable
private fun WidgetLabel(text: String) =
    Text(text, color = Muted, fontFamily = Mono, fontSize = 11.sp, letterSpacing = 2.sp)

@Composable
private fun DotText(text: String, dotDp: Float, lit: Color = Ink) {
    val cols = DotFont.columns(text).coerceAtLeast(1)
    Canvas(Modifier.padding(top = 2.dp).height((7 * dotDp).dp).fillMaxWidth()) {
        val step = minOf(size.width / cols, size.height / 7)
        val r = step * 0.38f
        var x0 = 0
        for (ch in text) {
            val g = DotFont.glyphs[ch] ?: continue
            for ((row, line) in g.withIndex()) for ((col, bit) in line.withIndex()) {
                if (bit == '1') drawCircle(lit, r, Offset((x0 + col) * step + step / 2, row * step + step / 2))
            }
            x0 += g[0].length + 1
        }
    }
}

@Composable
private fun BatteryWidget(level: Int?, charging: Boolean) {
    Column(Modifier.fillMaxSize()) {
        Box(Modifier.fillMaxWidth().weight(1f)) {
            Canvas(Modifier.fillMaxSize()) {
                val d = minOf(size.width, size.height) * 0.8f
                val tl = Offset(0f, (size.height - d) / 2)
                val sz = androidx.compose.ui.geometry.Size(d, d)
                drawArc(Color.White.copy(alpha = 0.1f), 0f, 360f, false, tl, sz, style = Stroke(8.dp.toPx()))
                drawArc(if ((level ?: 0) <= 15) Accent else Ink, -90f, 3.6f * (level ?: 0), false, tl, sz,
                    style = Stroke(8.dp.toPx(), cap = StrokeCap.Round))
            }
            if (charging) Text("⚡", color = Accent, fontSize = 16.sp, modifier = Modifier.align(Alignment.TopEnd))
        }
        Spacer(Modifier.height(8.dp))
        DotText(level?.let { "$it%" } ?: "--", 4f)
    }
}

@Composable
private fun AlarmWidget() {
    val ctx = LocalContext.current
    var next by remember { mutableStateOf<Long?>(null) }
    LaunchedEffect(Unit) {
        while (true) {
            next = ctx.getSystemService(AlarmManager::class.java)?.nextAlarmClock?.triggerTime
            delay(60_000)
        }
    }
    Column(Modifier.fillMaxSize()) {
        WidgetLabel(ctx.getString(R.string.widget_alarm).uppercase())
        Spacer(Modifier.weight(1f))
        val t = next
        if (t == null) {
            DotText("--:--", 4f, Muted)
            Text(ctx.getString(R.string.no_alarm), color = Muted, fontFamily = Mono, fontSize = 11.sp, letterSpacing = 1.sp)
        } else {
            val c = java.util.Calendar.getInstance().apply { timeInMillis = t }
            DotText(Logic.clock(c.get(java.util.Calendar.HOUR_OF_DAY), c.get(java.util.Calendar.MINUTE), true), 4f)
            Text(Logic.shortDate(Date(t), java.util.Locale.getDefault()), color = Accent, fontFamily = Mono,
                fontWeight = FontWeight.Bold, fontSize = 11.sp, letterSpacing = 1.sp)
        }
    }
}

@Composable
private fun StorageWidget() {
    val ctx = LocalContext.current
    val st = remember { StatFs(Environment.getDataDirectory().path) }
    val free = st.availableBytes
    val total = st.totalBytes.coerceAtLeast(1)
    val used = 1f - free.toFloat() / total
    Column(Modifier.fillMaxSize()) {
        WidgetLabel(ctx.getString(R.string.widget_storage).uppercase())
        Spacer(Modifier.weight(1f))
        DotText("${free / 1_000_000_000}", 4f)
        Text(ctx.getString(R.string.storage_free, "GB"), color = Muted, fontFamily = Mono, fontSize = 11.sp, letterSpacing = 1.sp)
        Spacer(Modifier.height(10.dp))
        Canvas(Modifier.fillMaxWidth().height(8.dp)) {
            val n = 20
            val step = size.width / n
            for (i in 0 until n) {
                drawCircle(if (i < (used * n).toInt()) (if (used > 0.9f) Accent else Ink) else Color.White.copy(alpha = 0.12f),
                    step * 0.32f, Offset(i * step + step / 2, size.height / 2))
            }
        }
    }
}
