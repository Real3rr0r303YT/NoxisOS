package com.noxis.launcher

import android.app.role.RoleManager
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProviderInfo
import android.widget.Toast
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items as listItems
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.viewinterop.AndroidView
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.LauncherApps
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import androidx.compose.runtime.key
import androidx.core.graphics.drawable.toBitmap
import android.os.Bundle
import android.provider.MediaStore
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import java.util.Calendar
import java.util.Locale

// Noxis Shell palette (same as the Linux launcher)
private val Accent = Color(0xFFFF2A2A)
private val Bg = Color(0xFF050505)
private val Surface = Color(0xFF121212)
private val Surface2 = Color(0xFF1B1B1B)
private val Line = Color(0x14FFFFFF)
private val Ink = Color(0xFFF2F2F2)
private val Muted = Color(0xFF8A8A8A)
private val Mono = FontFamily.Monospace
private const val GUARD_PKG = "com.noxis.guard"

class MainActivity : ComponentActivity() {
    private lateinit var apps: Apps
    private lateinit var prefs: LauncherPrefs
    private var callback: LauncherApps.Callback? = null
    private var drawerOpen by mutableStateOf(false)
    private var searchFocus by mutableStateOf(false)
    private var appsVersion by mutableIntStateOf(0)

    // widgets
    private lateinit var host: NoxisWidgetHost
    private lateinit var awm: AppWidgetManager
    private var widgets by mutableStateOf<List<WidgetSpec>>(emptyList())
    private var widgetMenuFor by mutableStateOf<WidgetSpec?>(null)
    private var pickerOpen by mutableStateOf(false)
    private var pendingId = -1
    private var pendingInfo: AppWidgetProviderInfo? = null

    private fun saveWidgets(v: List<WidgetSpec>) { widgets = v; prefs.widgets = v }

    private fun addBuiltin(name: String) = saveWidgets(widgets + WidgetSpec.builtin(name))

    private fun addSystem(info: AppWidgetProviderInfo) {
        val id = host.allocateAppWidgetId()
        pendingId = id; pendingInfo = info
        if (awm.bindAppWidgetIdIfAllowed(id, info.profile, info.provider, null)) {
            configureOrAdd()
        } else {
            val i = Intent(AppWidgetManager.ACTION_APPWIDGET_BIND)
                .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
                .putExtra(AppWidgetManager.EXTRA_APPWIDGET_PROVIDER, info.provider)
                .putExtra(AppWidgetManager.EXTRA_APPWIDGET_PROVIDER_PROFILE, info.profile)
            try { @Suppress("DEPRECATION") startActivityForResult(i, REQ_BIND) } catch (e: Exception) { failPending() }
        }
    }

    private fun configureOrAdd() {
        val info = pendingInfo ?: return failPending()
        val optional = Build.VERSION.SDK_INT >= 28 &&
            (info.widgetFeatures and AppWidgetProviderInfo.WIDGET_FEATURE_CONFIGURATION_OPTIONAL) != 0
        if (info.configure != null && !optional) {
            try { host.startAppWidgetConfigureActivityForResult(this, pendingId, 0, REQ_CONFIG, null) }
            catch (e: Exception) { failPending() }
        } else finishPending()
    }

    private fun finishPending() {
        val info = pendingInfo ?: return
        val minH = (info.minHeight / resources.displayMetrics.density).toInt()
        saveWidgets(widgets + WidgetSpec.system(pendingId, minH))
        pendingId = -1; pendingInfo = null
    }

    private fun failPending() {
        if (pendingId != -1) host.deleteAppWidgetId(pendingId)
        pendingId = -1; pendingInfo = null
        Toast.makeText(this, R.string.widget_failed, Toast.LENGTH_SHORT).show()
    }

    fun removeWidget(w: WidgetSpec) {
        if (!w.builtin) w.ref.toIntOrNull()?.let { host.deleteAppWidgetId(it) }
        saveWidgets(widgets - w)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION") super.onActivityResult(requestCode, resultCode, data)
        if (pendingId == -1) return
        when (requestCode) {
            REQ_BIND -> if (resultCode == RESULT_OK) configureOrAdd() else failPending()
            REQ_CONFIG -> if (resultCode == RESULT_OK) finishPending() else failPending()
        }
    }

    override fun onStart() { super.onStart(); try { host.startListening() } catch (e: Exception) { } }
    override fun onStop() { super.onStop(); try { host.stopListening() } catch (e: Exception) { } }

