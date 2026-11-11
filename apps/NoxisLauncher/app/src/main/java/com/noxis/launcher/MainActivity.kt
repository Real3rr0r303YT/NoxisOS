package com.noxis.launcher

import android.annotation.SuppressLint
import android.app.role.RoleManager
import android.content.Intent
import android.content.pm.LauncherApps
import android.net.Uri
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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import java.text.DateFormat
import java.util.Calendar
import java.util.Date

private val Accent = Color(0xFF7C8CFF)
private val Ink = Color(0xFFF2F3F7)
private const val GUARD_PKG = "com.noxis.guard"

class MainActivity : ComponentActivity() {
    private lateinit var apps: Apps
    private lateinit var prefs: LauncherPrefs
    private var callback: LauncherApps.Callback? = null
    private var drawerOpen by mutableStateOf(false)
    private var appsVersion by mutableIntStateOf(0)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        apps = Apps(this)
        prefs = LauncherPrefs(this)
        callback = apps.watch { appsVersion++ }
        setContent {
            MaterialTheme(colorScheme = darkColorScheme(primary = Accent, background = Color.Transparent)) {
                LauncherScreen()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        drawerOpen = false          // Home button: always back to the home screen
    }

    override fun onDestroy() {
        callback?.let(apps::unwatch)
        super.onDestroy()
    }

    @SuppressLint("WrongConstant")
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

    @OptIn(ExperimentalFoundationApi::class)
    @Composable
    private fun LauncherScreen() {
        var all by remember { mutableStateOf<List<AppItem>>(emptyList()) }
        var pinned by remember { mutableStateOf(prefs.pinned) }
        var dock by remember { mutableStateOf(prefs.dock) }
        var hidden by remember { mutableStateOf(prefs.hidden) }
        var mono by remember { mutableStateOf(prefs.mono) }
        var clock24 by remember { mutableStateOf(prefs.clock24) }
        var showHidden by remember { mutableStateOf(prefs.showHidden) }
        var menuFor by remember { mutableStateOf<AppItem?>(null) }
        var settingsOpen by remember { mutableStateOf(false) }

        LaunchedEffect(appsVersion) {
            all = withContext(Dispatchers.IO) { apps.load() }
            val keys = all.map { it.key.key }.toSet()
            pinned = Logic.prune(pinned, keys).also { prefs.pinned = it }
            if (!prefs.dockSet && all.isNotEmpty()) {
                val firstKeyOf = { pkg: String? -> all.firstOrNull { it.key.pkg == pkg }?.key?.key }
                dock = Logic.defaultDock(listOf(
                    firstKeyOf(apps.defaultPackage(Intent(Intent.ACTION_DIAL))),
                    firstKeyOf(apps.defaultPackage(Intent.makeMainSelectorActivity(Intent.ACTION_MAIN, Intent.CATEGORY_APP_MESSAGING))),
                    firstKeyOf(apps.defaultPackage(Intent(Intent.ACTION_VIEW, Uri.parse("https://example.org")))),
                    firstKeyOf(apps.defaultPackage(Intent(MediaStore.INTENT_ACTION_STILL_IMAGE_CAMERA))),
                ), keys).also { prefs.dock = it }
            } else {
                dock = Logic.prune(dock, keys).also { if (prefs.dockSet) prefs.dock = it }
            }
            hidden = Logic.prune(hidden.toList(), keys).toSet().also { prefs.hidden = it }
        }

        val byKey = all.associateBy { it.key.key }
        val launch: (AppItem) -> Unit = { apps.launch(it); drawerOpen = false }

        Box(
            Modifier
                .fillMaxSize()
                .background(Brush.verticalGradient(listOf(Color(0x66000000), Color(0x22000000), Color(0x99000000))))
        ) {
            AnimatedVisibility(visible = !drawerOpen, enter = fadeIn(), exit = fadeOut()) {
                HomeScreen(
                    pinned = pinned.mapNotNull(byKey::get), dock = dock.mapNotNull(byKey::get),
                    mono = mono, clock24 = clock24,
                    onLaunch = launch, onLongPressApp = { menuFor = it },
                    onSwipeUp = { drawerOpen = true }, onSwipeDown = { expandNotifications() },
                    onLongPressHome = { settingsOpen = true },
                    onGuard = { startSafely(packageManager.getLaunchIntentForPackage(GUARD_PKG)) },
                    guardInstalled = packageManager.getLaunchIntentForPackage(GUARD_PKG) != null,
                )
            }
            AnimatedVisibility(
                visible = drawerOpen,
                enter = slideInVertically { it / 3 } + fadeIn(),
                exit = slideOutVertically { it / 3 } + fadeOut(),
            ) {
                Drawer(all, hidden, showHidden, mono, onLaunch = launch, onLongPress = { menuFor = it },
                    onClose = { drawerOpen = false })
            }
        }

        BackHandler(enabled = drawerOpen) { drawerOpen = false }

        menuFor?.let { item ->
            val k = item.key.key
            AlertDialog(
                onDismissRequest = { menuFor = null },
                title = { Text(item.key.label) },
                text = {
                    Column {
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
                },
                confirmButton = {},
            )
        }

        if (settingsOpen) {
            AlertDialog(
                onDismissRequest = { settingsOpen = false },
                title = { Text(stringResource(R.string.settings)) },
                text = {
                    Column {
                        SwitchRow(stringResource(R.string.mono_icons), mono) { mono = it; prefs.mono = it }
                        Text(stringResource(R.string.mono_icons_sum), fontSize = 12.sp, color = Ink.copy(alpha = 0.6f))
                        SwitchRow(stringResource(R.string.clock_24h), clock24) { clock24 = it; prefs.clock24 = it }
                        SwitchRow(stringResource(R.string.show_hidden), showHidden) { showHidden = it; prefs.showHidden = it }
                        MenuRow(stringResource(R.string.default_home)) {
                            val rm = getSystemService(RoleManager::class.java)
                            startSafely(rm?.createRequestRoleIntent(RoleManager.ROLE_HOME)
                                ?: Intent(Settings.ACTION_HOME_SETTINGS))
                            settingsOpen = false
                        }
                    }
                },
                confirmButton = { TextButton(onClick = { settingsOpen = false }) { Text("OK") } },
            )
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun HomeScreen(
    pinned: List<AppItem>, dock: List<AppItem>, mono: Boolean, clock24: Boolean,
    onLaunch: (AppItem) -> Unit, onLongPressApp: (AppItem) -> Unit,
    onSwipeUp: () -> Unit, onSwipeDown: () -> Unit, onLongPressHome: () -> Unit,
    onGuard: () -> Unit, guardInstalled: Boolean,
) {
    var now by remember { mutableStateOf(Calendar.getInstance()) }
    LaunchedEffect(Unit) {
        while (true) {
            now = Calendar.getInstance()
            delay(60_000L - (System.currentTimeMillis() % 60_000L))
        }
    }
    var drag by remember { mutableStateOf(0f) }
    Column(
        Modifier
            .fillMaxSize()
            .statusBarsPadding()
            .navigationBarsPadding()
            .pointerInput(Unit) {
                detectVerticalDragGestures(
                    onDragStart = { drag = 0f },
                    onDragEnd = {
                        if (drag < -80f) onSwipeUp() else if (drag > 80f) onSwipeDown()
                        drag = 0f
                    },
                ) { _, dy -> drag += dy }
            }
            .combinedClickable(onClick = {}, onLongClick = onLongPressHome, indication = null,
                interactionSource = null),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.height(48.dp))
        DotClock(Logic.clock(now.get(Calendar.HOUR_OF_DAY), now.get(Calendar.MINUTE), clock24))
        Spacer(Modifier.height(14.dp))
        Text(DateFormat.getDateInstance(DateFormat.FULL).format(Date(now.timeInMillis)),
            color = Ink.copy(alpha = 0.75f), fontSize = 15.sp, letterSpacing = 1.sp)
        if (guardInstalled) {
            Spacer(Modifier.height(18.dp))
            Row(
                Modifier
                    .clip(RoundedCornerShape(50))
                    .border(1.dp, Accent.copy(alpha = 0.6f), RoundedCornerShape(50))
                    .combinedClickable(onClick = onGuard)
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Canvas(Modifier.size(8.dp)) { drawCircle(Accent) }
                Spacer(Modifier.width(8.dp))
                Text(stringResource(R.string.guard), color = Ink, fontSize = 13.sp)
            }
        }
        Spacer(Modifier.height(28.dp))
        // home grid: 4 columns, up to 16 apps (long press in the drawer → "Add to home")
        Column(Modifier.fillMaxWidth().padding(horizontal = 8.dp)) {
            pinned.chunked(4).forEach { row ->
                Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), horizontalArrangement = Arrangement.SpaceEvenly) {
                    row.forEach { AppCell(it, mono, showLabel = true, onClick = onLaunch, onLongClick = onLongPressApp) }
                    repeat(4 - row.size) { Spacer(Modifier.width(84.dp)) }
                }
            }
        }
        Spacer(Modifier.weight(1f))
        if (pinned.isEmpty()) {
            Text(stringResource(R.string.home_hint), color = Ink.copy(alpha = 0.45f), fontSize = 12.sp)
            Spacer(Modifier.height(12.dp))
        }
        Row(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp)
                .clip(RoundedCornerShape(32.dp))
                .background(Color(0x55000000))
                .padding(vertical = 10.dp),
            horizontalArrangement = Arrangement.SpaceEvenly,
        ) {
            dock.forEach { AppCell(it, mono, showLabel = false, onClick = onLaunch, onLongClick = onLongPressApp) }
        }
    }
}

@Composable
private fun DotClock(text: String) {
    val cols = DotFont.columns(text)
    Canvas(Modifier.width((cols * 9).dp).height((7 * 9).dp)) {
        val step = size.width / cols
        val r = step * 0.36f
        var x0 = 0
        for (ch in text) {
            val g = DotFont.glyphs[ch] ?: continue
            for ((row, line) in g.withIndex()) for ((col, bit) in line.withIndex()) {
                val c = Offset((x0 + col) * step + step / 2, row * step + step / 2)
                if (bit == '1') drawCircle(Ink, r, c) else drawCircle(Ink.copy(alpha = 0.07f), r, c)
            }
            x0 += g[0].length + 1
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun AppCell(
    item: AppItem, mono: Boolean, showLabel: Boolean,
    onClick: (AppItem) -> Unit, onLongClick: (AppItem) -> Unit,
) {
    Column(
        Modifier
            .clip(RoundedCornerShape(16.dp))
            .combinedClickable(onClick = { onClick(item) }, onLongClick = { onLongClick(item) })
            .padding(6.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        if (mono && item.themed) {
            Box(Modifier.size(54.dp).clip(CircleShape).background(Color(0x33FFFFFF)), Alignment.Center) {
                Image(item.mono.asImageBitmap(), item.key.label, Modifier.size(54.dp))
            }
        } else if (mono) {
            Image(item.mono.asImageBitmap(), item.key.label, Modifier.size(54.dp))
        } else {
            Image(item.icon.asImageBitmap(), item.key.label, Modifier.size(54.dp))
        }
        if (showLabel) {
            Spacer(Modifier.height(6.dp))
            Text(item.key.label, color = Ink, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis,
                textAlign = TextAlign.Center, modifier = Modifier.width(72.dp))
        }
    }
}

@Composable
private fun Drawer(
    all: List<AppItem>, hidden: Set<String>, showHidden: Boolean, mono: Boolean,
    onLaunch: (AppItem) -> Unit, onLongPress: (AppItem) -> Unit, onClose: () -> Unit,
) {
    var query by remember { mutableStateOf("") }
    val byKey = all.associateBy { it.key.key }
    val shown = Logic.filter(all.map { it.key }, query, hidden, showHidden).mapNotNull { byKey[it.key] }
    var drag by remember { mutableStateOf(0f) }
    Column(
        Modifier
            .fillMaxSize()
            .background(Color(0xFF07070B))
            .statusBarsPadding()
            .navigationBarsPadding()
            .imePadding()
            .pointerInput(Unit) {
                detectVerticalDragGestures(onDragStart = { drag = 0f },
                    onDragEnd = { if (drag > 160f) onClose(); drag = 0f }) { _, dy -> drag += dy }
            }
            .padding(horizontal = 12.dp),
    ) {
        Spacer(Modifier.height(12.dp))
        OutlinedTextField(
            value = query, onValueChange = { query = it }, singleLine = true,
            placeholder = { Text(stringResource(R.string.search)) },
            shape = RoundedCornerShape(50),
            colors = OutlinedTextFieldDefaults.colors(focusedBorderColor = Accent, unfocusedBorderColor = Ink.copy(alpha = 0.2f),
                focusedTextColor = Ink, unfocusedTextColor = Ink),
            modifier = Modifier.fillMaxWidth(),
        )
        Spacer(Modifier.height(12.dp))
        if (shown.isEmpty()) {
            Text(stringResource(R.string.no_results), color = Ink.copy(alpha = 0.6f), modifier = Modifier.padding(24.dp))
        }
        LazyVerticalGrid(columns = GridCells.Fixed(4), modifier = Modifier.weight(1f)) {
            items(shown, key = { it.key.key }) { item ->
                Box(Modifier.padding(vertical = 6.dp), Alignment.Center) {
                    AppCell(item, mono, showLabel = true, onClick = onLaunch, onLongClick = onLongPress)
                }
            }
        }
    }
}

@Composable
private fun MenuRow(label: String, onClick: () -> Unit) {
    TextButton(onClick = onClick, modifier = Modifier.fillMaxWidth()) {
        Text(label, color = Ink, modifier = Modifier.fillMaxWidth(), fontWeight = FontWeight.Normal)
    }
}

@Composable
private fun SwitchRow(label: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(label, color = Ink, modifier = Modifier.weight(1f))
        Switch(checked = checked, onCheckedChange = onChange)
    }
}
