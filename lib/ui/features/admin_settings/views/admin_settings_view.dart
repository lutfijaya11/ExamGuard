import 'dart:io';

import 'package:exambroku_android/data/repositories/exam_config_repository.dart';
import 'package:exambroku_android/data/services/crypto_service.dart';
import 'package:exambroku_android/data/services/native_security_service.dart';
import 'package:exambroku_android/data/services/remote_control_service.dart';
import 'package:exambroku_android/domain/models/exam_config.dart';
import 'package:exambroku_android/ui/core/mmc_footer.dart';
import 'package:flutter/material.dart';

class AdminSettingsView extends StatefulWidget {
  const AdminSettingsView({
    super.key,
    required this.repository,
    required this.initialConfig,
    this.securityService,
  });

  final ExamConfigRepository repository;
  final ExamConfig initialConfig;
  final NativeSecurityService? securityService;

  @override
  State<AdminSettingsView> createState() => _AdminSettingsViewState();
}

class _AdminSettingsViewState extends State<AdminSettingsView> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _hostCtrl;
  late final TextEditingController _portCtrl;
  late final TextEditingController _pathCtrl;
  final _newPinCtrl = TextEditingController();
  final _confirmPinCtrl = TextEditingController();
  late final TextEditingController _remoteUrlCtrl;

  late bool _strictHostLock;
  late bool _requirePinning;
  late bool _blockScreenshots;
  late bool _alarmOnViolation;
  late bool _blockCopyPaste;
  late bool _clearCacheOnExit;
  late bool _remoteControlEnabled;
  late bool _syncUrlFromServer;

  bool _isTesting = false;
  String? _testMessage;
  bool _testOk = false;

  bool _isTestingPanel = false;
  String? _panelTestMessage;
  bool _panelTestOk = false;

  @override
  void initState() {
    super.initState();
    final c = widget.initialConfig;
    _titleCtrl = TextEditingController(text: c.examTitle);
    _hostCtrl = TextEditingController(text: c.host);
    _portCtrl = TextEditingController(text: c.port.toString());
    _pathCtrl = TextEditingController(text: c.path);
    _remoteUrlCtrl = TextEditingController(text: c.remoteServerUrl);

    _strictHostLock = c.strictHostLock;
    _requirePinning = c.requirePinning;
    _blockScreenshots = c.blockScreenshots;
    _alarmOnViolation = c.alarmOnViolation;
    _blockCopyPaste = c.blockCopyPaste;
    _clearCacheOnExit = c.clearCacheOnExit;
    _remoteControlEnabled = c.remoteControlEnabled;
    _syncUrlFromServer = c.syncUrlFromServer;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _pathCtrl.dispose();
    _newPinCtrl.dispose();
    _confirmPinCtrl.dispose();
    _remoteUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    final uri = Uri.parse(ExamConfig.lockedPanelUrl);
    setState(() {
      _isTesting = true;
      _testMessage = 'Menguji koneksi ke $uri...';
      _testOk = false;
    });

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.getUrl(uri);
      final response = await request.close().timeout(const Duration(seconds: 5));
      await response.drain<void>();
      if (!mounted) return;
      setState(() {
        _testOk = true;
        _testMessage = 'Koneksi berhasil! Server CBT merespons HTTP ${response.statusCode}.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testOk = false;
        _testMessage = 'Gagal terhubung: $e';
      });
    } finally {
      client.close(force: true);
      if (mounted) {
        setState(() => _isTesting = false);
      }
    }
  }

  Future<void> _testPanelConnection() async {
    const url = ExamConfig.lockedPanelUrl;
    setState(() {
      _isTestingPanel = true;
      _panelTestMessage = 'Menghubungkan ke $url ...';
    });

    final probe = widget.initialConfig.copyWith(
      remoteControlEnabled: true,
      remoteServerUrl: url,
      remoteApiToken: '',
    );
    final err = await RemoteControlService().testPanelConnection(probeConfig: probe);
    if (!mounted) return;
    setState(() {
      _isTestingPanel = false;
      _panelTestOk = err == null;
      _panelTestMessage = err ?? 'Panel PHP terhubung!';
    });
  }

  Future<void> _saveSettings() async {
    var pinHash = widget.initialConfig.adminPinHash;
    var pinSalt = widget.initialConfig.adminPinSalt;
    var isDefaultPin = widget.initialConfig.isDefaultPin;

    if (_newPinCtrl.text.isNotEmpty || _confirmPinCtrl.text.isNotEmpty) {
      if (_newPinCtrl.text.length < 6) {
        _showSnack('Kode Admin baru minimal 6 karakter.');
        return;
      }
      if (_newPinCtrl.text != _confirmPinCtrl.text) {
        _showSnack('Konfirmasi Kode Admin tidak cocok.');
        return;
      }
      final pair = PinHasher.hashPin(_newPinCtrl.text);
      pinHash = pair.hashBase64;
      pinSalt = pair.saltBase64;
      isDefaultPin = false;
    }

    final updated = widget.initialConfig.copyWith(
      examTitle: _titleCtrl.text.trim().isEmpty
          ? 'Ujian CBT Terpadu'
          : _titleCtrl.text.trim(),
      protocol: 'https',
      host: ExamConfig.lockedCbtHost,
      port: 443,
      path: '/',
      adminPinHash: pinHash,
      adminPinSalt: pinSalt,
      pinIterations: _newPinCtrl.text.isNotEmpty ? 20000 : null,
      isDefaultPin: isDefaultPin,
      remoteControlEnabled: true,
      remoteServerUrl: ExamConfig.lockedPanelUrl,
      remoteApiToken: '',
      syncUrlFromServer: _syncUrlFromServer,
      setupCompleted: true,
      strictHostLock: _strictHostLock,
      requirePinning: false,
      blockScreenshots: _blockScreenshots,
      alarmOnViolation: _alarmOnViolation,
      blockCopyPaste: _blockCopyPaste,
      clearCacheOnExit: _clearCacheOnExit,
    );

    await widget.repository.save(updated);
    if (!mounted) return;
    Navigator.of(context).pop(updated);
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: const Color(0xFFDC2626)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: Color(0xFFE2E8F0)),
        ),
        title: const Text('Pengaturan Admin'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle('1. Target Server Ujian (URL & Port)'),
          const SizedBox(height: 10),
          TextField(
            controller: _titleCtrl,
            style: const TextStyle(color: Color(0xFF0F172A)),
            decoration: _inputDeco('Judul / Nama Ujian'),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFCBD5E1)),
            ),
            child: const Row(
              children: [
                Icon(Icons.lock_rounded, color: Color(0xFF059669), size: 22),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'URL CBT Ditanam & Dikunci Sistem:',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        ExamConfig.lockedPanelUrl,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Terkunci permanen: ${ExamConfig.lockedPanelUrl} (tidak dapat diketik manual)',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF059669),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: _isTesting ? null : _testConnection,
            icon: const Icon(Icons.wifi_find, size: 18),
            label: Text(_isTesting ? 'Menguji...' : 'Tes Koneksi URL CBT'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
            ),
          ),
          if (_testMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              _testMessage!,
              style: TextStyle(
                color: _testOk
                    ? const Color(0xFF16A34A)
                    : const Color(0xFFDC2626),
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 22),
          _sectionTitle('2. Ubah Kode Admin (Minimal 6 Karakter)'),
          const SizedBox(height: 10),
          TextField(
            controller: _newPinCtrl,
            obscureText: true,
            style: const TextStyle(color: Color(0xFF0F172A)),
            decoration: _inputDeco('Kode Admin Baru (kosongkan jika tetap)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirmPinCtrl,
            obscureText: true,
            style: const TextStyle(color: Color(0xFF0F172A)),
            decoration: _inputDeco('Konfirmasi Kode Admin Baru'),
          ),
          const SizedBox(height: 22),
          _sectionTitle('3. Kebijakan Keamanan Ujian'),
          const SizedBox(height: 6),
          _switchTile(
            'Kunci Host & Port',
            'Blokir navigasi ke domain atau port lain di luar server ujian',
            _strictHostLock,
            (v) => setState(() => _strictHostLock = v),
          ),
          _switchTile(
            'Wajibkan Screen Pinning / Kiosk',
            'Kunci tombol Home & Recent Apps selama ujian',
            _requirePinning,
            (v) => setState(() => _requirePinning = v),
          ),
          _switchTile(
            'Anti-Screenshot & Rekam Layar',
            'Blokir tangkapan layar dan sembunyikan preview di Recent Apps',
            _blockScreenshots,
            (v) => setState(() => _blockScreenshots = v),
          ),
          _switchTile(
            'Alarm Pelanggaran Keamanan',
            'Bunyikan alarm & kunci layar jika siswa mencoba keluar/split-screen',
            _alarmOnViolation,
            (v) => setState(() => _alarmOnViolation = v),
          ),
          _switchTile(
            'Blokir Salin-Tempel (Copy/Paste)',
            'Nonaktifkan seleksi teks dan menu tekan-lama di halaman ujian',
            _blockCopyPaste,
            (v) => setState(() => _blockCopyPaste = v),
          ),
          _switchTile(
            'Hapus Cache & Cookies Saat Keluar',
            'Bersihkan sesi ujian secara otomatis setelah Admin keluar',
            _clearCacheOnExit,
            (v) => setState(() => _clearCacheOnExit = v),
          ),
          if (widget.securityService != null) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => widget.securityService?.openAccessibilitySettings(),
              icon: const Icon(Icons.touch_app_rounded, color: Color(0xFF059669)),
              label: const Text('Buka Pengaturan Aksesibilitas HP (Auto GOT IT)'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF059669),
                side: const BorderSide(color: Color(0xFF10B981)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ],
          const SizedBox(height: 18),
          _sectionTitle('4. Kontrol Terpusat Panel Admin PHP (Opsional)'),
          const SizedBox(height: 6),
          _switchTile(
            'Hubungkan ke Panel Admin PHP',
            'Sinkronkan Kode Admin, monitoring siswa & remote start/keluar',
            _remoteControlEnabled,
            (v) => setState(() => _remoteControlEnabled = v),
          ),
          if (_remoteControlEnabled) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.lock_rounded, color: Color(0xFF059669), size: 22),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'URL Panel Admin PHP (Terkunci):',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          ExamConfig.lockedPanelUrl,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Terkunci otomatis: ${ExamConfig.lockedPanelUrl}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF059669),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            _switchTile(
              'Sinkronkan URL, Port & Kebijakan dari Server PHP',
              'Ikuti semua pengaturan & kebijakan dari Panel PHP Admin',
              _syncUrlFromServer,
              (v) => setState(() => _syncUrlFromServer = v),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _isTestingPanel ? null : _testPanelConnection,
              icon: const Icon(Icons.cloud_done, size: 18),
              label: Text(_isTestingPanel ? 'Menghubungi Panel...' : 'Tes Koneksi Panel PHP'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
              ),
            ),
            if (_panelTestMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _panelTestMessage!,
                style: TextStyle(
                  color: _panelTestOk
                      ? const Color(0xFF16A34A)
                      : const Color(0xFFDC2626),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
          const SizedBox(height: 20),
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _saveSettings,
              icon: const Icon(Icons.save),
              label: const Text(
                'Simpan Pengaturan',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF16A34A),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const MmcDevFooter(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF1D4ED8),
        fontSize: 14,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  InputDecoration _inputDeco(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Color(0xFF64748B)),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
      ),
    );
  }

  Widget _switchTile(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: const TextStyle(color: Color(0xFF0F172A), fontSize: 14)),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
      ),
      value: value,
      activeThumbColor: const Color(0xFF16A34A),
      onChanged: onChanged,
    );
  }
}