    companion object {
        private const val REQ_BIND = 11
        private const val REQ_CONFIG = 12
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        apps = Apps(this)
        prefs = LauncherPrefs(this)
        callback = apps.watch { appsVersion++ }
        awm = AppWidgetManager.getInstance(this)
        host = NoxisWidgetHost(this).also { h -> h.onLongPress = { id -> widgetMenuFor = widgets.firstOrNull { it.ref == id.toString() && !it.builtin } } }
        // forget widgets whose provider was uninstalled
        widgets = prefs.widgets.filter { it.builtin || awm.getAppWidgetInfo(it.ref.toInt()) != null }
        prefs.widgets = widgets
        setContent {
            MaterialTheme(colorScheme = darkColorScheme(primary = Accent, background = Bg, surface = Surface)) {
                LauncherScreen()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        drawerOpen = false          // Home button: always back to the home screen
    }

    override fun onDestroy() {
        callback?.let { apps.unwatch(it) }
        super.onDestroy()
    }

    private fun expandNotifications() {
        try {
            val sb = getSystemService("statusbar") ?: return
            sb.javaClass.getMethod("expandNotificationsPanel").invoke(sb)
        } catch (e: Exception) { /* not available */ }
    }

    private fun startSafely(i: Intent?) {
        if (i == null) return
        try { startActivity(i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) } catch (e: Exception) { }
    }

    private fun openDrawer(withSearch: Boolean) {
        searchFocus = withSearch
        drawerOpen = true
    }

    @Composable
    private fun LauncherScreen() {
        var all by remember { mutableStateOf<List<AppItem>>(emptyList()) }
        var pinned by remember { mutableStateOf(prefs.pinned) }
        var dock by remember { mutableStateOf(prefs.dock) }
        var hidden by remember { mutableStateOf(prefs.hidden) }
        var realIcons by remember { mutableStateOf(prefs.realIcons) }
        var wallpaper by remember { mutableStateOf(prefs.wallpaper) }
        var clock24 by remember { mutableStateOf(prefs.clock24) }
        var showHidden by remember { mutableStateOf(prefs.showHidden) }
        var menuFor by remember { mutableStateOf<AppItem?>(null) }
        var settingsOpen by remember { mutableStateOf(false) }
        var homeMenu by remember { mutableStateOf(false) }

        LaunchedEffect(appsVersion) {
            all = withContext(Dispatchers.IO) { apps.load() }
            val keys = all.map { it.key.key }.toSet()
            pinned = Logic.prune(pinned, keys).also { prefs.pinned = it }
            hidden = Logic.prune(hidden.toList(), keys).toSet().also { prefs.hidden = it }
            if (!prefs.dockSet && all.isNotEmpty()) {
                val firstKeyOf = { pkg: String? -> all.firstOrNull { it.key.pkg == pkg }?.key?.key }
                dock = Logic.defaultDock(listOf(
                    firstKeyOf(apps.defaultPackage(Intent(Intent.ACTION_DIAL))),
                    firstKeyOf(apps.defaultPackage(Intent.makeMainSelectorActivity(Intent.ACTION_MAIN, Intent.CATEGORY_APP_MESSAGING))),
                    firstKeyOf(apps.defaultPackage(Intent(Intent.ACTION_VIEW, Uri.parse("https://example.org")))),
                    firstKeyOf(apps.defaultPackage(Intent(MediaStore.INTENT_ACTION_STILL_IMAGE_CAMERA))),
                ), keys).also { prefs.dock = it }
            } else if (prefs.dockSet) {
                dock = Logic.prune(dock, keys).also { prefs.dock = it }
            }
        }

        val byKey = all.associateBy { it.key.key }
        val launch: (AppItem) -> Unit = { apps.launch(it); drawerOpen = false }

        Box(Modifier.fillMaxSize()) {
            NoxisBackground(wallpaper)
            AnimatedVisibility(visible = !drawerOpen, enter = fadeIn(), exit = fadeOut()) {
                HomeScreen(
                    pinned = pinned.mapNotNull(byKey::get), dock = dock.mapNotNull(byKey::get),
                    realIcons = realIcons, clock24 = clock24,
                    onLaunch = launch, onLongPressApp = { menuFor = it },
                    onSearch = { openDrawer(true) },
                    onSwipeUp = { openDrawer(false) }, onSwipeDown = { expandNotifications() },
                    onLongPressHome = { homeMenu = true },
                    widgets = { status -> WidgetArea(status) },
                    onGuard = { startSafely(packageManager.getLaunchIntentForPackage(GUARD_PKG)) },
                    guardInstalled = packageManager.getLaunchIntentForPackage(GUARD_PKG) != null,
                )
            }
            AnimatedVisibility(
                visible = drawerOpen,
                enter = slideInVertically { it / 4 } + fadeIn(),
                exit = slideOutVertically { it / 4 } + fadeOut(),
            ) {
                Drawer(all, hidden, showHidden, realIcons, searchFocus,
                    onLaunch = launch, onLongPress = { menuFor = it }, onClose = { drawerOpen = false })
            }
        }

        BackHandler(enabled = drawerOpen) { drawerOpen = false }

        menuFor?.let { item ->
            val k = item.key.key
            NoxisDialog(title = item.key.label, onDismiss = { menuFor = null }) {
                MenuRow(stringResource(if (k in pinned) R.string.unpin else R.string.pin)) {
                    pinned = Logic.togglePin(pinned, k).also { prefs.pinned = it }; menuFor = null
                }
                MenuRow(stringResource(if (k in dock) R.string.dock_remove else R.string.dock_add)) {
                    dock = Logic.togglePin(dock, k, Logic.MAX_DOCK).also { prefs.dock = it }; menuFor = null
                }
                MenuRow(stringResource(if (k in hidden) R.string.unhide else R.string.hide)) {
                    hidden = (if (k in hidden) hidden - k else hidden + k).also { prefs.hidden = it }; menuFor = null
                }
                MenuRow(stringResource(R.string.app_info)) { apps.details(item); menuFor = null }
                MenuRow(stringResource(R.string.uninstall)) {
                    startSafely(Intent(Intent.ACTION_DELETE, Uri.parse("package:${item.key.pkg}"))); menuFor = null
                }
            }
        }

        if (homeMenu) {
            NoxisDialog(title = "NOXIS", onDismiss = { homeMenu = false }) {
                MenuRow(stringResource(R.string.add_widget)) { homeMenu = false; pickerOpen = true }
                MenuRow(stringResource(R.string.change_wallpaper)) {
                    homeMenu = false
                    wallpaper = true; prefs.wallpaper = true
                    startSafely(Intent.createChooser(Intent(Intent.ACTION_SET_WALLPAPER), null))
                }
                MenuRow(stringResource(R.string.settings)) { homeMenu = false; settingsOpen = true }
            }
        }

        if (pickerOpen) WidgetPicker()

        widgetMenuFor?.let { w ->
            NoxisDialog(title = "WIDGET", onDismiss = { widgetMenuFor = null }) {
                MenuRow(stringResource(R.string.bigger)) {
                    saveWidgets(widgets.map { if (it == w) WidgetSpec.resize(it, 1) else it }); widgetMenuFor = null
                }
                MenuRow(stringResource(R.string.smaller)) {
                    saveWidgets(widgets.map { if (it == w) WidgetSpec.resize(it, -1) else it }); widgetMenuFor = null
                }
                MenuRow(stringResource(R.string.remove)) { removeWidget(w); widgetMenuFor = null }
            }
        }

        if (settingsOpen) {
            NoxisDialog(title = stringResource(R.string.settings), onDismiss = { settingsOpen = false }) {
                SwitchRow(stringResource(R.string.icon_style), stringResource(R.string.icon_style_sum), realIcons) {
                    realIcons = it; prefs.realIcons = it
                }
                SwitchRow(stringResource(R.string.use_wallpaper), stringResource(R.string.use_wallpaper_sum), wallpaper) {
                    wallpaper = it; prefs.wallpaper = it
                }
                SwitchRow(stringResource(R.string.clock_24h), null, clock24) { clock24 = it; prefs.clock24 = it }
                SwitchRow(stringResource(R.string.show_hidden), null, showHidden) { showHidden = it; prefs.showHidden = it }
                MenuRow(stringResource(R.string.default_home)) {
                    val rm = getSystemService(RoleManager::class.java)
                    startSafely(rm?.createRequestRoleIntent(RoleManager.ROLE_HOME) ?: Intent(Settings.ACTION_HOME_SETTINGS))
                    settingsOpen = false
                }
            }
        }
    }

    @OptIn(ExperimentalFoundationApi::class)
    @Composable
    private fun WidgetArea(status: SysStatus) {
        val shape = RoundedCornerShape(26.dp)
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState())) {
            WidgetSpec.rows(widgets).forEach { row ->
                Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    row.forEach { w -> key(w.kind, w.ref) {
                        val m = Modifier.weight(1f).height(w.heightDp.dp).clip(shape)
                        if (w.builtin) {
                            BuiltinWidget(w.ref, status.battery, status.charging,
                                m.background(Surface).border(1.dp, Line, shape)
                                    .combinedClickable(onClick = {}, onLongClick = { widgetMenuFor = w }))
                        } else {
                            val id = w.ref.toInt()
                            val full = row.size == 1
                            AndroidView(
                                modifier = m,
                                factory = { ctx ->
                                    (host.createView(ctx, id, awm.getAppWidgetInfo(id)) as NoxisWidgetView)
                                },
                                update = { v ->
                                    val wDp = (resources.configuration.screenWidthDp - 40) / (if (full) 1 else 2)
                                    v.setSizeDp(wDp, w.heightDp)
                                },
                            )
                        }
                    } }
                    if (row.size == 1 && row[0].builtin) Spacer(Modifier.weight(1f))
                }
            }
        }
    }

    @OptIn(ExperimentalFoundationApi::class)
    @Composable
    private fun WidgetPicker() {
        val providers = remember {
            awm.getInstalledProvidersForProfile(android.os.Process.myUserHandle())
                .filter { (it.widgetCategory and AppWidgetProviderInfo.WIDGET_CATEGORY_HOME_SCREEN) != 0 }
                .sortedBy { it.loadLabel(packageManager).lowercase() }
        }
        val names = mapOf("battery" to R.string.widget_battery, "alarm" to R.string.widget_alarm, "storage" to R.string.widget_storage)
        NoxisDialog(title = stringResource(R.string.add_widget).uppercase(), onDismiss = { pickerOpen = false }) {
            LazyColumn(Modifier.heightIn(max = 460.dp)) {
                item {
                    Text(stringResource(R.string.noxis_widgets).uppercase(), color = Accent, fontFamily = Mono, fontSize = 12.sp,
                        letterSpacing = 2.sp, modifier = Modifier.padding(vertical = 8.dp))
                }
                listItems(WidgetSpec.BUILTINS) { b ->
                    MenuRow(stringResource(names.getValue(b))) { pickerOpen = false; addBuiltin(b) }
                }
                item {
                    Text(stringResource(R.string.app_widgets).uppercase(), color = Accent, fontFamily = Mono, fontSize = 12.sp,
                        letterSpacing = 2.sp, modifier = Modifier.padding(top = 16.dp, bottom = 8.dp))
                }
                listItems(providers) { p ->
                    val app = remember(p) {
                        try { packageManager.getApplicationLabel(packageManager.getApplicationInfo(p.provider.packageName, 0)).toString() }
                        catch (e: Exception) { p.provider.packageName }
                    }
                    Row(
                        Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp))
                            .combinedClickable(onClick = { pickerOpen = false; addSystem(p) })
                            .padding(vertical = 10.dp, horizontal = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        val icon = remember(p) {
                            try { p.loadIcon(this@MainActivity, resources.displayMetrics.densityDpi)
                                ?.toBitmap(96, 96) } catch (e: Exception) { null }
                        }
                        if (icon != null) Image(icon.asImageBitmap(), null, Modifier.size(32.dp).clip(RoundedCornerShape(8.dp)))
                        Spacer(Modifier.width(12.dp))
                        Column {
                            Text(p.loadLabel(packageManager), color = Ink, fontSize = 15.sp)
                            Text(app, color = Muted, fontSize = 12.sp)
                        }
                    }
                }
            }
        }
    }
}

