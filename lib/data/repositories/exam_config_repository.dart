import 'dart:convert';

import 'package:exambroku_android/data/services/crypto_service.dart';
import 'package:exambroku_android/domain/models/exam_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ExamConfigRepository {
  static const String _storageKey = 'exambroku_config_v1';

  Future<ExamConfig> loadOrCreateDefault() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final cfg = ExamConfig.fromJson(decoded);
        if (cfg.adminPinHash.isNotEmpty && cfg.adminPinSalt.isNotEmpty) {
          if (cfg.remoteServerUrl != ExamConfig.lockedPanelUrl ||
              !cfg.setupCompleted ||
              !cfg.requirePinning ||
              cfg.schoolName == 'ExamBroKu CBT School' ||
              cfg.schoolName == 'ExamGuard CBT School') {
            final locked = cfg.copyWith(
              schoolName: 'MAS AL HUDA',
              examTitle: cfg.examTitle == 'Ujian CBT Terpadu'
                  ? 'Sumatif Akhir Semester'
                  : cfg.examTitle,
              remoteControlEnabled: true,
              remoteServerUrl: ExamConfig.lockedPanelUrl,
              syncUrlFromServer: true,
              setupCompleted: true,
              requirePinning: true,
            );
            await save(locked);
            return locked;
          }
          return cfg;
        }
      } catch (_) {
        // Fall through to default initialization
      }
    }

    final pair = PinHasher.hashPin(ExamConfig.defaultAdminPin);
    final initial = ExamConfig.initial(
      adminPinHash: pair.hashBase64,
      adminPinSalt: pair.saltBase64,
    );
    await save(initial);
    return initial;
  }

  Future<void> save(ExamConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(config.toJson()));
  }
}
