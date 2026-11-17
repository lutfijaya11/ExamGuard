import 'package:exambroku_android/data/repositories/exam_config_repository.dart';
import 'package:exambroku_android/data/services/remote_control_service.dart';
import 'package:exambroku_android/domain/models/exam_config.dart';
import 'package:exambroku_android/ui/core/mmc_footer.dart';
import 'package:flutter/material.dart';

/// First-run onboarding view prompting the operator/admin to connect this
/// Android device to the centralized PHP Admin Panel before entering Standby.
class ServerSetupView extends StatefulWidget {
  const ServerSetupView({
    super.key,
    required this.initialConfig,
    required this.repository,
    required this.onCompleted,
  });

  final ExamConfig initialConfig;
  final ExamConfigRepository repository;
  final ValueChanged<ExamConfig> onCompleted;

  @override
  State<ServerSetupView> createState() => _ServerSetupViewState();
}

class _ServerSetupViewState extends State<ServerSetupView> {
  late final TextEditingController _urlCtrl;
  late bool _syncFromServer;
  bool _isConnecting = false;
  String? _statusMsg;
  bool _statusOk = false;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(text: ExamConfig.lockedPanelUrl);
    _syncFromServer = widget.initialConfig.syncUrlFromServer;
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _connectAndSave() async {
    final url = RemoteControlService.normalizeServerUrl(_urlCtrl.text);
    if (url.isEmpty) {
      setState(() {
        _statusOk = false;
        _statusMsg = 'Isi URL Panel Admin PHP terlebih dahulu.';
      });
      return;
    }

    _urlCtrl.text = url;
    setState(() {
      _isConnecting = true;
      _statusOk = false;
      _statusMsg = 'Menghubungkan ke $url ...';
    });

    final baseCfg = widget.initialConfig.copyWith(
      remoteControlEnabled: true,
      remoteServerUrl: url,
      remoteApiToken: '',
      syncUrlFromServer: _syncFromServer,
      setupCompleted: true,
    );

    final probe = await RemoteControlService().probePanelConnection(
      probeConfig: baseCfg,
    );
    if (!mounted) return;

    if (probe.heartbeat != null && probe.heartbeat!.ok) {
      final synced = RemoteControlService.applyServerSync(
            baseCfg,
            probe.heartbeat!,
          ) ??
          baseCfg;
      final finalCfg = synced.copyWith(setupCompleted: true);
      await widget.repository.save(finalCfg);
      if (!mounted) return;
      setState(() {
        _isConnecting = false;
        _statusOk = true;
        _statusMsg = 'Berhasil terhubung & sinkronisasi dari server selesai!';
      });
      widget.onCompleted(finalCfg);
    } else {
      setState(() {
        _isConnecting = false;
        _statusOk = false;
        _statusMsg = probe.error ?? 'Gagal terhubung ke Panel PHP.';
      });
    }
  }

  Future<void> _skipOfflineMode() async {
    final updated = widget.initialConfig.copyWith(
      remoteControlEnabled: false,
      setupCompleted: true,
    );
    await widget.repository.save(updated);
    if (!mounted) return;
    widget.onCompleted(updated);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const SizedBox(height: 12),
            const Row(
              children: [
                Icon(Icons.cloud_sync, color: Color(0xFF2563EB), size: 32),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Setup Server ExamGuard',
                    style: TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Masukkan URL Panel Admin PHP agar URL ujian, Kode Admin, dan seluruh kebijakan keamanan tersinkron otomatis dari server.',
              style: TextStyle(color: Color(0xFF475569), fontSize: 13.5),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Hubungkan ke Panel Admin PHP',
                    style: TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFCBD5E1)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.lock_rounded, color: Color(0xFF059669), size: 20),
                        SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'URL Panel Admin CBT (Terkunci Otomatis)',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                ExamConfig.lockedPanelUrl,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: const Color(0xFF16A34A),
                    title: const Text(
                      'Sinkronkan URL, Port & Kebijakan dari Server PHP',
                      style: TextStyle(color: Color(0xFF0F172A), fontSize: 13.5),
                    ),
                    subtitle: const Text(
                      'Otomatis ikuti seluruh pengaturan Admin di server',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                    ),
                    value: _syncFromServer,
                    onChanged: (v) => setState(() => _syncFromServer = v),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _isConnecting ? null : _connectAndSave,
                      icon: const Icon(Icons.cloud_done),
                      label: Text(
                        _isConnecting
                            ? 'Menghubungkan...'
                            : 'Tes Koneksi & Hubungkan',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  if (_statusMsg != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _statusMsg!,
                      style: TextStyle(
                        color: _statusOk
                            ? const Color(0xFF16A34A)
                            : const Color(0xFFDC2626),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _isConnecting ? null : _skipOfflineMode,
              icon: const Icon(Icons.settings_ethernet, color: Color(0xFF475569)),
              label: const Text(
                'Lewati — Atur URL Ujian Manual (Mode Offline)',
                style: TextStyle(color: Color(0xFF475569)),
              ),
            ),
            const SizedBox(height: 14),
            const MmcDevFooter(),
          ],
        ),
      ),
    );
  }
}
