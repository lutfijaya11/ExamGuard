import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:exambroku_android/data/repositories/exam_config_repository.dart';
import 'package:exambroku_android/data/services/crypto_service.dart';
import 'package:exambroku_android/data/services/native_security_service.dart';
import 'package:exambroku_android/data/services/remote_control_service.dart';
import 'package:exambroku_android/domain/models/exam_config.dart';
import 'package:exambroku_android/ui/core/admin_pin_dialog.dart';
import 'package:exambroku_android/ui/core/mmc_footer.dart';
import 'package:exambroku_android/ui/features/admin_settings/views/admin_settings_view.dart';
import 'package:exambroku_android/ui/features/exam/views/exam_kiosk_view.dart';
import 'package:exambroku_android/ui/features/exam/widgets/in_app_wifi_dialog.dart';
import 'package:exambroku_android/ui/features/launcher/view_models/launcher_view_model.dart';
import 'package:exambroku_android/ui/features/setup/views/server_setup_view.dart';
import 'package:flutter/material.dart';

class LauncherView extends StatefulWidget {
  const LauncherView({
    super.key,
    required this.viewModel,
    required this.repository,
    required this.securityService,
  });

  final LauncherViewModel viewModel;
  final ExamConfigRepository repository;
  final NativeSecurityService securityService;

  @override
  State<LauncherView> createState() => _LauncherViewState();
}

class _LauncherViewState extends State<LauncherView> {
  final _pinGuard = PinAttemptGuard();
  final _remoteService = RemoteControlService();
  final _studentNameCtrl = TextEditingController();
  final _studentIdCtrl = TextEditingController();

  Timer? _heartbeatTimer;
  bool _heartbeatBusy = false;
  bool _inExam = false;
  bool _checkingStudent = false;
  String? _studentLookupError;
  bool _remoteOnline = false;
  String _cachedLogoSource = '';
  Uint8List? _cachedLogoBytes;

