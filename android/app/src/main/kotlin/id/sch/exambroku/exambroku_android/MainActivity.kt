package id.sch.exambroku.exambroku_android

import android.Manifest
import android.app.ActivityManager
import android.app.admin.DevicePolicyManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.Rect
import android.hardware.display.DisplayManager
import android.media.AudioManager
import android.media.ToneGenerator
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.ScanResult
import android.net.wifi.SupplicantState
import android.net.wifi.WifiConfiguration
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSpecifier
import android.net.wifi.WifiNetworkSuggestion
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.provider.Settings
import android.view.Display
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.window.OnBackInvokedDispatcher
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "id.sch.exambroku/security"
        private const val REQ_WIFI_SETTINGS = 4401
        private const val WIFI_SETTINGS_TIMEOUT_MS = 30000L

        var isWifiSessionActive: Boolean = false
            private set

        var isExamSessionActive: Boolean = false
            private set

        var instance: MainActivity? = null
            private set

        fun reportViolationFromService(code: String, reason: String) {
            instance?.let { act ->
                act.mainHandler.post {
                    if (act.examActive && act.wifiSettingsSessionActive) {
                        act.clearWifiSettingsState()
                        act.bringExamToFront()
                        act.notifyViolation(code, reason)
                    }
                }
            }
        }
    }

    private var methodChannel: MethodChannel? = null
    private var examActive = false
    private var requirePinning = true
    private var blockScreenshotsEnabled = true
    private var pinningGraceUntilMs = 0L
    private var wifiSettingsSessionActive = false
    private var wifiSettingsReturnedCleanly = false
    private var wifiSettingsSingleTaskQuirk = false
    private var wifiSettingsOpenedAtMs = 0L
    private val mainHandler = Handler(Looper.getMainLooper())
    private var wifiSettingsTimeoutRunnable: Runnable? = null
    private var displayManager: DisplayManager? = null
    private var displayListener: DisplayManager.DisplayListener? = null
    private var toneGenerator: ToneGenerator? = null

    private var isActivityResumed = true
    private var pendingLeaveRunnable: Runnable? = null
    private var pendingFocusRunnable: Runnable? = null

    private var cachedStatusBarService: Any? = null
    private var cachedCollapseMethod: java.lang.reflect.Method? = null
    private var isStatusBarMethodResolved = false

    private fun unsealHiddenApis() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            try {
                val forName = Class::class.java.getDeclaredMethod("forName", String::class.java)
                val getDeclaredMethod = Class::class.java.getDeclaredMethod(
                    "getDeclaredMethod",
                    String::class.java,
                    arrayOf<Class<*>>()::class.java
                )
                val vmRuntimeClass = forName.invoke(null, "dalvik.system.VMRuntime") as Class<*>
                val getRuntime = getDeclaredMethod.invoke(vmRuntimeClass, "getRuntime", null) as java.lang.reflect.Method
                val vmRuntime = getRuntime.invoke(null)
                val setHiddenApiExemptions = getDeclaredMethod.invoke(
                    vmRuntimeClass,
                    "setHiddenApiExemptions",
                    arrayOf(arrayOf<String>()::class.java)
                ) as java.lang.reflect.Method
                setHiddenApiExemptions.invoke(vmRuntime, arrayOf("L"))
            } catch (_: Throwable) {
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        instance = this
        unsealHiddenApis()
        // Always prevent screenshots and recents preview thumbnail across the entire app
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)

        // Automatically re-hide navigation bar whenever system UI visibility changes (e.g. user swiped up)
        @Suppress("DEPRECATION")
        window.decorView.setOnSystemUiVisibilityChangeListener { visibility ->
            if (examActive) {
                if (isKeyboardVisible()) {
                    // Keyboard sedang digunakan siswa untuk mengetik di CBT! Jangan ganggu!
                    return@setOnSystemUiVisibilityChangeListener
                }
                if ((visibility and View.SYSTEM_UI_FLAG_HIDE_NAVIGATION) == 0) {
                    mainHandler.postDelayed({
                        if (examActive && !isKeyboardVisible()) {
                            applyImmersiveMode()
                        }
                    }, 300L)
                }
            }
        }

        // Android 13+ (API 33+) Predictive Back interceptor: consume Back completely during exam
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            onBackInvokedDispatcher.registerOnBackInvokedCallback(
                OnBackInvokedDispatcher.PRIORITY_DEFAULT
            ) {
                if (examActive) {
                    applyImmersiveMode()
                } else {
                    finish()
                }
            }
        }
    }

    override fun dispatchTouchEvent(ev: MotionEvent): Boolean {
        if (examActive && !wifiSettingsSessionActive) {
            val y = ev.rawY

            // Segera tutup status bar jika ada gestur sentuh dari tepi atas
            if (ev.action == MotionEvent.ACTION_DOWN && y < 60f) {
                collapseStatusBarPanels()
                applyImmersiveMode()
            }
        }
        return super.dispatchTouchEvent(ev)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "enableExamLock" -> {
                    val reqPin = call.argument<Boolean>("requirePinning") ?: true
                    val blockShot = call.argument<Boolean>("blockScreenshots") ?: true
                    enableExamLock(reqPin, blockShot)
                    result.success(getSecurityStatusMap())
                }
                "disableExamLock" -> {
                    disableExamLock()
                    result.success(true)
                }
                "exitApp" -> {
                    disableExamLock()
                    try {
                        android.widget.Toast.makeText(applicationContext, "Ujian selesai. Dikeluarkan oleh Pengawas.", android.widget.Toast.LENGTH_SHORT).show()
                    } catch (_: Exception) {}

                    // 1. Lepaskan sematan layar secara langsung
                    try {
                        stopLockTask()
                    } catch (_: Exception) {}

                    // 2. Luncurkan Home Screen (Layar Utama HP) agar OS Android langsung berpindah tampilan keluar dari sematan
                    try {
                        val homeIntent = Intent(Intent.ACTION_MAIN).apply {
                            addCategory(Intent.CATEGORY_HOME)
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                        }
                        startActivity(homeIntent)
                    } catch (_: Exception) {}

                    // 3. Selesaikan dan bersihkan task aplikasi dari sistem secara mulus
                    mainHandler.postDelayed({
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                                finishAndRemoveTask()
                            } else {
                                finishAffinity()
                            }
                        } catch (_: Exception) {
                            try { finishAffinity() } catch (_: Exception) { finish() }
                        }
                    }, 80L)
                    result.success(true)
                }
                "unlockViolation" -> {
                    pinningGraceUntilMs = SystemClock.elapsedRealtime() + 15000L
                    if (examActive) {
                        val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager?
                        val lockState = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            am?.lockTaskModeState ?: ActivityManager.LOCK_TASK_MODE_NONE
                        } else {
                            ActivityManager.LOCK_TASK_MODE_NONE
                        }
                        if (lockState == ActivityManager.LOCK_TASK_MODE_NONE) {
                            try {
                                startLockTask()
                            } catch (_: Exception) {}
                        }
                        applyImmersiveMode()
                    }
                    result.success(true)
                }
                "getSecurityStatus" -> {
                    result.success(getSecurityStatusMap())
                }
                "triggerViolationAlarm" -> {
                    triggerAlarmSound()
                    result.success(true)
                }
                "reapplyImmersive" -> {
                    applyImmersiveMode()
                    result.success(true)
                }
                "openWifiSettings" -> {
                    result.success(openWifiSettingsSafely())
                }
                "scanWifiNetworks" -> {
                    ensureWifiScanningPermission()
                    result.success(getWifiScanResultsList())
                }
                "getCurrentWifiInfo" -> {
                    result.success(getCurrentWifiInfoMap())
                }
                "connectToWifi" -> {
                    val ssid = call.argument<String>("ssid") ?: ""
                    val pass = call.argument<String>("password") ?: ""
                    connectToWifiNetwork(ssid, pass) { success, message ->
                        result.success(mapOf("success" to success, "message" to message))
                    }
                }
                "disconnectWifi" -> {
                    result.success(disconnectActiveWifi())
                }
                "resetNetworkRoute" -> {
                    try {
                        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager?
                        activeNetworkCallback?.let {
                            try { cm?.unregisterNetworkCallback(it) } catch (_: Exception) {}
                            activeNetworkCallback = null
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            cm?.bindProcessToNetwork(null)
                        }
                        result.success(true)
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }
                "setWifiDialogActive" -> {
                    val active = call.argument<Boolean>("active") ?: false
                    wifiSettingsSessionActive = active
                    isWifiSessionActive = active
                    if (active) {
                        pinningGraceUntilMs = SystemClock.elapsedRealtime() + 300000L
                        pendingLeaveRunnable?.let { mainHandler.removeCallbacks(it) }
                        pendingLeaveRunnable = null
                        pendingFocusRunnable?.let { mainHandler.removeCallbacks(it) }
                        pendingFocusRunnable = null
                    } else {
                        pinningGraceUntilMs = SystemClock.elapsedRealtime() + 10000L
                        if (examActive) {
                            applyImmersiveMode()
                        }
                    }
                    result.success(true)
                }
                "openAccessibilitySettings" -> {
                    try {
                        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                        result.success(true)
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun enableExamLock(reqPin: Boolean, blockScreenshots: Boolean) {
        examActive = true
        isExamSessionActive = true
        requirePinning = true
        blockScreenshotsEnabled = blockScreenshots
        pinningGraceUntilMs = SystemClock.elapsedRealtime() + 30000L

        if (blockScreenshots) {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED
                or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
                or WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
            )
        }
        applyImmersiveMode()
        registerScreenPowerWatchdog()

        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val adminComponent = ComponentName(this, ExamDeviceAdminReceiver::class.java)

        if (dpm.isDeviceOwnerApp(packageName)) {
            dpm.setLockTaskPackages(adminComponent, arrayOf(packageName))
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                dpm.setLockTaskFeatures(adminComponent, DevicePolicyManager.LOCK_TASK_FEATURE_NONE)
            }
        }

        // Kiosk LockTask / Screen Pinning:
        // Aktifkan startLockTask() agar sistem Android secara native mengunci status bar (anti tarik notifikasi),
        // menonaktifkan tombol Home, dan menghilangkan tombol Overview/Recent Apps.
        val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager?
        val currentLockState = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            am?.lockTaskModeState ?: ActivityManager.LOCK_TASK_MODE_NONE
        } else {
            ActivityManager.LOCK_TASK_MODE_NONE
        }

        if (currentLockState == ActivityManager.LOCK_TASK_MODE_NONE) {
            try {
                startLockTask()
            } catch (_: Exception) {
            }
        }

        // Segera tutup banner instruksi pelepasan sematan sistem bawaan Android
        mainHandler.postDelayed({
            try {
                @Suppress("DEPRECATION")
                sendBroadcast(Intent(Intent.ACTION_CLOSE_SYSTEM_DIALOGS))
                collapseStatusBarPanels()
                applyImmersiveMode()
            } catch (_: Exception) {}
        }, 120L)
        mainHandler.postDelayed({
            try {
                @Suppress("DEPRECATION")
                sendBroadcast(Intent(Intent.ACTION_CLOSE_SYSTEM_DIALOGS))
                collapseStatusBarPanels()
                applyImmersiveMode()
            } catch (_: Exception) {}
        }, 400L)

        // Mute notification, ring, and system sound streams so incoming messages do not chime or vibrate
        try {
            val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager?
            audio?.let {
                it.setStreamVolume(AudioManager.STREAM_NOTIFICATION, 0, 0)
                it.setStreamVolume(AudioManager.STREAM_RING, 0, 0)
                it.setStreamVolume(AudioManager.STREAM_SYSTEM, 0, 0)
            }
        } catch (_: Exception) {}

        mainHandler.removeCallbacks(examStatusBarGuardRunnable)
        mainHandler.post(examStatusBarGuardRunnable)

        registerDisplayWatchdog()
    }

    private fun disableExamLock() {
        examActive = false
        isExamSessionActive = false
        mainHandler.removeCallbacks(examStatusBarGuardRunnable)
        pendingLeaveRunnable?.let { mainHandler.removeCallbacks(it) }
        pendingLeaveRunnable = null
        pendingFocusRunnable?.let { mainHandler.removeCallbacks(it) }
        pendingFocusRunnable = null
        clearWifiSettingsState()
        unregisterDisplayWatchdog()
        unregisterScreenPowerWatchdog()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(false)
            setTurnScreenOn(false)
        } else {
            @Suppress("DEPRECATION")
            window.clearFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED
                or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
                or WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
            )
        }
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        try {
            stopLockTask()
        } catch (_: Exception) {
        }
        mainHandler.postDelayed({
            try {
                stopLockTask()
            } catch (_: Exception) {}
        }, 120L)
        restoreSystemBars()
    }

    private fun isKeyboardVisible(): Boolean {
        try {
            val insets = androidx.core.view.ViewCompat.getRootWindowInsets(window.decorView)
            if (insets?.isVisible(WindowInsetsCompat.Type.ime()) == true) {
                return true
            }
        } catch (_: Throwable) {}

        // Fallback deteksi geometrik untuk segala versi Android & custom ROM
        try {
            val r = Rect()
            window.decorView.getWindowVisibleDisplayFrame(r)
            val screenHeight = window.decorView.rootView.height
            if (screenHeight > 0) {
                val keypadHeight = screenHeight - r.bottom
                if (keypadHeight > screenHeight * 0.15) {
                    return true
                }
            }
        } catch (_: Throwable) {}

        return false
    }

    fun applyImmersiveMode() {
        runOnUiThread {
            try {
                // Jika keyboard virtual sedang digunakan siswa untuk mengetik di CBT, jangan sembunyikan
                if (isKeyboardVisible()) {
                    return@runOnUiThread
                }

                val controller = WindowInsetsControllerCompat(window, window.decorView)
                // HANYA sembunyikan status bar dan nav bar, JANGAN sembunyikan IME (Keyboard)
                controller.hide(WindowInsetsCompat.Type.statusBars() or WindowInsetsCompat.Type.navigationBars())
                controller.systemBarsBehavior =
                    WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE

                @Suppress("DEPRECATION")
                window.decorView.systemUiVisibility = (
                    View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                    or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_FULLSCREEN
                )

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    try {
                        val realW: Int
                        val realH: Int
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                            val bounds = windowManager.currentWindowMetrics.bounds
                            realW = bounds.width()
                            realH = bounds.height()
                        } else {
                            val realMetrics = android.util.DisplayMetrics()
                            @Suppress("DEPRECATION")
                            windowManager.defaultDisplay.getRealMetrics(realMetrics)
                            realW = realMetrics.widthPixels
                            realH = realMetrics.heightPixels
                        }
                        val topRect = Rect(0, 0, realW, 220)
                        val botRect = Rect(0, realH - 220, realW, realH)
                        window.decorView.systemGestureExclusionRects = listOf(topRect, botRect)
                    } catch (_: Throwable) {
                    }
                }
            } catch (_: Exception) {
            }
        }
    }

    private fun restoreSystemBars() {
        runOnUiThread {
            try {
                WindowCompat.setDecorFitsSystemWindows(window, true)
                val controller = WindowInsetsControllerCompat(window, window.decorView)
                controller.show(WindowInsetsCompat.Type.systemBars())
                controller.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_DEFAULT

                @Suppress("DEPRECATION")
                window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_VISIBLE

                @Suppress("DEPRECATION")
                window.clearFlags(
                    WindowManager.LayoutParams.FLAG_FULLSCREEN
                    or WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
                )

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    try {
                        window.decorView.systemGestureExclusionRects = emptyList()
                    } catch (_: Throwable) {
                    }
                }
            } catch (_: Exception) {
            }
        }
    }

    private fun getSecurityStatusMap(): Map<String, Any> {
        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val lockState = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            am.lockTaskModeState
        } else {
            ActivityManager.LOCK_TASK_MODE_NONE
        }

        val dm = getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
        val externalDisplays = dm.displays.count { it.displayId != Display.DEFAULT_DISPLAY }

        val bm = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        val batteryPct = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)

        val multiWindow = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            isInMultiWindowMode
        } else {
            false
        }

        val isPinned = (lockState != ActivityManager.LOCK_TASK_MODE_NONE)

        val wifiStatus = getWifiStatusPair()

        return mapOf(
            "isDeviceOwner" to dpm.isDeviceOwnerApp(packageName),
            "lockTaskState" to lockState,
            "isPinned" to isPinned,
            "isInMultiWindow" to multiWindow,
            "externalDisplayCount" to externalDisplays,
            "batteryLevel" to batteryPct,
            "wifiConnected" to wifiStatus.first,
            "wifiEnabled" to wifiStatus.second,
            "isWifiSettingsActive" to wifiSettingsSessionActive,
            "isAccessibilityRunning" to false
        )
    }

    private fun getWifiStatusPair(): Pair<Boolean, Boolean> {
        var connected = false
        var enabled = false

        val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager?
        if (wm != null) {
            try {
                enabled = wm.isWifiEnabled
            } catch (_: Exception) {
            }
        }

        try {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager?
            if (cm != null) {
                // Periksa seluruh network interface yang aktif, bukan hanya default gateway
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    val allNets = cm.allNetworks
                    for (net in allNets) {
                        val caps = cm.getNetworkCapabilities(net)
                        if (caps != null && caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) {
                            connected = true
                            break
                        }
                    }
                } else {
                    @Suppress("DEPRECATION")
                    val info = cm.getNetworkInfo(ConnectivityManager.TYPE_WIFI)
                    if (info != null && info.isConnected) {
                        connected = true
                    }
                }
            }
        } catch (_: Exception) {
        }

        // Jika ConnectivityManager belum mengalihkan default route (misal router CBT offline tanpa internet),
        // periksa status koneksi radio Wi-Fi secara langsung dari WifiManager
        if (!connected && wm != null) {
            try {
                @Suppress("DEPRECATION")
                val winfo = wm.connectionInfo
                if (winfo != null) {
                    val suppState = winfo.supplicantState
                    val isAssociated = (suppState == SupplicantState.COMPLETED)
                    val hasIp = (winfo.ipAddress != 0)
                    val validNetId = (winfo.networkId != -1)
                    val rawSsid = winfo.ssid ?: ""
                    val hasValidSsid = rawSsid.isNotEmpty() && rawSsid != "<unknown ssid>"

                    if (isAssociated && (hasIp || validNetId || hasValidSsid)) {
                        connected = true
                    }
                }
            } catch (_: Exception) {
            }
        }

        if (connected) {
            enabled = true
        }

        return Pair(connected, enabled)
    }

    private val examStatusBarGuardRunnable = object : Runnable {
        override fun run() {
            if (examActive && !wifiSettingsSessionActive) {
                if (!isActivityResumed) {
                    bringExamToFront(forceActivityLaunch = true)
                } else if (!isKeyboardVisible()) {
                    applyImmersiveMode()
                }

                // Pengawal Integritas Sematan Layar (Screen Pinning / Lock Task):
                if (requirePinning) {
                    val now = SystemClock.elapsedRealtime()
                    if (now > pinningGraceUntilMs) {
                        val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager?
                        val lockState = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            am?.lockTaskModeState ?: ActivityManager.LOCK_TASK_MODE_NONE
                        } else {
                            ActivityManager.LOCK_TASK_MODE_NONE
                        }
                        if (lockState == ActivityManager.LOCK_TASK_MODE_NONE) {
                            try {
                                startLockTask()
                            } catch (_: Exception) {}
                            bringExamToFront()
                            if (!isKeyboardVisible()) {
                                applyImmersiveMode()
                            }
                            notifyViolation("unpinned", "Peringatan: Peserta mencoba melepas sematan layar (unpin)!")
                        }
                    }
                }

                // Pengawal Anti Layar Terbagi (Split-Screen), Jendela Mengambang (Floating Window) & PiP
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    try {
                        if (isInMultiWindowMode) {
                            bringExamToFront(forceActivityLaunch = true)
                            applyImmersiveMode()
                            notifyViolation("multi_window", "Dilarang menggunakan mode Split-Screen / Layar Terbagi selama ujian!")
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && isInPictureInPictureMode) {
                            bringExamToFront(forceActivityLaunch = true)
                            applyImmersiveMode()
                            notifyViolation("floating_window", "Dilarang menggunakan mode Jendela Mengambang (Picture-in-Picture)!")
                        }
                    } catch (_: Exception) {}
                }

                mainHandler.postDelayed(this, 1000L)
            }
        }
    }

    private val statusBarGuardRunnable = object : Runnable {
        override fun run() {
            if (wifiSettingsSessionActive) {
                collapseStatusBarPanels()
                mainHandler.postDelayed(this, 500L)
            }
        }
    }

    private fun collapseStatusBarPanels() {
        try {
            if (!isStatusBarMethodResolved) {
                isStatusBarMethodResolved = true
                cachedStatusBarService = getSystemService("statusbar")
                val statusBarManager = Class.forName("android.app.StatusBarManager")
                val methods = arrayOf("collapsePanels", "collapse")
                for (m in methods) {
                    try {
                        val method = statusBarManager.getMethod(m)
                        method.isAccessible = true
                        cachedCollapseMethod = method
                        break
                    } catch (_: Throwable) {
                    }
                }
            }
            val service = cachedStatusBarService ?: getSystemService("statusbar")
            cachedCollapseMethod?.invoke(service)
        } catch (_: Throwable) {
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            try {
                @Suppress("DEPRECATION")
                sendBroadcast(Intent(Intent.ACTION_CLOSE_SYSTEM_DIALOGS))
            } catch (_: Throwable) {
            }
        }
    }

    private fun clearWifiSettingsState() {
        wifiSettingsSessionActive = false
        isWifiSessionActive = false
        wifiSettingsReturnedCleanly = false
        wifiSettingsSingleTaskQuirk = false
        wifiSettingsTimeoutRunnable?.let { mainHandler.removeCallbacks(it) }
        wifiSettingsTimeoutRunnable = null
        mainHandler.removeCallbacks(statusBarGuardRunnable)
    }

    fun bringExamToFront(forceActivityLaunch: Boolean = false) {
        try {
            val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager?
            am?.moveTaskToFront(taskId, ActivityManager.MOVE_TASK_WITH_HOME)
        } catch (_: Exception) {
        }
        if (!isActivityResumed || forceActivityLaunch) {
            val intent = Intent(this, MainActivity::class.java).apply {
                addFlags(
                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
                )
            }
            try {
                startActivity(intent)
            } catch (_: Exception) {
            }
        }
        if (!isKeyboardVisible()) {
            applyImmersiveMode()
        }
        collapseStatusBarPanels()
    }

    private fun openWifiSettingsSafely(): Boolean {
        val candidates = mutableListOf<Intent>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            candidates.add(Intent(Settings.Panel.ACTION_WIFI))
        }
        candidates.add(Intent(Settings.ACTION_WIFI_SETTINGS))

        var chosen: Intent? = null
        for (candidate in candidates) {
            if (candidate.resolveActivity(packageManager) != null) {
                chosen = candidate
                break
            }
        }
        if (chosen == null) {
            return false
        }

        clearWifiSettingsState()
        wifiSettingsSessionActive = true
        isWifiSessionActive = true
        wifiSettingsOpenedAtMs = SystemClock.elapsedRealtime()
        pinningGraceUntilMs = wifiSettingsOpenedAtMs + 4000L
        mainHandler.post(statusBarGuardRunnable)

        if (examActive) {
            try {
                stopLockTask()
            } catch (_: Exception) {
            }
        }

        val timeoutTask = Runnable {
            if (examActive && wifiSettingsSessionActive) {
                clearWifiSettingsState()
                notifyViolation(
                    "left_wifi_settings",
                    "Peserta terlalu lama meninggalkan ujian atau membuka halaman lain di luar pengaturan WiFi."
                )
                bringExamToFront()
            }
        }
        wifiSettingsTimeoutRunnable = timeoutTask
        mainHandler.postDelayed(timeoutTask, WIFI_SETTINGS_TIMEOUT_MS)

        return try {
            @Suppress("DEPRECATION")
            startActivityForResult(chosen, REQ_WIFI_SETTINGS)
            true
        } catch (_: Exception) {
            clearWifiSettingsState()
            if (examActive) {
                enableExamLock(requirePinning, blockScreenshotsEnabled)
            }
            false
        }
    }

    private var activeNetworkCallback: ConnectivityManager.NetworkCallback? = null

    private fun ensureWifiScanningPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val permissions = mutableListOf<String>()
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
                permissions.add(Manifest.permission.ACCESS_FINE_LOCATION)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                if (ContextCompat.checkSelfPermission(this, Manifest.permission.NEARBY_WIFI_DEVICES) != PackageManager.PERMISSION_GRANTED) {
                    permissions.add(Manifest.permission.NEARBY_WIFI_DEVICES)
                }
            }
            if (permissions.isNotEmpty()) {
                ActivityCompat.requestPermissions(this, permissions.toTypedArray(), 9911)
            }
        }
    }

    private fun disconnectActiveWifi(): Boolean {
        return try {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager?
            activeNetworkCallback?.let {
                try { cm?.unregisterNetworkCallback(it) } catch (_: Exception) {}
                activeNetworkCallback = null
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                cm?.bindProcessToNetwork(null)
            }
            val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager?
            @Suppress("DEPRECATION")
            wm?.disconnect() ?: false
        } catch (_: Exception) {
            false
        }
    }

    private fun connectToWifiNetwork(ssid: String, pass: String, callback: (Boolean, String) -> Unit) {
        val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager?
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager?
        if (wm == null || cm == null) {
            callback(false, "Layanan WiFi tidak tersedia pada perangkat ini.")
            return
        }

        try {
            if (!wm.isWifiEnabled) {
                @Suppress("DEPRECATION")
                wm.isWifiEnabled = true
            }
        } catch (_: Exception) {
        }

        val cleanSsid = ssid.trim()
        val cleanPass = pass.trim()
        if (cleanSsid.isEmpty()) {
            callback(false, "Nama jaringan (SSID) tidak boleh kosong.")
            return
        }

        // Bersihkan state callback jaringan lama dan pastikan routing proses kembali ke default
        activeNetworkCallback?.let {
            try { cm.unregisterNetworkCallback(it) } catch (_: Exception) {}
            activeNetworkCallback = null
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try { cm.bindProcessToNetwork(null) } catch (_: Exception) {}
        }

        // Jeda LockTask sementara agar sistem Android mengizinkan dialog/persetujuan jaringan Wi-Fi
        val wasExamActive = examActive
        if (wasExamActive) {
            try { stopLockTask() } catch (_: Exception) {}
            pinningGraceUntilMs = SystemClock.elapsedRealtime() + 25000L
        }

        var responded = false
        fun finishWithResult(success: Boolean, message: String) {
            if (responded) return
            responded = true
            activeNetworkCallback?.let {
                try { cm.unregisterNetworkCallback(it) } catch (_: Exception) {}
                activeNetworkCallback = null
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                try { cm.bindProcessToNetwork(null) } catch (_: Exception) {}
            }
            if (wasExamActive) {
                mainHandler.postDelayed({
                    if (examActive) {
                        try {
                            val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
                            if (dpm.isDeviceOwnerApp(packageName)) {
                                startLockTask()
                            }
                        } catch (_: Exception) {}
                        applyImmersiveMode()
                    }
                }, 600L)
            }
            mainHandler.post { callback(success, message) }
        }

        // Tier A: Jaringan yang sudah pernah disimpan di perangkat
        try {
            @Suppress("DEPRECATION")
            val existing = wm.configuredNetworks?.find {
                val s = it.SSID?.trim() ?: ""
                s == "\"$cleanSsid\"" || s == cleanSsid
            }
            if (existing != null) {
                if (cleanPass.isNotEmpty()) {
                    existing.preSharedKey = "\"$cleanPass\""
                    try { wm.updateNetwork(existing) } catch (_: Exception) {}
                }
                try { wm.disconnect() } catch (_: Exception) {}
                try { wm.enableNetwork(existing.networkId, true) } catch (_: Exception) {}
                try { wm.reconnect() } catch (_: Exception) {}
            }
        } catch (_: Exception) {}

        // Tier B: Daftarkan via WifiConfiguration (kompatibilitas luas)
        try {
            @Suppress("DEPRECATION")
            val conf = WifiConfiguration().apply {
                SSID = "\"$cleanSsid\""
                if (cleanPass.isNotEmpty()) {
                    preSharedKey = "\"$cleanPass\""
                    allowedProtocols.set(WifiConfiguration.Protocol.RSN)
                    allowedProtocols.set(WifiConfiguration.Protocol.WPA)
                    allowedKeyManagement.set(WifiConfiguration.KeyMgmt.WPA_PSK)
                    allowedPairwiseCiphers.set(WifiConfiguration.PairwiseCipher.CCMP)
                    allowedPairwiseCiphers.set(WifiConfiguration.PairwiseCipher.TKIP)
                    allowedGroupCiphers.set(WifiConfiguration.GroupCipher.WEP40)
                    allowedGroupCiphers.set(WifiConfiguration.GroupCipher.WEP104)
                    allowedGroupCiphers.set(WifiConfiguration.GroupCipher.CCMP)
                    allowedGroupCiphers.set(WifiConfiguration.GroupCipher.TKIP)
                } else {
                    allowedKeyManagement.set(WifiConfiguration.KeyMgmt.NONE)
                }
                status = WifiConfiguration.Status.ENABLED
            }
            @Suppress("DEPRECATION")
            val netId = wm.addNetwork(conf)
            if (netId != -1) {
                @Suppress("DEPRECATION")
                wm.disconnect()
                @Suppress("DEPRECATION")
                wm.enableNetwork(netId, true)
                @Suppress("DEPRECATION")
                wm.reconnect()
            }
        } catch (_: Exception) {}

        // Tier C: WifiNetworkSuggestion (standar resmi Android 10+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                val sugBuilder = WifiNetworkSuggestion.Builder()
                    .setSsid(cleanSsid)
                    .setIsAppInteractionRequired(false)
                    .setIsUserInteractionRequired(false)

                if (cleanPass.isNotEmpty() && cleanPass.length >= 8) {
                    try {
                        sugBuilder.setWpa2Passphrase(cleanPass)
                    } catch (_: Exception) {}
                }
                val sug = sugBuilder.build()
                try { wm.removeNetworkSuggestions(listOf(sug)) } catch (_: Exception) {}
                wm.addNetworkSuggestions(listOf(sug))
                try { wm.disconnect() } catch (_: Exception) {}
                try { wm.reconnect() } catch (_: Exception) {}
            } catch (_: Exception) {}
        }

        // Tier D: WifiNetworkSpecifier (koneksi langsung Android 10+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                val specBuilder = WifiNetworkSpecifier.Builder().setSsid(cleanSsid)
                if (cleanPass.isNotEmpty() && cleanPass.length >= 8) {
                    try {
                        specBuilder.setWpa2Passphrase(cleanPass)
                    } catch (_: Exception) {}
                }
                val specifier = specBuilder.build()
                val request = NetworkRequest.Builder()
                    .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                    .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                    .setNetworkSpecifier(specifier)
                    .build()

                activeNetworkCallback?.let {
                    try { cm.unregisterNetworkCallback(it) } catch (_: Exception) {}
                }

                val networkCallback = object : ConnectivityManager.NetworkCallback() {
                    override fun onAvailable(network: Network) {
                        super.onAvailable(network)
                        // Pastikan routing proses kembali ke default sistem agar akses https://cbtpanel.mmc.biz.id tetap lancar
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            try { cm.bindProcessToNetwork(null) } catch (_: Exception) {}
                        }
                        finishWithResult(true, "Berhasil terhubung ke $cleanSsid")
                    }

                    override fun onLost(network: Network) {
                        super.onLost(network)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            try { cm.bindProcessToNetwork(null) } catch (_: Exception) {}
                        }
                    }

                    override fun onUnavailable() {
                        super.onUnavailable()
                        // Jangan langsung batalkan, beri kesempatan polling Tier A/B/C mengecek koneksi
                    }
                }
                activeNetworkCallback = networkCallback
                cm.requestNetwork(request, networkCallback)
            } catch (_: Exception) {}
        }

        // Pemantau aktif: periksa status koneksi berkala hingga 10 detik
        var checkCount = 0
        val maxChecks = 6
        fun pollStatus() {
            if (responded) return
            val cur = getCurrentWifiInfoMap()
            val connected = cur["connected"] as? Boolean ?: false
            val curSsid = (cur["ssid"] as? String ?: "").trim()

            if (connected && (curSsid.equals(cleanSsid, true) || curSsid.isNotEmpty())) {
                finishWithResult(true, "Berhasil terhubung ke $curSsid")
                return
            }

            checkCount++
            if (checkCount < maxChecks) {
                mainHandler.postDelayed({ pollStatus() }, 1500L)
            } else {
                val finalCur = getCurrentWifiInfoMap()
                val isFinalConnected = finalCur["connected"] as? Boolean ?: false
                val finalSsid = (finalCur["ssid"] as? String ?: "").trim()
                if (isFinalConnected && finalSsid.isNotEmpty()) {
                    finishWithResult(true, "Terhubung ke $finalSsid")
                } else {
                    finishWithResult(
                        false,
                        "Belum dapat terhubung otomatis. Silakan gunakan tombol 'Buka Panel Wi-Fi Cepat' di bawah."
                    )
                }
            }
        }

        mainHandler.postDelayed({ pollStatus() }, 1800L)
    }

    private fun getWifiScanResultsList(): List<Map<String, Any>> {
        val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager? ?: return emptyList()
        try {
            @Suppress("DEPRECATION")
            wm.startScan()
        } catch (_: Exception) {
        }

        val list = mutableListOf<Map<String, Any>>()
        val seen = mutableSetOf<String>()

        try {
            @Suppress("DEPRECATION")
            val results = wm.scanResults ?: emptyList()
            val sorted = results.sortedByDescending { it.level }

            for (res in sorted) {
                val s = res.SSID?.trim() ?: ""
                if (s.isEmpty() || seen.contains(s)) continue
                seen.add(s)

                val caps = res.capabilities?.uppercase() ?: ""
                val isSecured = caps.contains("WPA") || caps.contains("WEP") || caps.contains("PSK") || caps.contains("EAP")

                val sigLevel = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    wm.calculateSignalLevel(res.level)
                } else {
                    @Suppress("DEPRECATION")
                    WifiManager.calculateSignalLevel(res.level, 5)
                }

                list.add(
                    mapOf(
                        "ssid" to s,
                        "bssid" to (res.BSSID ?: ""),
                        "level" to res.level,
                        "signalLevel" to sigLevel,
                        "isSecure" to isSecured,
                        "capabilities" to (res.capabilities ?: "")
                    )
                )
            }
        } catch (_: Exception) {
        }

        return list
    }

    private fun getCurrentWifiInfoMap(): Map<String, Any?> {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager?
        val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager?

        var connected = false
        var ssid = ""
        var bssid = ""
        var ipStr = ""
        var signalLevel = 0

        try {
            if (cm != null) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    val allNets = cm.allNetworks
                    for (net in allNets) {
                        val caps = cm.getNetworkCapabilities(net)
                        if (caps != null && caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) {
                            connected = true
                            break
                        }
                    }
                } else {
                    @Suppress("DEPRECATION")
                    val info = cm.getNetworkInfo(ConnectivityManager.TYPE_WIFI)
                    if (info != null && info.isConnected) {
                        connected = true
                    }
                }
            }

            if (wm != null) {
                @Suppress("DEPRECATION")
                val winfo = wm.connectionInfo
                if (winfo != null) {
                    val suppState = winfo.supplicantState
                    val isAssociated = (suppState == SupplicantState.COMPLETED)
                    val hasIp = (winfo.ipAddress != 0)
                    val validNetId = (winfo.networkId != -1)

                    var rawSsid = winfo.ssid ?: ""
                    if (rawSsid.startsWith("\"") && rawSsid.endsWith("\"") && rawSsid.length >= 2) {
                        rawSsid = rawSsid.substring(1, rawSsid.length - 1)
                    }
                    if (rawSsid != "<unknown ssid>" && rawSsid.isNotEmpty()) {
                        ssid = rawSsid
                    }
                    if (isAssociated && (hasIp || validNetId || ssid.isNotEmpty())) {
                        connected = true
                    }

                    bssid = winfo.bssid ?: ""
                    signalLevel = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        wm.calculateSignalLevel(winfo.rssi)
                    } else {
                        @Suppress("DEPRECATION")
                        WifiManager.calculateSignalLevel(winfo.rssi, 5)
                    }
                    val ip = winfo.ipAddress
                    if (ip != 0) {
                        ipStr = String.format(
                            "%d.%d.%d.%d",
                            ip and 0xff,
                            ip shr 8 and 0xff,
                            ip shr 16 and 0xff,
                            ip shr 24 and 0xff
                        )
                    }
                }
            }
        } catch (_: Exception) {
        }

        return mapOf(
            "connected" to connected,
            "ssid" to ssid,
            "bssid" to bssid,
            "ipAddress" to ipStr,
            "signalLevel" to signalLevel
        )
    }

    private fun registerDisplayWatchdog() {
        if (displayManager != null) return
        val dm = getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
        displayManager = dm

        // Immediate check for existing wireless/HDMI displays
        if (dm.displays.any { it.displayId != Display.DEFAULT_DISPLAY }) {
            notifyViolation("external_display", "Terdeteksi layar eksternal / screen mirroring aktif.")
        }

        val listener = object : DisplayManager.DisplayListener {
            override fun onDisplayAdded(displayId: Int) {
                if (examActive && displayId != Display.DEFAULT_DISPLAY) {
                    notifyViolation("external_display", "Layar eksternal / screen mirroring baru terdeteksi.")
                }
            }

            override fun onDisplayRemoved(displayId: Int) {}
            override fun onDisplayChanged(displayId: Int) {}
        }
        displayListener = listener
        dm.registerDisplayListener(listener, null)
    }

    private fun unregisterDisplayWatchdog() {
        val dm = displayManager
        val listener = displayListener
        if (dm != null && listener != null) {
            try {
                dm.unregisterDisplayListener(listener)
            } catch (_: Exception) {
            }
        }
        displayManager = null
        displayListener = null
    }

    private var screenPowerReceiver: BroadcastReceiver? = null

    private fun registerScreenPowerWatchdog() {
        if (screenPowerReceiver != null) return
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_SCREEN_ON)
        }
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                when (intent?.action) {
                    Intent.ACTION_SCREEN_OFF -> {
                        if (examActive) {
                            notifyViolation("power_button_pressed", "Tombol power ditekan atau layar dimatikan saat ujian.")
                            wakeScreenUp()
                        }
                    }
                }
            }
        }
        screenPowerReceiver = receiver
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(receiver, filter)
            }
        } catch (_: Exception) {
            try { registerReceiver(receiver, filter) } catch (_: Exception) {}
        }
    }

    private fun unregisterScreenPowerWatchdog() {
        screenPowerReceiver?.let {
            try { unregisterReceiver(it) } catch (_: Exception) {}
            screenPowerReceiver = null
        }
    }

    private fun wakeScreenUp() {
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager?
            @Suppress("DEPRECATION")
            val wakeLock = pm?.newWakeLock(
                PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP or PowerManager.ON_AFTER_RELEASE,
                "ExamBroKu:PowerWakeLock"
            )
            wakeLock?.acquire(3000L)
            bringExamToFront()
            applyImmersiveMode()
        } catch (_: Exception) {}
    }

    private fun triggerAlarmSound() {
        try {
            if (toneGenerator == null) {
                toneGenerator = ToneGenerator(AudioManager.STREAM_ALARM, 100)
            }
            toneGenerator?.startTone(ToneGenerator.TONE_CDMA_EMERGENCY_RINGBACK, 900)
        } catch (_: Exception) {
        }
    }

    private fun notifyViolation(code: String, reason: String) {
        runOnUiThread {
            methodChannel?.invokeMethod(
                "onSecurityViolation",
                mapOf("code" to code, "reason" to reason)
            )
        }
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_WIFI_SETTINGS && wifiSettingsSessionActive) {
            val elapsed = SystemClock.elapsedRealtime() - wifiSettingsOpenedAtMs
            if (elapsed >= 350L) {
                wifiSettingsReturnedCleanly = true
                wifiSettingsSessionActive = false
                wifiSettingsTimeoutRunnable?.let { mainHandler.removeCallbacks(it) }
                wifiSettingsTimeoutRunnable = null
            } else {
                wifiSettingsSingleTaskQuirk = true
            }
        }
    }

    override fun onPause() {
        super.onPause()
        isActivityResumed = false
        if (examActive && !wifiSettingsSessionActive) {
            collapseStatusBarPanels()
            bringExamToFront()
        }
    }

    override fun onResume() {
        super.onResume()
        isActivityResumed = true

        // Accidental Back/Home/Menu touches were neutralized: cancel pending leave & focus violation
        pendingLeaveRunnable?.let {
            mainHandler.removeCallbacks(it)
            pendingLeaveRunnable = null
        }
        pendingFocusRunnable?.let {
            mainHandler.removeCallbacks(it)
            pendingFocusRunnable = null
        }

        if (!examActive) {
            clearWifiSettingsState()
            return
        }

        applyImmersiveMode()

        if (wifiSettingsReturnedCleanly) {
            clearWifiSettingsState()
            enableExamLock(requirePinning, blockScreenshotsEnabled)
            return
        }

        if (wifiSettingsSessionActive) {
            val elapsed = SystemClock.elapsedRealtime() - wifiSettingsOpenedAtMs
            val allowedReturn = wifiSettingsSingleTaskQuirk || elapsed < 1500L
            clearWifiSettingsState()
            enableExamLock(requirePinning, blockScreenshotsEnabled)
            if (!allowedReturn) {
                notifyViolation(
                    "left_wifi_settings",
                    "Peserta membuka halaman atau aplikasi lain di luar pengaturan WiFi."
                )
            }
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (!examActive) return

        if (hasFocus) {
            pendingFocusRunnable?.let {
                mainHandler.removeCallbacks(it)
                pendingFocusRunnable = null
            }
            applyImmersiveMode()
            if (requirePinning) {
                val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager?
                val lockState = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    am?.lockTaskModeState ?: ActivityManager.LOCK_TASK_MODE_NONE
                } else {
                    ActivityManager.LOCK_TASK_MODE_NONE
                }
                if (lockState == ActivityManager.LOCK_TASK_MODE_NONE) {
                    try {
                        startLockTask()
                    } catch (_: Exception) {
                    }
                }
            }
            return
        }

        // Ketika fokus hilang (siswa mencoba menarik status bar atau membuka panel lain),
        // segera tutup paksa panel status bar. Jangan ganggu keyboard virtual jika sedang aktif!
        if (!wifiSettingsSessionActive) {
            collapseStatusBarPanels()
            if (!isActivityResumed) {
                bringExamToFront(forceActivityLaunch = true)
            }
            if (!isKeyboardVisible()) {
                applyImmersiveMode()
            }
        }

        // Segera tutup dialog sistem jika siswa mencoba menahan tombol power (menu restart/matikan daya)
        try {
            @Suppress("DEPRECATION")
            sendBroadcast(Intent(Intent.ACTION_CLOSE_SYSTEM_DIALOGS))
        } catch (_: Exception) {}

        val now = SystemClock.elapsedRealtime()
        if (now < pinningGraceUntilMs || wifiSettingsSessionActive) return

        val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager?
        val lockState = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            am?.lockTaskModeState ?: ActivityManager.LOCK_TASK_MODE_NONE
        } else {
            ActivityManager.LOCK_TASK_MODE_NONE
        }

        // While Android Screen Pinning / Lock Task is actively pinned, losing focus
        // to the system's "Screen is pinned / Got It" prompt is NOT a violation.
        if (lockState != ActivityManager.LOCK_TASK_MODE_NONE) {
            return
        }

        // Debounce focus loss: accidental tap on bottom bar or transient system UI
        // must NOT immediately lock out the student!
        pendingFocusRunnable?.let { mainHandler.removeCallbacks(it) }
        val focusTask = Runnable {
            if (examActive && !hasWindowFocus()) {
                notifyViolation("focus_lost", "Fokus aplikasi ujian terganggu atau siswa mencoba membuka panel/aplikasi lain.")
            }
        }
        pendingFocusRunnable = focusTask
        mainHandler.postDelayed(focusTask, 1200L)
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (!examActive) return

        val now = SystemClock.elapsedRealtime()
        if (now < pinningGraceUntilMs) return
        if (wifiSettingsSessionActive && (now - wifiSettingsOpenedAtMs) < 1200L) return

        // Instantly bounce activity back to front so the accidental touch is neutralized
        bringExamToFront()
        applyImmersiveMode()

        // Debounce violation: do NOT trigger violation immediately on an accidental touch.
        // Only if the app actually stays left/backgrounded for > 1500ms, record violation!
        pendingLeaveRunnable?.let { mainHandler.removeCallbacks(it) }
        val checkTask = Runnable {
            if (examActive && !isActivityResumed) {
                notifyViolation("leave_attempt", "Siswa meninggalkan aplikasi ujian.")
            }
        }
        pendingLeaveRunnable = checkTask
        mainHandler.postDelayed(checkTask, 1500L)
    }

    override fun onMultiWindowModeChanged(isInMultiWindowMode: Boolean) {
        super.onMultiWindowModeChanged(isInMultiWindowMode)
        if (examActive && isInMultiWindowMode) {
            bringExamToFront()
            applyImmersiveMode()
            notifyViolation("multi_window", "Mode layar terbagi (Split-Screen) / jendela mengambang dilarang selama ujian.")
        }
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: android.content.res.Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        if (examActive && isInPictureInPictureMode) {
            bringExamToFront()
            applyImmersiveMode()
            notifyViolation("floating_window", "Mode Picture-in-Picture / Jendela Mengambang dilarang selama ujian.")
        }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (examActive) {
            when (event.keyCode) {
                KeyEvent.KEYCODE_BACK,
                KeyEvent.KEYCODE_APP_SWITCH,
                KeyEvent.KEYCODE_HOME,
                KeyEvent.KEYCODE_MENU,
                KeyEvent.KEYCODE_SEARCH,
                KeyEvent.KEYCODE_WINDOW,
                KeyEvent.KEYCODE_ALL_APPS,
                KeyEvent.KEYCODE_VOLUME_UP,
                KeyEvent.KEYCODE_VOLUME_DOWN,
                KeyEvent.KEYCODE_VOLUME_MUTE -> {
                    applyImmersiveMode()
                    return true
                }
            }
        }
        return super.dispatchKeyEvent(event)
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (examActive) {
            when (keyCode) {
                KeyEvent.KEYCODE_BACK,
                KeyEvent.KEYCODE_APP_SWITCH,
                KeyEvent.KEYCODE_HOME,
                KeyEvent.KEYCODE_MENU,
                KeyEvent.KEYCODE_SEARCH,
                KeyEvent.KEYCODE_WINDOW,
                KeyEvent.KEYCODE_ALL_APPS,
                KeyEvent.KEYCODE_VOLUME_UP,
                KeyEvent.KEYCODE_VOLUME_DOWN,
                KeyEvent.KEYCODE_VOLUME_MUTE -> {
                    applyImmersiveMode()
                    return true
                }
            }
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun onKeyUp(keyCode: Int, event: KeyEvent?): Boolean {
        if (examActive) {
            when (keyCode) {
                KeyEvent.KEYCODE_BACK,
                KeyEvent.KEYCODE_APP_SWITCH,
                KeyEvent.KEYCODE_HOME,
                KeyEvent.KEYCODE_MENU,
                KeyEvent.KEYCODE_SEARCH,
                KeyEvent.KEYCODE_WINDOW,
                KeyEvent.KEYCODE_ALL_APPS,
                KeyEvent.KEYCODE_VOLUME_UP,
                KeyEvent.KEYCODE_VOLUME_DOWN,
                KeyEvent.KEYCODE_VOLUME_MUTE -> {
                    applyImmersiveMode()
                    return true
                }
            }
        }
        return super.onKeyUp(keyCode, event)
    }

    override fun onKeyLongPress(keyCode: Int, event: KeyEvent?): Boolean {
        if (examActive) {
            applyImmersiveMode()
            return true
        }
        return super.onKeyLongPress(keyCode, event)
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        if (examActive) {
            // Silently absorb accidental Back tap without triggering violation
            applyImmersiveMode()
            return
        }
        finish()
    }

    override fun onDestroy() {
        pendingLeaveRunnable?.let { mainHandler.removeCallbacks(it) }
        pendingLeaveRunnable = null
        pendingFocusRunnable?.let { mainHandler.removeCallbacks(it) }
        pendingFocusRunnable = null
        clearWifiSettingsState()
        unregisterDisplayWatchdog()
        unregisterScreenPowerWatchdog()
        try {
            toneGenerator?.release()
        } catch (_: Exception) {
        }
        toneGenerator = null
        if (instance === this) {
            instance = null
        }
        super.onDestroy()
    }
}