/* ------------------------------------------------------------------ background */


@Composable
private fun NoxisBackground(wallpaper: Boolean) {
    if (wallpaper) {
        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color(0x99000000), Color(0x33000000), Color(0xCC000000)))))
        return
    }
    Canvas(Modifier.fillMaxSize()) {
        drawRect(Bg)
        // red glow from the top, like the Linux shell
        drawRect(Brush.radialGradient(listOf(Accent.copy(alpha = 0.16f), Color.Transparent),
            center = Offset(size.width / 2, 0f), radius = size.height * 0.55f))
        // dot grid
        val step = 14.dp.toPx()
        val r = 0.9.dp.toPx()
        val dot = Color.White.copy(alpha = 0.06f)
        var y = step / 2
        while (y < size.height) {
            var x = step / 2
            while (x < size.width) { drawCircle(dot, r, Offset(x, y)); x += step }
            y += step
        }
    }
}

/* ------------------------------------------------------------------ home */

data class SysStatus(val battery: Int?, val charging: Boolean, val net: List<String>)

@Composable
private fun rememberStatus(): SysStatus {
    val ctx = LocalContext.current
    var status by remember { mutableStateOf(SysStatus(null, false, listOf("OFFLINE"))) }
    DisposableEffect(Unit) {
        fun net(): List<String> {
            val cm = ctx.getSystemService(ConnectivityManager::class.java)
            val caps = cm?.getNetworkCapabilities(cm.activeNetwork)
            return Logic.netParts(
                wifi = caps?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true,
                cellular = caps?.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) == true,
                vpn = caps?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true,
            )
        }
        val rx = object : BroadcastReceiver() {
            override fun onReceive(c: Context, i: Intent) {
                val level = i.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
                val scale = i.getIntExtra(BatteryManager.EXTRA_SCALE, 100)
                val plugged = i.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) != 0
                status = SysStatus(if (level >= 0) level * 100 / scale else null, plugged, net())
            }
        }
        ctx.registerReceiver(rx, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        onDispose { ctx.unregisterReceiver(rx) }
    }
    return status
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun HomeScreen(
    pinned: List<AppItem>, dock: List<AppItem>, realIcons: Boolean, clock24: Boolean,
    onLaunch: (AppItem) -> Unit, onLongPressApp: (AppItem) -> Unit, onSearch: () -> Unit,
    onSwipeUp: () -> Unit, onSwipeDown: () -> Unit, onLongPressHome: () -> Unit,
    onGuard: () -> Unit, guardInstalled: Boolean,
    widgets: @Composable (SysStatus) -> Unit,
) {
    var now by remember { mutableStateOf(Calendar.getInstance()) }
    LaunchedEffect(Unit) {
        while (true) {
            now = Calendar.getInstance()
            delay(60_000L - (System.currentTimeMillis() % 60_000L))
        }
    }
    val status = rememberStatus()
    var drag by remember { mutableStateOf(0f) }
    Column(
        Modifier
            .fillMaxSize()
            .statusBarsPadding()
            .navigationBarsPadding()
            .pointerInput(Unit) {
                detectVerticalDragGestures(
                    onDragStart = { drag = 0f },
                    onDragEnd = { if (drag < -80f) onSwipeUp() else if (drag > 80f) onSwipeDown(); drag = 0f },
                ) { _, dy -> drag += dy }
            }
            .combinedClickable(onClick = {}, onLongClick = onLongPressHome, indication = null, interactionSource = null)
            .padding(horizontal = 20.dp),
    ) {
        Spacer(Modifier.height(36.dp))
        DotClock(Logic.clock(now.get(Calendar.HOUR_OF_DAY), now.get(Calendar.MINUTE), clock24))
        Spacer(Modifier.height(16.dp))
        Text(Logic.shortDate(now.time, Locale.getDefault()), color = Ink, fontFamily = Mono,
            fontWeight = FontWeight.Bold, fontSize = 16.sp, letterSpacing = 3.sp)
        Spacer(Modifier.height(8.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            val parts = buildList {
                status.battery?.let { add(stringResource(R.string.battery, it) + if (status.charging) " ⚡" else "") }
                addAll(status.net)
            }
            parts.forEachIndexed { i, p ->
                if (i > 0) { Spacer(Modifier.width(10.dp)); Box(Modifier.size(4.dp).clip(CircleShape).background(Accent)); Spacer(Modifier.width(10.dp)) }
                Text(p, color = Muted, fontFamily = Mono, fontSize = 12.sp, letterSpacing = 1.5.sp)
            }
            if (guardInstalled) {
                Spacer(Modifier.weight(1f))
                Text("GUARD", color = Accent, fontFamily = Mono, fontWeight = FontWeight.Bold, fontSize = 12.sp,
                    letterSpacing = 2.sp, modifier = Modifier.clip(RoundedCornerShape(8.dp))
                        .combinedClickable(onClick = onGuard).padding(6.dp))
            }
        }
        Spacer(Modifier.height(28.dp))
        // search bar
        Row(
            Modifier
                .fillMaxWidth()
                .height(50.dp)
                .clip(RoundedCornerShape(25.dp))
                .background(Color.White.copy(alpha = 0.07f))
                .border(1.dp, Line, RoundedCornerShape(25.dp))
                .combinedClickable(onClick = onSearch)
                .padding(horizontal = 18.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            SearchGlyph()
            Spacer(Modifier.width(14.dp))
            Text(stringResource(R.string.search_home), color = Muted, fontSize = 16.sp)
        }
        Spacer(Modifier.height(14.dp))
        Box(Modifier.weight(1f).fillMaxWidth()) { widgets(status) }
        // home apps: 2 rows of 4
        pinned.chunked(4).forEach { row ->
            Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), horizontalArrangement = Arrangement.SpaceEvenly) {
                row.forEach { AppTile(it, realIcons, showLabel = true, onClick = onLaunch, onLongClick = onLongPressApp) }
                repeat(4 - row.size) { Spacer(Modifier.width(84.dp)) }
            }
        }
        if (pinned.isEmpty()) {
            Text(stringResource(R.string.home_hint), color = Muted.copy(alpha = 0.7f), fontSize = 12.sp,
                modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center)
        }
        Spacer(Modifier.height(14.dp))
        // dock
        Row(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(34.dp))
                .background(Color.White.copy(alpha = 0.06f))
                .border(1.dp, Line, RoundedCornerShape(34.dp))
                .padding(vertical = 12.dp),
            horizontalArrangement = Arrangement.SpaceEvenly,
        ) {
            dock.forEach { AppTile(it, realIcons, showLabel = false, onClick = onLaunch, onLongClick = onLongPressApp) }
        }
        Spacer(Modifier.height(16.dp))
    }
}

