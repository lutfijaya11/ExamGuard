import 'dart:async';

import 'package:exambroku_android/data/services/native_security_service.dart';
import 'package:exambroku_android/ui/core/mmc_footer.dart';
import 'package:flutter/material.dart';

class InAppWifiDialog extends StatefulWidget {
  const InAppWifiDialog({
    super.key,
    required this.securityService,
    this.onConnectionChanged,
  });

  final NativeSecurityService securityService;
  final VoidCallback? onConnectionChanged;

  static Future<void> show(
    BuildContext context, {
    required NativeSecurityService securityService,
    VoidCallback? onConnectionChanged,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: true,
      builder: (_) => InAppWifiDialog(
        securityService: securityService,
        onConnectionChanged: onConnectionChanged,
      ),
    );
  }

  @override
  State<InAppWifiDialog> createState() => _InAppWifiDialogState();
}

class _InAppWifiDialogState extends State<InAppWifiDialog> {
  bool _isLoading = true;
  bool _isConnecting = false;
  String _statusMessage = '';
  CurrentWifiInfo? _currentInfo;
  List<WifiNetworkItem> _networks = [];

  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshWifiData();
    _autoRefreshTimer = Timer.periodic(
      const Duration(seconds: 6),
      (_) => _refreshWifiData(showSpinner: false),
    );
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshWifiData({bool showSpinner = true}) async {
    if (showSpinner && mounted) {
      setState(() => _isLoading = true);
    }
    try {
      final cur = await widget.securityService.getCurrentWifiInfo();
      final nets = await widget.securityService.scanWifiNetworks();
      if (!mounted) return;
      setState(() {
        _currentInfo = cur;
        _networks = nets;
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _promptConnectTo(WifiNetworkItem item) async {
    if (_currentInfo != null &&
        _currentInfo!.connected &&
        _currentInfo!.ssid.toLowerCase() == item.ssid.toLowerCase()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Perangkat sudah terhubung ke ${item.ssid}'),
          backgroundColor: const Color(0xFF15803D),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    if (!item.isSecure) {
      await _executeConnect(item.ssid, '');
      return;
    }

    final passCtrl = TextEditingController();
    bool obscure = true;

    final pass = await showDialog<String>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDlgState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  const Icon(Icons.wifi_lock_rounded,
                      color: Color(0xFF2563EB), size: 24),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Sandi ${item.ssid}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Masukkan kata sandi Wi-Fi untuk menghubungkan:',
                    style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passCtrl,
                    obscureText: obscure,
                    autofocus: true,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'Kata Sandi',
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 20,
                        ),
                        onPressed: () => setDlgState(() => obscure = !obscure),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(null),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: () =>
                      Navigator.of(dialogCtx).pop(passCtrl.text.trim()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Hubungkan'),
                ),
              ],
            );
          },
        );
      },
    );

    if (pass != null && mounted) {
      await _executeConnect(item.ssid, pass);
    }
  }

  Future<void> _promptManualSsid() async {
    final ssidCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    bool obscure = true;

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDlgState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Row(
                children: [
                  Icon(Icons.add_link_rounded,
                      color: Color(0xFF2563EB), size: 24),
                  SizedBox(width: 8),
                  Text(
                    'Tambah Wi-Fi Manual',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: ssidCtrl,
                    decoration: InputDecoration(
                      labelText: 'Nama Jaringan (SSID)',
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passCtrl,
                    obscureText: obscure,
                    decoration: InputDecoration(
                      labelText: 'Sandi (Kosongkan jika terbuka)',
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 20,
                        ),
                        onPressed: () => setDlgState(() => obscure = !obscure),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(null),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final s = ssidCtrl.text.trim();
                    if (s.isEmpty) return;
                    Navigator.of(dialogCtx)
                        .pop({'ssid': s, 'pass': passCtrl.text.trim()});
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Hubungkan'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null && mounted) {
      await _executeConnect(result['ssid']!, result['pass']!);
    }
  }

  Future<void> _executeConnect(String ssid, String pass) async {
    setState(() {
      _isConnecting = true;
      _statusMessage = 'Menghubungkan ke $ssid...';
    });

    final res = await widget.securityService.connectToWifi(ssid, pass);
    if (!mounted) return;

    final success = res['success'] == true;
    final msg = res['message'] as String? ?? '';

    setState(() {
      _isConnecting = false;
      _statusMessage = msg;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg.isNotEmpty
            ? msg
            : (success ? 'Terhubung ke $ssid' : 'Gagal terhubung')),
        backgroundColor:
            success ? const Color(0xFF15803D) : const Color(0xFFDC2626),
        duration: const Duration(seconds: 3),
      ),
    );

    widget.onConnectionChanged?.call();
    await _refreshWifiData();
  }

  Future<void> _disconnect() async {
    setState(() {
      _isConnecting = true;
      _statusMessage = 'Memutuskan koneksi...';
    });
    await widget.securityService.disconnectWifi();
    if (!mounted) return;
    setState(() {
      _isConnecting = false;
      _statusMessage = 'Koneksi Wi-Fi diputuskan.';
    });
    widget.onConnectionChanged?.call();
    await _refreshWifiData();
  }

  IconData _getSignalIcon(int level, bool isSecure) {
    if (level >= 4) {
      return isSecure ? Icons.wifi_lock_rounded : Icons.wifi_rounded;
    } else if (level >= 2) {
      return isSecure ? Icons.wifi_lock_rounded : Icons.wifi_2_bar_rounded;
    }
    return isSecure ? Icons.wifi_lock_rounded : Icons.wifi_1_bar_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final cur = _currentInfo;
    final isCurConnected = cur != null && cur.connected;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 12, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.wifi_rounded,
                      color: Color(0xFF2563EB), size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pengaturan Wi-Fi Ujian',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        'Tetap di dalam ExamGuard tanpa membuka HP/Setelan',
                        style:
                            TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded,
                      color: Color(0xFF64748B)),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: Color(0xFFE2E8F0)),

          // Content body
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
              children: [
                // Active status card
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isCurConnected
                        ? const Color(0xFFDCFCE7)
                        : const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isCurConnected
                          ? const Color(0xFF86EFAC)
                          : const Color(0xFFFDE68A),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isCurConnected
                            ? Icons.wifi_rounded
                            : Icons.wifi_off_rounded,
                        color: isCurConnected
                            ? const Color(0xFF15803D)
                            : const Color(0xFFB45309),
                        size: 26,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isCurConnected
                                  ? (cur.ssid.isNotEmpty
                                      ? cur.ssid
                                      : 'Terhubung ke Wi-Fi')
                                  : 'Belum Terhubung ke Wi-Fi',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: isCurConnected
                                    ? const Color(0xFF15803D)
                                    : const Color(0xFFB45309),
                              ),
                            ),
                            if (isCurConnected && cur.ipAddress.isNotEmpty)
                              Text(
                                'IP: ${cur.ipAddress}',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: Color(0xFF166534),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (isCurConnected)
                        TextButton(
                          onPressed: _isConnecting ? null : _disconnect,
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFFDC2626),
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Text('Putuskan'),
                        ),
                    ],
                  ),
                ),

                if (_statusMessage.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    _statusMessage,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF2563EB),
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],

                const SizedBox(height: 16),

                // Available Wi-Fi section title + refresh
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Jaringan Wi-Fi Sekitar',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF334155),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _isLoading ? null : () => _refreshWifiData(),
                      icon: _isLoading
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Color(0xFF2563EB)),
                            )
                          : const Icon(Icons.refresh_rounded, size: 16),
                      label: Text(
                        _isLoading ? 'Memindai...' : 'Pindai Ulang',
                        style: const TextStyle(fontSize: 12),
                      ),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),

                if (_isLoading && _networks.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF2563EB),
                      ),
                    ),
                  )
                else if (_networks.isEmpty)
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.wifi_find_rounded,
                            size: 32, color: Color(0xFF94A3B8)),
                        const SizedBox(height: 8),
                        const Text(
                          'Tidak ada jaringan Wi-Fi terdeteksi.',
                          style: TextStyle(
                              fontSize: 12.5, color: Color(0xFF64748B)),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _promptManualSsid,
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Masukkan Nama Wi-Fi Manual'),
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ..._networks.map((net) {
                    final isThisConnected = isCurConnected &&
                        cur.ssid.toLowerCase() == net.ssid.toLowerCase();

                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(
                        color: isThisConnected
                            ? const Color(0xFFF0FDF4)
                            : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isThisConnected
                              ? const Color(0xFF86EFAC)
                              : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: ListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        leading: Icon(
                          _getSignalIcon(net.signalLevel, net.isSecure),
                          color: isThisConnected
                              ? const Color(0xFF15803D)
                              : const Color(0xFF475569),
                          size: 22,
                        ),
                        title: Text(
                          net.ssid,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: isThisConnected
                                ? const Color(0xFF15803D)
                                : const Color(0xFF0F172A),
                          ),
                        ),
                        subtitle: Text(
                          net.isSecure ? 'Terlindungi (Sandi)' : 'Terbuka',
                          style: const TextStyle(
                              fontSize: 11, color: Color(0xFF64748B)),
                        ),
                        trailing: isThisConnected
                            ? const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check_circle_rounded,
                                      color: Color(0xFF16A34A), size: 18),
                                  SizedBox(width: 4),
                                  Text(
                                    'Aktif',
                                    style: TextStyle(
                                      color: Color(0xFF16A34A),
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              )
                            : (net.isSecure
                                ? const Icon(Icons.lock_outline_rounded,
                                    color: Color(0xFF94A3B8), size: 18)
                                : const Icon(Icons.chevron_right_rounded,
                                    color: Color(0xFF94A3B8), size: 20)),
                        onTap: _isConnecting
                            ? null
                            : () => _promptConnectTo(net),
                      ),
                    );
                  }),

                const SizedBox(height: 8),

                // Manual SSID button
                Center(
                  child: TextButton.icon(
                    onPressed: _isConnecting ? null : _promptManualSsid,
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text(
                      'Jaringan Tidak Muncul? Masukkan SSID Manual',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: Color(0xFFE2E8F0)),

          // Quick Native Wi-Fi Panel Option
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
            child: SizedBox(
              height: 38,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await widget.securityService.openWifiSettings();
                  if (mounted) {
                    await _refreshWifiData();
                    widget.onConnectionChanged?.call();
                  }
                },
                icon: const Icon(Icons.settings_input_antenna_rounded, size: 16),
                label: const Text(
                  'Buka Panel Wi-Fi Cepat Android',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF2563EB),
                  side: const BorderSide(color: Color(0xFF93C5FD)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ),

          // Bottom close button
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 6),
            child: SizedBox(
              height: 44,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'Tutup & Lanjutkan Ujian',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),

          const MmcDevFooter(
            padding: EdgeInsets.only(top: 4, bottom: 8),
          ),
        ],
      ),
    );
  }
}
