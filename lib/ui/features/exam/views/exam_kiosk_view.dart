import 'dart:async';

import 'package:exambroku_android/data/repositories/exam_config_repository.dart';
import 'package:exambroku_android/data/services/crypto_service.dart';
import 'package:exambroku_android/data/services/native_security_service.dart';
import 'package:exambroku_android/data/services/remote_control_service.dart';
import 'package:exambroku_android/domain/models/exam_config.dart';
import 'package:exambroku_android/ui/core/admin_pin_dialog.dart';
import 'package:exambroku_android/ui/core/mmc_footer.dart';
import 'package:exambroku_android/ui/features/exam/widgets/in_app_wifi_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

class ExamKioskView extends StatefulWidget {
  const ExamKioskView({
    super.key,
    required this.config,
    required this.securityService,
    this.repository,
    this.onConfigSynced,
  });

  final ExamConfig config;
  final NativeSecurityService securityService;
  final ExamConfigRepository? repository;
  final ValueChanged<ExamConfig>? onConfigSynced;

  @override
  State<ExamKioskView> createState() => _ExamKioskViewState();
}

class _ExamKioskViewState extends State<ExamKioskView>
    with WidgetsBindingObserver {
  final _pinGuard = PinAttemptGuard();
  final _remoteService = RemoteControlService();
  late ExamConfig _activeConfig;
  late final WebViewController _webController;
  late final Uri _targetUri;

  Timer? _statusTimer;
  Timer? _remoteTimer;
  Timer? _lifecycleViolationTimer;
  bool _remoteBusy = false;
  bool _isLoading = true;
  String? _webErrorText;
  bool _isPromptingAdmin = false;
  bool _isWifiDialogOpen = false;
  bool _isExiting = false;

  String? _violationReason;
  int _violationCount = 0;
  DateTime _now = DateTime.now();
  int _batteryLevel = -1;
  bool _isPinned = false;
  bool _isDeviceOwner = false;
  bool _wifiConnected = false;
  bool _awaitingWifiReturn = false;
  DateTime _graceUntil = DateTime.now().add(const Duration(seconds: 8));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _activeConfig = widget.config;

    final validated = UrlPortHelper.validateAndBuildUri(
      protocol: _activeConfig.protocol,
      host: _activeConfig.host,
      port: _activeConfig.port,
      path: _activeConfig.path,
    );
    _targetUri = validated.uri!;

    _initWebView();
    _engageLockdown();
  }

  void _initWebView() {
    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (!mounted) return;
            setState(() {
              _isLoading = true;
              _webErrorText = null;
            });
          },
          onPageFinished: (_) async {
            if (!mounted) return;
            if (widget.config.blockCopyPaste) {
              await _injectAntiCopyJs();
            }
            if (mounted) {
              setState(() => _isLoading = false);
            }
          },
          onWebResourceError: (err) {
            if (!mounted || !(err.isForMainFrame ?? true)) return;
            setState(() {
              _isLoading = false;
              _webErrorText =
                  'Halaman ujian belum dapat dimuat (kode: ${err.errorCode}).';
            });
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (UrlPortHelper.isNavigationAllowed(uri, widget.config)) {
              return NavigationDecision.navigate;
            }
            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(_targetUri);
  }

  Future<void> _injectAntiCopyJs() async {
    const js = '''
      (function() {
        var style = document.createElement('style');
        style.innerHTML = 'body { -webkit-touch-callout: none; } input, textarea, select, [contenteditable="true"], .form-control { -webkit-user-select: auto !important; user-select: auto !important; pointer-events: auto !important; }';
        document.head.appendChild(style);
        document.addEventListener('contextmenu', function(e) {
          var tag = (e.target && e.target.tagName) ? e.target.tagName.toLowerCase() : '';
          if (tag !== 'input' && tag !== 'textarea') { e.preventDefault(); }
        }, false);
      })();
    ''';
    try {
      await _webController.runJavaScript(js);
    } catch (_) {}
  }

  Future<void> _engageLockdown() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    widget.securityService.setViolationListener(_handleViolation);
    final status = await widget.securityService.enableExamLock(
      requirePinning: true,
      blockScreenshots: widget.config.blockScreenshots,
    );

    if (mounted) {
      setState(() {
        _isDeviceOwner = status.isDeviceOwner;
        _isPinned = status.isPinned;
        _batteryLevel = status.batteryLevel;
        _wifiConnected = status.wifiConnected;
      });
    }

    _statusTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!mounted || _isExiting) return;
      final st = await widget.securityService.getSecurityStatus();
      if (!mounted) return;

      if (_awaitingWifiReturn && !st.isWifiSettingsActive) {
        _awaitingWifiReturn = false;
      }

      final afterGrace = DateTime.now().isAfter(_graceUntil);
      if (afterGrace &&
          !st.isPinned &&
          !st.isWifiSettingsActive &&
          !_awaitingWifiReturn &&
          !_isPromptingAdmin &&
          !_isWifiDialogOpen &&
          _violationReason == null) {
        _handleViolation(
          'unpinned',
          'Mode Screen Pinning / Kiosk dinonaktifkan oleh peserta.',
        );
      }

      if (st.isInMultiWindow && _violationReason == null) {
        _handleViolation(
          'multi_window',
          'Mode layar terbagi (Split-Screen) / jendela mengambang terdeteksi.',
        );
      }

      if (st.externalDisplayCount > 0 && _violationReason == null) {
        _handleViolation(
          'external_display',
          'Layar eksternal / screen mirroring terdeteksi.',
        );
      }

      setState(() {
        _now = DateTime.now();
        _batteryLevel = st.batteryLevel;
        _isPinned = st.isPinned;
        _isDeviceOwner = st.isDeviceOwner;
        _wifiConnected = st.wifiConnected;
      });
    });

    if (_activeConfig.remoteControlEnabled) {
      _remoteTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _pollRemoteControl(),
      );
      _pollRemoteControl();
    }
  }

  DateTime _lastRemotePollAttempt = DateTime.now();

  Future<void> _pollRemoteControl() async {
    if (!mounted || _isExiting || !_activeConfig.remoteControlEnabled) {
      return;
    }
    final now = DateTime.now();
    if (_remoteBusy) {
      if (now.difference(_lastRemotePollAttempt).inSeconds > 2) {
        _remoteBusy = false; // Reset lock otomatis jika koneksi sebelumnya stall/terhambat
      } else {
        return;
      }
    }
    _lastRemotePollAttempt = now;
    _remoteBusy = true;
    try {
      final status = _violationReason != null ? 'LOCKED_VIOLATION' : 'READY';
      final lockMode = _isDeviceOwner
          ? 'DeviceOwner'
          : (_isPinned ? 'ScreenPinning' : 'FocusWatchdog');

      final resp = await _remoteService.sendHeartbeat(
        config: _activeConfig,
        status: status,
        violationCount: _violationCount,
        lastViolation: _violationReason ?? '',
        lockMode: lockMode,
      );
      if (!mounted || _isExiting || resp == null || !resp.ok) return;

      final synced = RemoteControlService.applyServerSync(_activeConfig, resp);
      if (synced != null) {
        _activeConfig = synced;
        await widget.repository?.save(synced);
        widget.onConfigSynced?.call(synced);
      }

      if (resp.command == 'FORCE_EXIT') {
        _isExiting = true;
        _statusTimer?.cancel();
        _remoteTimer?.cancel();
        widget.securityService.setViolationListener(null);

        // Kirim ACK dan Heartbeat EXITED di latar belakang
        unawaited(_remoteService.sendAck(
          config: _activeConfig,
          commandId: resp.commandId,
        ));
        unawaited(_remoteService.sendHeartbeat(
          config: _activeConfig,
          status: 'EXITED',
          violationCount: _violationCount,
          lastViolation: _violationReason ?? '',
          lockMode: _isDeviceOwner ? 'DeviceOwner' : 'ScreenPinning',
        ));

        // Keluar dari aplikasi dan kembali ke Home Screen seketika
        await widget.securityService.exitApp();
        return;
      } else if (resp.command == 'UNLOCK_VIOLATION') {
        _graceUntil = DateTime.now().add(const Duration(seconds: 15));
        if (mounted) {
          setState(() => _violationReason = null);
        }
        await widget.securityService.unlockViolation();
        unawaited(_remoteService.sendAck(
          config: _activeConfig,
          commandId: resp.commandId,
        ));
      }
    } catch (_) {
      // Ignore transient network errors during exam
    } finally {
      _remoteBusy = false;
    }
  }

  void _handleViolation(String code, String reason) {
    if (!mounted || _isExiting || _isPromptingAdmin || _isWifiDialogOpen) return;
    if (DateTime.now().isBefore(_graceUntil) && code != 'external_display') {
      return;
    }

    setState(() {
      _violationCount++;
      _violationReason = reason;
    });

    if (widget.config.alarmOnViolation) {
      widget.securityService.triggerViolationAlarm();
    }
  }

  Future<void> _openWifiSettings() async {
    if (_isExiting || _isPromptingAdmin || _isWifiDialogOpen) return;
    setState(() {
      _isWifiDialogOpen = true;
    });

    _lifecycleViolationTimer?.cancel();
    _lifecycleViolationTimer = null;
    _graceUntil = DateTime.now().add(const Duration(minutes: 5));
    await widget.securityService.setWifiDialogActive(true);
    if (!mounted) return;

    try {
      await InAppWifiDialog.show(
        context,
        securityService: widget.securityService,
        onConnectionChanged: () async {
          await widget.securityService.resetNetworkRoute();
          _remoteBusy = false;
          _pollRemoteControl();
          final st = await widget.securityService.getSecurityStatus();
          if (mounted) {
            setState(() {
              _wifiConnected = st.wifiConnected;
            });
          }
        },
      );
    } finally {
      await widget.securityService.setWifiDialogActive(false);
      await widget.securityService.resetNetworkRoute();
      if (mounted) {
        setState(() {
          _isWifiDialogOpen = false;
        });
        var st = await widget.securityService.getSecurityStatus();
        setState(() {
          _wifiConnected = st.wifiConnected;
          _isPinned = st.isPinned;
        });
        _graceUntil = DateTime.now().add(const Duration(seconds: 10));
        widget.securityService.reapplyImmersive();

        // Segera reset remote control busy flag dan kirim heartbeat ke https://cbtpanel.mmc.biz.id
        _remoteBusy = false;
        _pollRemoteControl();

        Future.delayed(const Duration(seconds: 1), () async {
          if (!mounted) return;
          st = await widget.securityService.getSecurityStatus();
          setState(() {
            _wifiConnected = st.wifiConnected;
          });
        });

        Future.delayed(const Duration(seconds: 2), () {
          if (mounted && !_isExiting) {
            _remoteBusy = false;
            _pollRemoteControl();
          }
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isExiting || _isPromptingAdmin || _isWifiDialogOpen) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (!_awaitingWifiReturn && DateTime.now().isAfter(_graceUntil)) {
        // Debounce: accidental touch on Back/Home/Menu is neutralized in Android native
        // and returns immediately. Only trigger violation if app stays in background for > 1500ms.
        _lifecycleViolationTimer?.cancel();
        _lifecycleViolationTimer = Timer(const Duration(milliseconds: 1500), () {
          if (!mounted || _isExiting || _isPromptingAdmin) return;
          _handleViolation(
            'lifecycle_leave',
            'Aplikasi ujian ditinggalkan atau dipindahkan ke latar belakang.',
          );
        });
      }
    } else if (state == AppLifecycleState.resumed) {
      // User returned immediately: cancel pending violation
      _lifecycleViolationTimer?.cancel();
      _lifecycleViolationTimer = null;
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      widget.securityService.reapplyImmersive();
      if (_awaitingWifiReturn) {
        _awaitingWifiReturn = false;
        _graceUntil = DateTime.now().add(const Duration(seconds: 6));
        widget.securityService.getSecurityStatus().then((st) {
          if (!mounted) return;
          setState(() {
            _wifiConnected = st.wifiConnected;
            _isPinned = st.isPinned;
            _isDeviceOwner = st.isDeviceOwner;
          });
        });
      }
    }
  }

  Future<void> _promptAdminExit() async {
    if (_isPromptingAdmin || _isExiting) return;
    _isPromptingAdmin = true;
    try {
      final verified = await AdminPinDialog.show(
        context,
        config: _activeConfig,
        guard: _pinGuard,
        title: 'Keluar Mode Ujian (Admin)',
        subtitle:
            'Masukkan Kode Admin untuk menghentikan ujian dan membuka kunci perangkat.',
      );
      if (!verified || !mounted) return;

      _isExiting = true;
      await _cleanupAndExit();
    } finally {
      _isPromptingAdmin = false;
    }
  }

  Future<void> _promptAdminUnlockViolation() async {
    if (_isPromptingAdmin || _isExiting) return;
    _isPromptingAdmin = true;
    try {
      final verified = await AdminPinDialog.show(
        context,
        config: _activeConfig,
        guard: _pinGuard,
        title: 'Buka Kunci Pelanggaran (Admin)',
        subtitle:
            'Masukkan Kode Admin untuk melanjutkan ujian setelah pelanggaran.',
      );
      if (!verified || !mounted) return;

      _graceUntil = DateTime.now().add(const Duration(seconds: 15));
      await widget.securityService.unlockViolation();
      if (mounted) {
        setState(() => _violationReason = null);
      }
    } finally {
      _isPromptingAdmin = false;
    }
  }

  Future<void> _cleanupAndExit() async {
    _statusTimer?.cancel();
    _remoteTimer?.cancel();
    if (_activeConfig.remoteControlEnabled) {
      await _remoteService.sendHeartbeat(
        config: _activeConfig,
        status: 'EXITED',
        violationCount: _violationCount,
        lastViolation: _violationReason ?? '',
        lockMode: _isDeviceOwner ? 'DeviceOwner' : 'ScreenPinning',
      );
    }
    widget.securityService.setViolationListener(null);
    if (_activeConfig.clearCacheOnExit) {
      try {
        await _webController.clearCache();
        await _webController.clearLocalStorage();
        await WebViewCookieManager().clearCookies();
      } catch (_) {}
    }
    await widget.securityService.disableExamLock();
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } catch (_) {}
    await widget.securityService.exitApp();
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _remoteTimer?.cancel();
    _lifecycleViolationTimer?.cancel();
    widget.securityService.setViolationListener(null);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hh = _now.hour.toString().padLeft(2, '0');
    final mm = _now.minute.toString().padLeft(2, '0');
    final batText = _batteryLevel >= 0 ? '$_batteryLevel%' : '--';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          widget.securityService.reapplyImmersive();
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: const Color(0xFFF8FAFC),
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  _buildTopBar(hh, mm, batText),
                  if (_isLoading)
                    const LinearProgressIndicator(
                      minHeight: 3,
                      backgroundColor: Color(0xFFE2E8F0),
                      color: Color(0xFF2563EB),
                    ),
                  Expanded(
                    child: _webErrorText != null
                        ? _buildErrorView()
                        : WebViewWidget(controller: _webController),
                  ),
                ],
              ),
              if (_violationReason != null) _buildViolationOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(String hh, String mm, String batText) {
    return Container(
      height: 48,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _isDeviceOwner || _isPinned
                  ? const Color(0xFF16A34A)
                  : const Color(0xFFD97706),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _isDeviceOwner
                  ? 'KIOSK FULL'
                  : (_isPinned ? 'TERKUNCI' : 'MONITOR'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10.5,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${_activeConfig.schoolName} - ${_activeConfig.examTitle}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: _openWifiSettings,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: _wifiConnected
                    ? const Color(0xFFDCFCE7)
                    : const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _wifiConnected
                      ? const Color(0xFF86EFAC)
                      : const Color(0xFFFDE68A),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _wifiConnected
                        ? Icons.wifi_rounded
                        : Icons.wifi_off_rounded,
                    size: 14,
                    color: _wifiConnected
                        ? const Color(0xFF15803D)
                        : const Color(0xFFB45309),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _wifiConnected ? 'WiFi' : 'WiFi Off',
                    style: TextStyle(
                      color: _wifiConnected
                          ? const Color(0xFF15803D)
                          : const Color(0xFFB45309),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$hh:$mm | $batText',
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 11.5),
          ),
          IconButton(
            tooltip: 'Muat ulang',
            icon: const Icon(Icons.refresh, color: Color(0xFF334155), size: 20),
            onPressed: () {
              setState(() => _webErrorText = null);
              widget.securityService.resetNetworkRoute();
              _remoteBusy = false;
              _pollRemoteControl();
              _webController.loadRequest(_targetUri);
            },
          ),
          ElevatedButton(
            onPressed: _promptAdminExit,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: const Size(0, 32),
            ),
            child: const Text(
              'Keluar',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Container(
      color: const Color(0xFFF1F5F9),
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off, color: Color(0xFFDC2626), size: 48),
              const SizedBox(height: 12),
              const Text(
                'Koneksi ke Server Ujian Bermasalah',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Pastikan WiFi perangkat aktif dan terhubung ke jaringan ujian.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF475569),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _webErrorText ?? '',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
              ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: _openWifiSettings,
                    icon: const Icon(Icons.wifi_rounded, size: 18),
                    label: const Text('Pengaturan WiFi'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1D4ED8),
                      side: const BorderSide(color: Color(0xFFBFDBFE)),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() => _webErrorText = null);
                      widget.securityService.resetNetworkRoute();
                      _remoteBusy = false;
                      _pollRemoteControl();
                      _webController.loadRequest(_targetUri);
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Coba Muat Ulang'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const MmcDevFooter(padding: EdgeInsets.zero),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildViolationOverlay() {
    return Container(
      color: const Color(0xE8FEF2F2),
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFDC2626), width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: Color(0xFFDC2626),
                size: 56,
              ),
              const SizedBox(height: 12),
              const Text(
                'PELANGGARAN KEAMANAN TERDETEKSI',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF991B1B),
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _violationReason ?? '',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF7F1D1D), fontSize: 13.5),
              ),
              const SizedBox(height: 8),
              Text(
                'Total pelanggaran sesi ini: $_violationCount',
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 12.5),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _promptAdminUnlockViolation,
                  icon: const Icon(Icons.lock_open),
                  label: const Text('Buka Kunci (Kode Admin)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _promptAdminExit,
                  icon: const Icon(Icons.exit_to_app),
                  label: const Text('Keluar Ujian (Kode Admin)'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFDC2626),
                    side: const BorderSide(color: Color(0xFFDC2626)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