@Composable
private fun SearchGlyph() {
    Canvas(Modifier.size(20.dp)) {
        val s = size.minDimension
        drawCircle(Muted, s * 0.32f, Offset(s * 0.42f, s * 0.42f), style = androidx.compose.ui.graphics.drawscope.Stroke(s * 0.1f))
        drawLine(Muted, Offset(s * 0.66f, s * 0.66f), Offset(s * 0.92f, s * 0.92f), s * 0.1f)
    }
}

@Composable
private fun DotClock(text: String) {
    val cols = DotFont.columns(text)
    Canvas(Modifier.width((cols * 11).dp).height((7 * 11).dp)) {
        val step = size.width / cols
        val r = step * 0.38f
        var x0 = 0
        for (ch in text) {
            val g = DotFont.glyphs[ch] ?: continue
            val color = if (ch == ':') Accent else Ink
            for ((row, line) in g.withIndex()) for ((col, bit) in line.withIndex()) {
                val c = Offset((x0 + col) * step + step / 2, row * step + step / 2)
                if (bit == '1') drawCircle(color, r, c)
                else if (ch != ':') drawCircle(Ink.copy(alpha = 0.08f), r, c)
            }
            x0 += g[0].length + 1
        }
    }
}

/* ------------------------------------------------------------------ app tile */

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun AppTile(
    item: AppItem, realIcons: Boolean, showLabel: Boolean,
    onClick: (AppItem) -> Unit, onLongClick: (AppItem) -> Unit,
) {
    Column(
        Modifier
            .width(84.dp)
            .clip(RoundedCornerShape(18.dp))
            .combinedClickable(onClick = { onClick(item) }, onLongClick = { onLongClick(item) })
            .padding(vertical = 4.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        val shape = RoundedCornerShape(30)
        Box(
            Modifier.size(58.dp).clip(shape).background(Surface).border(1.dp, Line, shape),
            contentAlignment = Alignment.Center,
        ) {
            if (realIcons) {
                Image(item.tile.asImageBitmap(), item.key.label, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
            } else {
                Text(Logic.monogram(item.key.label), color = Ink, fontFamily = Mono, fontWeight = FontWeight.Bold, fontSize = 24.sp)
                Box(Modifier.align(Alignment.TopEnd).padding(top = 9.dp, end = 9.dp).size(7.dp).clip(CircleShape).background(Accent))
            }
        }
        if (showLabel) {
            Spacer(Modifier.height(8.dp))
            Text(item.key.label, color = Ink, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis,
                textAlign = TextAlign.Center, modifier = Modifier.width(80.dp))
        }
    }
}

/* ------------------------------------------------------------------ drawer */

@Composable
private fun Drawer(
    all: List<AppItem>, hidden: Set<String>, showHidden: Boolean, realIcons: Boolean, focusSearch: Boolean,
    onLaunch: (AppItem) -> Unit, onLongPress: (AppItem) -> Unit, onClose: () -> Unit,
) {
    var query by remember { mutableStateOf("") }
    val byKey = all.associateBy { it.key.key }
    val shown = Logic.filter(all.map { it.key }, query, hidden, showHidden).mapNotNull { byKey[it.key] }
    val focus = remember { FocusRequester() }
    LaunchedEffect(focusSearch) { if (focusSearch) runCatching { focus.requestFocus() } }
    var drag by remember { mutableStateOf(0f) }
    Column(
        Modifier
            .fillMaxSize()
            .background(Color(0xFF0A0A0A))
            .statusBarsPadding()
            .navigationBarsPadding()
            .imePadding()
            .pointerInput(Unit) {
                detectVerticalDragGestures(onDragStart = { drag = 0f },
                    onDragEnd = { if (drag > 160f) onClose(); drag = 0f }) { _, dy -> drag += dy }
            }
            .padding(horizontal = 16.dp),
    ) {
        Spacer(Modifier.height(8.dp))
        Box(Modifier.align(Alignment.CenterHorizontally).size(40.dp, 4.dp).clip(RoundedCornerShape(2.dp))
            .background(Color.White.copy(alpha = 0.25f)))
        Spacer(Modifier.height(14.dp))
        Row(
            Modifier
                .fillMaxWidth()
                .height(50.dp)
                .clip(RoundedCornerShape(25.dp))
                .background(Surface2)
                .border(1.dp, Line, RoundedCornerShape(25.dp))
                .padding(horizontal = 18.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            SearchGlyph()
            Spacer(Modifier.width(14.dp))
            Box(Modifier.weight(1f)) {
                if (query.isEmpty()) Text(stringResource(R.string.search), color = Muted, fontSize = 16.sp)
                BasicTextField(
                    value = query, onValueChange = { query = it }, singleLine = true,
                    textStyle = TextStyle(color = Ink, fontSize = 16.sp), cursorBrush = SolidColor(Accent),
                    modifier = Modifier.fillMaxWidth().focusRequester(focus),
                )
            }
        }
        Spacer(Modifier.height(8.dp))
        if (shown.isEmpty()) {
            Text(stringResource(R.string.no_results), color = Muted, modifier = Modifier.padding(24.dp))
        }
        val sections = if (query.isBlank()) Logic.sections(shown) { it.key.label } else listOf("" to shown)
        LazyVerticalGrid(columns = GridCells.Fixed(4), modifier = Modifier.weight(1f)) {
            sections.forEach { (letter, list) ->
                if (letter.isNotEmpty()) {
                    item(span = { GridItemSpan(4) }, key = "h_$letter") {
                        Text(letter, color = Accent, fontFamily = Mono, fontWeight = FontWeight.Bold, fontSize = 12.sp,
                            letterSpacing = 3.sp, modifier = Modifier.padding(start = 6.dp, top = 16.dp, bottom = 8.dp))
                    }
                }
                items(list, key = { it.key.key }) { item ->
                    Box(Modifier.padding(vertical = 6.dp), Alignment.Center) {
                        AppTile(item, realIcons, showLabel = true, onClick = onLaunch, onLongClick = onLongPress)
                    }
                }
            }
        }
    }
}

/* ------------------------------------------------------------------ dialogs */

@Composable
private fun NoxisDialog(title: String, onDismiss: () -> Unit, content: @Composable () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = Surface,
        title = { Text(title, color = Ink, fontFamily = Mono, fontWeight = FontWeight.Bold) },
        text = { Column { content() } },
        confirmButton = { TextButton(onClick = onDismiss) { Text("OK", color = Accent, fontFamily = Mono) } },
    )
}

@Composable
private fun MenuRow(label: String, onClick: () -> Unit) {
    TextButton(onClick = onClick, modifier = Modifier.fillMaxWidth()) {
        Text(label, color = Ink, modifier = Modifier.fillMaxWidth(), fontWeight = FontWeight.Normal)
    }
}

@Composable
private fun SwitchRow(label: String, summary: String?, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(label, color = Ink)
            if (summary != null) Text(summary, color = Muted, fontSize = 12.sp)
        }
        Switch(checked = checked, onCheckedChange = onChange,
            colors = SwitchDefaults.colors(checkedTrackColor = Accent, checkedThumbColor = Color.White))
    }
}