  @override
  void initState() {
    super.initState();
    // Identity must always start empty when app launches or restarts
    _studentNameCtrl.text = '';
    _studentIdCtrl.text = '';
    _checkingStudent = false;
    _studentLookupError = null;

    _studentIdCtrl.addListener(() {
      if (_studentLookupError != null && mounted) {
        setState(() => _studentLookupError = null);
      }
    });

    widget.viewModel.initialize().then((_) {
      if (!mounted) return;
      _pollServerOnce();
    });

    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _pollServerOnce(),
    );
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    _studentNameCtrl.dispose();
    _studentIdCtrl.dispose();
    super.dispose();
  }

  Uint8List? _decodeLogo(String raw) {
    final trimmed = raw.trim();
    if (trimmed == _cachedLogoSource) {
      return _cachedLogoBytes;
    }
    _cachedLogoSource = trimmed;
    if (trimmed.isEmpty) {
      _cachedLogoBytes = null;
      return null;
    }
    try {
      var clean = trimmed;
      final marker = clean.indexOf('base64,');
      if (marker >= 0) {
        clean = clean.substring(marker + 7);
      }
      _cachedLogoBytes = base64Decode(clean);
    } catch (_) {
      _cachedLogoBytes = null;
    }
    return _cachedLogoBytes;
  }

  Future<ExamConfig> _saveStudentIdentity(ExamConfig cfg) async {
    final n = _studentNameCtrl.text.trim();
    final id = _studentIdCtrl.text.trim();
    if (n == cfg.studentName && id == cfg.studentId) {
      return cfg;
    }
    final updated = cfg.copyWith(studentName: n, studentId: id);
    await widget.repository.save(updated);
    widget.viewModel.updateConfig(updated);
    return updated;
  }

  DateTime _lastLauncherHeartbeatAttempt = DateTime.now();

  Future<void> _pollServerOnce() async {
    var cfg = widget.viewModel.config;
    if (!mounted || cfg == null || _inExam) return;

    final now = DateTime.now();
    if (_heartbeatBusy) {
      if (now.difference(_lastLauncherHeartbeatAttempt).inSeconds > 2) {
        _heartbeatBusy = false;
      } else {
        return;
      }
    }
    _lastLauncherHeartbeatAttempt = now;

    await widget.viewModel.refreshSecurityStatus();
    if (!mounted) return;

    if (!cfg.remoteControlEnabled) {
      if (_remoteOnline) {
        setState(() => _remoteOnline = false);
      }
      return;
    }

    _heartbeatBusy = true;
    try {
      cfg = await _saveStudentIdentity(cfg);
      final resp = await _remoteService.sendHeartbeat(
        config: cfg,
        status: 'READY',
        violationCount: 0,
        lastViolation: '',
        lockMode: (widget.viewModel.securityStatus?.isDeviceOwner ?? false)
            ? 'DeviceOwner'
            : 'ScreenPinning',
      );
      if (!mounted || _inExam) return;

      if (resp != null && resp.ok) {
        final synced = RemoteControlService.applyServerSync(cfg, resp);
        if (synced != null) {
          cfg = synced;
          await widget.repository.save(synced);
          widget.viewModel.updateConfig(synced);
        }
        if (!_remoteOnline) {
          setState(() => _remoteOnline = true);
        }

        if (resp.command == 'START_EXAM') {
          await _remoteService.sendAck(config: cfg, commandId: resp.commandId);
          if (mounted) {
            await _startExam(cfg, triggeredRemotely: true);
          }
        } else if (resp.command == 'FORCE_EXIT') {
          await _remoteService.sendAck(config: cfg, commandId: resp.commandId);
          if (mounted) {
            _studentNameCtrl.clear();
            _studentIdCtrl.clear();
            await widget.securityService.exitApp();
          }
        }
      } else if (_remoteOnline) {
        setState(() => _remoteOnline = false);
      }
    } catch (_) {
      if (mounted && _remoteOnline) {
        setState(() => _remoteOnline = false);
      }
    } finally {
      _heartbeatBusy = false;
    }
  }

  Future<void> _openHiddenAdminSettings(ExamConfig cfg) async {
    final ok = await AdminPinDialog.show(
      context,
      config: cfg,
      guard: _pinGuard,
      title: 'Akses Pengaturan Admin',
      subtitle: 'Masukkan Kode Admin untuk membuka pengaturan darurat.',
    );
    if (!ok || !mounted) return;

    final updated = await Navigator.of(context).push<ExamConfig>(
      MaterialPageRoute(
        builder: (_) => AdminSettingsView(
          repository: widget.repository,
          initialConfig: cfg,
          securityService: widget.securityService,
        ),
      ),
    );
    if (updated != null && mounted) {
      widget.viewModel.updateConfig(updated);
      await _pollServerOnce();
    }
  }

  Future<void> _handleMulai(ExamConfig cfg) async {
    if (_inExam || _checkingStudent) return;

    final clean = _studentIdCtrl.text.trim();
    if (clean.isEmpty) {
      setState(() {
        _studentLookupError = 'Silakan masukkan nomor peserta ujian terlebih dahulu.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Silakan masukkan nomor peserta ujian terlebih dahulu.'),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
      return;
    }

    if (cfg.examGateMode == 'LOCKED_WAIT') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Akses ujian belum dibuka oleh pengawas atau server.'),
          backgroundColor: Color(0xFFB45309),
        ),
      );
      return;
    }

    setState(() {
      _checkingStudent = true;
      _studentLookupError = null;
    });

    try {
      if (cfg.remoteControlEnabled) {
        final student = await _remoteService.lookupStudent(
          config: cfg,
          studentNumber: clean,
        );
        if (!mounted) return;

        if (student != null) {
          final studentName = ((student['student_name'] as String?) ?? '').trim();
          _studentNameCtrl.text = studentName.isNotEmpty ? studentName : clean;
          await _startExam(cfg);
        } else {
          final msg = "Nomor peserta '$clean' tidak ditemukan dalam database ujian hari ini.";
          setState(() {
            _studentLookupError = msg;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              backgroundColor: const Color(0xFFDC2626),
            ),
          );
        }
      } else {
        // Mode lokal tanpa remote control
        _studentNameCtrl.text = clean;
        await _startExam(cfg);
      }
    } catch (_) {
      if (!mounted) return;
      const msg = 'Gagal menghubungi server panel ujian. Periksa koneksi jaringan.';
      setState(() {
        _studentLookupError = msg;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(msg),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _checkingStudent = false);
      }
    }
  }

  Future<void> _startExam(
    ExamConfig cfg, {
    bool triggeredRemotely = false,
  }) async {
    if (_inExam) return;

    final id = _studentIdCtrl.text.trim();
    if (!triggeredRemotely && id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Silakan masukkan nomor peserta terlebih dahulu.',
          ),
          backgroundColor: Color(0xFFB45309),
        ),
      );
      return;
    }

    if (!triggeredRemotely && cfg.examGateMode == 'LOCKED_WAIT') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Akses ujian belum dibuka oleh pengawas atau server.'),
          backgroundColor: Color(0xFFB45309),
        ),
      );
      return;
    }

    if (_studentNameCtrl.text.trim().isEmpty) {
      _studentNameCtrl.text = id.isNotEmpty ? id : 'Peserta Ujian';
    }

    final latest = await _saveStudentIdentity(cfg);
    if (!mounted) return;

    final res = UrlPortHelper.validateAndBuildUri(
      protocol: latest.protocol,
      host: latest.host,
      port: latest.port,
      path: latest.path,
    );
    if (!res.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Konfigurasi ujian belum siap. Silakan hubungi pengawas ujian.',
          ),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
      return;
    }

    if (!mounted) return;
    _inExam = true;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ExamKioskView(
            config: latest,
            securityService: widget.securityService,
            repository: widget.repository,
            onConfigSynced: (synced) {
              if (mounted) widget.viewModel.updateConfig(synced);
            },
          ),
        ),
      );
    } finally {
      _inExam = false;
      // Dikosongkan saat ujian selesai / dikeluarkan agar peserta berikutnya mulai dari formulir kosong
      _studentNameCtrl.clear();
      _studentIdCtrl.clear();
      final currentCfg = widget.viewModel.config;
      if (currentCfg != null) {
        final cleared = currentCfg.copyWith(studentName: '', studentId: '');
        await widget.repository.save(cleared);
        widget.viewModel.updateConfig(cleared);
      }
    }

    if (mounted) {
      await widget.viewModel.refreshSecurityStatus();
      await _pollServerOnce();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final cfg = widget.viewModel.config;
        final st = widget.viewModel.securityStatus;

        if (!widget.viewModel.isLoading && cfg != null && !cfg.setupCompleted) {
          return ServerSetupView(
            initialConfig: cfg,
            repository: widget.repository,
            onCompleted: (updated) {
              widget.viewModel.updateConfig(updated);
              _pollServerOnce();
            },
          );
        }

        if (widget.viewModel.isLoading || cfg == null) {
          return const Scaffold(
            backgroundColor: Color(0xFFF1F5F9),
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFF2563EB)),
            ),
          );
        }

        final schoolName = cfg.schoolName.trim().isNotEmpty
            ? cfg.schoolName.trim()
            : 'ExamGuard CBT School';
        final examTitle = cfg.examTitle.trim().isNotEmpty
            ? cfg.examTitle.trim()
            : 'Ujian Berbasis Komputer';
        final logoBytes = _decodeLogo(cfg.schoolLogoBase64);
        final isLockedWait = cfg.examGateMode == 'LOCKED_WAIT';
        final wifiConnected = st?.wifiConnected ?? false;

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) async {
            if (didPop) return;
            await widget.securityService.exitApp();
          },
          child: Scaffold(
            backgroundColor: const Color(0xFFF1F5F9),
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 24,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x120F172A),
                          blurRadius: 24,
                          offset: Offset(0, 10),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          height: 6,
                          color: const Color(0xFF2563EB),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Center(
                                child: GestureDetector(
                                  onLongPress: () =>
                                      _openHiddenAdminSettings(cfg),
                                  child: Container(
                                    width: 82,
                                    height: 82,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(
                                        color: const Color(0xFFE2E8F0),
                                      ),
                                    ),
                                    padding: const EdgeInsets.all(8),
                                    child: logoBytes != null
                                        ? Image.memory(
                                            logoBytes,
                                            fit: BoxFit.contain,
                                            gaplessPlayback: true,
                                          )
                                        : Container(
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFEFF6FF),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: const Icon(
                                              Icons.school_rounded,
                                              size: 40,
                                              color: Color(0xFF2563EB),
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                schoolName,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFF0F172A),
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 7,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEFF6FF),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: const Color(0xFFBFDBFE),
                                    ),
                                  ),
                                  child: Text(
                                    examTitle,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Color(0xFF1D4ED8),
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 22),
                              const Divider(
                                height: 1,
                                color: Color(0xFFE2E8F0),
                              ),
                              const SizedBox(height: 20),
                              const Text(
                                'Nomor Peserta Ujian',
                                style: TextStyle(
                                  color: Color(0xFF334155),
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: _studentIdCtrl,
                                textInputAction: TextInputAction.go,
                                onSubmitted: (_) {
                                  if (!isLockedWait && !_checkingStudent) {
                                    _handleMulai(cfg);
                                  }
                                },
                                style: const TextStyle(
                                  color: Color(0xFF0F172A),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
                                decoration: _inputDecoration(
                                  hint: 'Contoh: 27-539-1-001',
                                  icon: Icons.badge_outlined,
                                ),
                              ),
                              if (_studentLookupError != null) ...[
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF2F2),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: const Color(0xFFFECACA),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.error_outline_rounded,
                                        size: 16,
                                        color: Color(0xFFDC2626),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _studentLookupError!,
                                          style: const TextStyle(
                                            color: Color(0xFFB91C1C),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 18),
                              SizedBox(
                                height: 50,
                                child: ElevatedButton.icon(
                                  onPressed: (isLockedWait || _checkingStudent)
                                      ? null
                                      : () => _handleMulai(cfg),
                                  icon: _checkingStudent
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                            color: Colors.white,
                                          ),
                                        )
                                      : Icon(
                                          isLockedWait
                                              ? Icons.lock_clock_rounded
                                              : Icons.login_rounded,
                                          size: 20,
                                        ),
                                  label: Text(
                                    _checkingStudent
                                        ? 'MEMERIKSA DATA...'
                                        : (isLockedWait
                                            ? 'MENUNGGU AKSES ADMIN'
                                            : 'MULAI UJIAN'),
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF059669),
                                    disabledBackgroundColor:
                                        const Color(0xFF94A3B8),
                                    foregroundColor: Colors.white,
                                    disabledForegroundColor: Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                isLockedWait
                                    ? 'Ujian akan otomatis dimulai setelah dibuka oleh Admin'
                                    : 'Masukkan nomor peserta ujian kemudian klik Mulai Ujian',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: isLockedWait
                                      ? const Color(0xFFB45309)
                                      : const Color(0xFF64748B),
                                  fontSize: 11.5,
                                ),
                              ),
                              const SizedBox(height: 18),
                              const Divider(
                                height: 1,
                                color: Color(0xFFE2E8F0),
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Expanded(
                                    child: InkWell(
                                      onTap: () => InAppWifiDialog.show(
                                        context,
                                        securityService: widget.securityService,
                                        onConnectionChanged: () =>
                                            widget.viewModel.refreshSecurityStatus(),
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: wifiConnected
                                              ? const Color(0xFFDCFCE7)
                                              : const Color(0xFFFEF3C7),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              wifiConnected
                                                  ? Icons.wifi_rounded
                                                  : Icons.wifi_off_rounded,
                                              size: 16,
                                              color: wifiConnected
                                                  ? const Color(0xFF15803D)
                                                  : const Color(0xFFB45309),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              wifiConnected
                                                  ? 'WiFi: Aktif'
                                                  : 'WiFi: Mati',
                                              style: TextStyle(
                                                color: wifiConnected
                                                    ? const Color(0xFF15803D)
                                                    : const Color(0xFFB45309),
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: !cfg.remoteControlEnabled
                                            ? const Color(0xFFF1F5F9)
                                            : (_remoteOnline
                                                ? const Color(0xFFEFF6FF)
                                                : const Color(0xFFFEF2F2)),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            !cfg.remoteControlEnabled
                                                ? Icons.computer_rounded
                                                : (_remoteOnline
                                                    ? Icons.cloud_done_rounded
                                                    : Icons.cloud_off_rounded),
                                            size: 16,
                                            color: !cfg.remoteControlEnabled
                                                ? const Color(0xFF64748B)
                                                : (_remoteOnline
                                                    ? const Color(0xFF1D4ED8)
                                                    : const Color(0xFFDC2626)),
                                          ),
                                          const SizedBox(width: 6),
                                          Flexible(
                                            child: Text(
                                              !cfg.remoteControlEnabled
                                                  ? 'Mode Lokal'
                                                  : (_remoteOnline
                                                      ? 'Server Siap'
                                                      : 'Terputus'),
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: !cfg.remoteControlEnabled
                                                    ? const Color(0xFF64748B)
                                                    : (_remoteOnline
                                                        ? const Color(0xFF1D4ED8)
                                                        : const Color(0xFFDC2626)),
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Center(
                                child: TextButton.icon(
                                  onPressed: () => widget.securityService.exitApp(),
                                  icon: const Icon(Icons.power_settings_new_rounded, size: 16, color: Color(0xFF64748B)),
                                  label: const Text(
                                    'Tutup Aplikasi',
                                    style: TextStyle(
                                      color: Color(0xFF64748B),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Divider(
                                height: 1,
                                color: Color(0xFFF1F5F9),
                              ),
                              const MmcDevFooter(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      },
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13.5),
      prefixIcon: Icon(icon, color: const Color(0xFF64748B), size: 20),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.6),
      ),
    );
  }
}
