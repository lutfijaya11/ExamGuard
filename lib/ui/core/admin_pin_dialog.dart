import 'dart:async';

import 'package:exambroku_android/data/services/crypto_service.dart';
import 'package:exambroku_android/domain/models/exam_config.dart';
import 'package:flutter/material.dart';

class AdminPinDialog extends StatefulWidget {
  const AdminPinDialog({
    super.key,
    required this.config,
    required this.guard,
    required this.title,
    required this.subtitle,
  });

  final ExamConfig config;
  final PinAttemptGuard guard;
  final String title;
  final String subtitle;

  static Future<bool> show(
    BuildContext context, {
    required ExamConfig config,
    required PinAttemptGuard guard,
    required String title,
    required String subtitle,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AdminPinDialog(
        config: config,
        guard: guard,
        title: title,
        subtitle: subtitle,
      ),
    );
    return result ?? false;
  }

  @override
  State<AdminPinDialog> createState() => _AdminPinDialogState();
}

class _AdminPinDialogState extends State<AdminPinDialog> {
  final _pinController = TextEditingController();
  bool _obscure = true;
  String? _errorText;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    _cooldownTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      if (widget.guard.remainingCooldownSeconds() > 0 || _errorText != null) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _pinController.dispose();
    super.dispose();
  }

  void _verify() {
    final rem = widget.guard.remainingCooldownSeconds();
    if (rem > 0) {
      setState(() {});
      return;
    }

    if (PinHasher.verifyPin(widget.config, _pinController.text)) {
      widget.guard.recordSuccess();
      Navigator.of(context).pop(true);
      return;
    }

    final cooldown = widget.guard.recordFailure();
    _pinController.clear();
    setState(() {
      if (cooldown > 0) {
        _errorText = 'Terlalu banyak percobaan salah.';
      } else {
        _errorText =
            'Kode admin salah (percobaan gagal: ${widget.guard.failedAttempts}).';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final rem = widget.guard.remainingCooldownSeconds();
    final isLockedOut = rem > 0;

    return AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        widget.title,
        style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.subtitle,
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _pinController,
            obscureText: _obscure,
            enabled: !isLockedOut,
            autofocus: true,
            style: const TextStyle(color: Color(0xFF0F172A)),
            onSubmitted: (_) => _verify(),
            decoration: InputDecoration(
              labelText: 'Kode Admin',
              labelStyle: const TextStyle(color: Color(0xFF64748B)),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure ? Icons.visibility : Icons.visibility_off,
                  color: const Color(0xFF64748B),
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (isLockedOut)
            Text(
              'Terlalu banyak percobaan salah. Tunggu $rem detik.',
              style: const TextStyle(color: Color(0xFFDC2626), fontSize: 12.5),
            )
          else if (_errorText != null)
            Text(
              _errorText!,
              style: const TextStyle(color: Color(0xFFDC2626), fontSize: 12.5),
            )
          else if (widget.config.isDefaultPin)
            const Text(
              'Catatan: Kode default masih 123456 (segera ubah di Pengaturan).',
              style: TextStyle(color: Color(0xFFB45309), fontSize: 12),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Batal', style: TextStyle(color: Color(0xFF475569))),
        ),
        ElevatedButton(
          onPressed: isLockedOut ? null : _verify,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2563EB),
            foregroundColor: Colors.white,
          ),
          child: const Text('Verifikasi'),
        ),
      ],
    );
  }
}
