package com.noxis.launcher

import android.content.ComponentName
import android.content.Context
import android.content.SharedPreferences
import android.content.pm.LauncherActivityInfo
import android.content.pm.LauncherApps
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.Paint
import android.graphics.drawable.AdaptiveIconDrawable
import android.graphics.drawable.Drawable
import android.os.Build
import android.os.Process
import android.os.UserHandle
import androidx.core.graphics.drawable.toBitmap

/** One launchable activity with its rendered icons. */
class AppItem(
    val key: AppKey,
    val component: ComponentName,
    val user: UserHandle,
    val icon: Bitmap,
    val mono: Bitmap,       // white monochrome layer (Android 13+ themed icons) or a grayscale fallback
    val themed: Boolean,    // true = real monochrome layer, false = grayscale fallback
)

class Apps(private val ctx: Context) {
    private val la = ctx.getSystemService(LauncherApps::class.java)
    private val iconPx = (48 * ctx.resources.displayMetrics.density).toInt()

    fun load(): List<AppItem> =
        la.getActivityList(null, Process.myUserHandle())
            .filter { it.componentName.packageName != ctx.packageName }
            .map(::toItem)

    private fun toItem(info: LauncherActivityInfo): AppItem {
        val cn = info.componentName
        val icon = info.getIcon(0)
        val bmp = icon.toBitmap(iconPx, iconPx)
        val m = monochrome(icon)
        return AppItem(
            AppKey(cn.flattenToShortString(), info.label.toString(), cn.packageName),
            cn, info.user, bmp, m ?: grayscale(bmp), m != null,
        )
    }

    private fun monochrome(d: Drawable): Bitmap? {
        if (Build.VERSION.SDK_INT < 33 || d !is AdaptiveIconDrawable) return null
        val m = d.monochrome ?: return null
        val bmp = Bitmap.createBitmap(iconPx, iconPx, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        // the monochrome layer is an adaptive foreground (108 dp with 18 dp safe padding each side)
        val pad = (iconPx * 0.25f).toInt()
        m.mutate().setBounds(-pad, -pad, iconPx + pad, iconPx + pad)
        m.setTint(android.graphics.Color.WHITE)
        m.draw(c)
        return bmp
    }

    private fun grayscale(src: Bitmap): Bitmap {
        val out = Bitmap.createBitmap(src.width, src.height, Bitmap.Config.ARGB_8888)
        val p = Paint(Paint.ANTI_ALIAS_FLAG)
        p.colorFilter = ColorMatrixColorFilter(ColorMatrix().apply { setSaturation(0f) })
        Canvas(out).drawBitmap(src, 0f, 0f, p)
        return out
    }

    /** Package of the default app for an intent (dialer, SMS, browser, camera), if any. */
    fun defaultPackage(i: android.content.Intent): String? =
        ctx.packageManager.resolveActivity(i, android.content.pm.PackageManager.MATCH_DEFAULT_ONLY)
            ?.activityInfo?.packageName?.takeIf { it != "android" }

    fun launch(item: AppItem) = la.startMainActivity(item.component, item.user, null, null)
    fun details(item: AppItem) = la.startAppDetailsActivity(item.component, item.user, null, null)

    fun watch(onChange: () -> Unit): LauncherApps.Callback {
        val cb = object : LauncherApps.Callback() {
            override fun onPackageRemoved(p: String?, u: UserHandle?) = onChange()
            override fun onPackageAdded(p: String?, u: UserHandle?) = onChange()
            override fun onPackageChanged(p: String?, u: UserHandle?) = onChange()
            override fun onPackagesAvailable(p: Array<out String>?, u: UserHandle?, r: Boolean) = onChange()
            override fun onPackagesUnavailable(p: Array<out String>?, u: UserHandle?, r: Boolean) = onChange()
        }
        la.registerCallback(cb)
        return cb
    }

    fun unwatch(cb: LauncherApps.Callback) = la.unregisterCallback(cb)
}

class LauncherPrefs(ctx: Context) {
    private val sp: SharedPreferences = ctx.getSharedPreferences("noxis_launcher", Context.MODE_PRIVATE)

    var pinned: List<String>
        get() = Logic.decode(sp.getString("pinned", null))
        set(v) = sp.edit().putString("pinned", Logic.encode(v)).apply()
    var dock: List<String>
        get() = Logic.decode(sp.getString("dock", null))
        set(v) = sp.edit().putString("dock", Logic.encode(v)).putBoolean("dock_set", true).apply()
    val dockSet: Boolean get() = sp.getBoolean("dock_set", false)
    var hidden: Set<String>
        get() = Logic.decode(sp.getString("hidden", null)).toSet()
        set(v) = sp.edit().putString("hidden", Logic.encode(v.toList())).apply()
    var mono: Boolean
        get() = sp.getBoolean("mono", true)
        set(v) = sp.edit().putBoolean("mono", v).apply()
    var clock24: Boolean
        get() = sp.getBoolean("clock24", true)
        set(v) = sp.edit().putBoolean("clock24", v).apply()
    var realIcons: Boolean
        get() = sp.getBoolean("real_icons", false)
        set(v) = sp.edit().putBoolean("real_icons", v).apply()
    var wallpaper: Boolean
        get() = sp.getBoolean("wallpaper", false)
        set(v) = sp.edit().putBoolean("wallpaper", v).apply()
    var showHidden: Boolean
        get() = sp.getBoolean("show_hidden", false)
        set(v) = sp.edit().putBoolean("show_hidden", v).apply()
}
