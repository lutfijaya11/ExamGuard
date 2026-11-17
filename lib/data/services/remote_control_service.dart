import 'dart:convert';
import 'dart:io';

import 'package:exambroku_android/domain/models/exam_config.dart';

class HeartbeatResult {
  const HeartbeatResult({
    required this.ok,
    required this.command,
    required this.commandId,
    required this.adminPinSalt,
    required this.adminPinHash,
    required this.pinIterations,
    required this.syncUrlToClients,
    this.examGateMode = 'FREE_OR_REMOTE',
    this.securityPolicies,
    this.examConfigMap,
  });

  final bool ok;
  final String command;
  final String commandId;
  final String adminPinSalt;
  final String adminPinHash;
  final int pinIterations;
  final bool syncUrlToClients;
  final String examGateMode;
  final Map<String, dynamic>? securityPolicies;
  final Map<String, dynamic>? examConfigMap;

  factory HeartbeatResult.fromJson(Map<String, dynamic> json) {
    return HeartbeatResult(
      ok: (json['ok'] as bool?) ?? false,
      command: (json['command'] as String?) ?? 'NONE',
      commandId: (json['command_id'] as String?) ?? '',
      adminPinSalt: (json['admin_pin_salt'] as String?) ?? '',
      adminPinHash: (json['admin_pin_hash'] as String?) ?? '',
      pinIterations: (json['pin_iterations'] as num?)?.toInt() ?? 20000,
      syncUrlToClients: (json['sync_url_to_clients'] as bool?) ?? false,
      examGateMode: (json['exam_gate_mode'] as String?) == 'ADMIN_ONLY'
          ? 'ADMIN_ONLY'
          : 'FREE_OR_REMOTE',
      securityPolicies: json['security_policies'] as Map<String, dynamic>?,
      examConfigMap: json['exam_config'] as Map<String, dynamic>?,
    );
  }
}

class PanelProbeResult {
  const PanelProbeResult({this.heartbeat, this.error});

  final HeartbeatResult? heartbeat;
  final String? error;
}

class RemoteControlService {
  static final HttpClient _persistentClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 3)
    ..idleTimeout = const Duration(seconds: 30)
    ..badCertificateCallback = ((cert, host, port) => true);

  static String normalizeServerUrl(String raw) {
    var trimmed = raw.trim().replaceAll(RegExp(r'/+$'), '');
    if (trimmed.isEmpty) return '';
    if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(trimmed)) {
      trimmed = 'https://$trimmed';
    }
    return trimmed;
  }

  Future<PanelProbeResult> probePanelConnection({
    required ExamConfig probeConfig,
    String status = 'IDLE',
    int violationCount = 0,
    String lastViolation = '',
    String lockMode = 'ConnectionTest',
  }) async {
    final baseUrl = normalizeServerUrl(probeConfig.remoteServerUrl);
    final uri = Uri.tryParse('$baseUrl/api/heartbeat.php');
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return const PanelProbeResult(
        error: 'Format URL Panel PHP tidak valid (contoh: https://domainanda.com/exambro).',
      );
    }

    final body = jsonEncode({
      'device_id': probeConfig.deviceId,
      'student_name': probeConfig.studentName,
      'student_id': probeConfig.studentId,
      'platform': 'Android',
      'device_name': Platform.localHostname,
      'status': status,
      'exam_url': UrlPortHelper.formatDisplayUrl(probeConfig),
      'violation_count': violationCount,
      'last_violation': lastViolation,
      'lock_mode': lockMode,
      'need_logo': probeConfig.schoolLogoBase64.trim().isEmpty,
    });

    try {
      final req = await _persistentClient.postUrl(uri);
      req.headers.contentType = ContentType.json;
      req.headers.set('User-Agent', 'ExamBroKu-Android/2.0');
      req.headers.set('Connection', 'keep-alive');
      if (probeConfig.remoteApiToken.trim().isNotEmpty) {
        final tok = probeConfig.remoteApiToken.trim();
        req.headers.set('X-ExamBro-Token', tok);
        req.headers.set('Authorization', 'Bearer $tok');
      }
      req.write(body);
      final resp = await req.close().timeout(const Duration(milliseconds: 2500));
      final respText = await resp
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(milliseconds: 2500));
      if (resp.statusCode == 401) {
        return const PanelProbeResult(
          error: 'Server menolak akses (HTTP 401). Pastikan php-admin-panel di server sudah versi terbaru.',
        );
      }
      if (resp.statusCode != 200) {
        return PanelProbeResult(
          error: 'Server merespons HTTP ${resp.statusCode}. Pastikan URL mengarah ke folder php-admin-panel.',
        );
      }
      final map = jsonDecode(respText) as Map<String, dynamic>;
      final parsed = HeartbeatResult.fromJson(map);
      if (!parsed.ok) {
        return const PanelProbeResult(error: 'Respon Panel PHP tidak valid.');
      }
      return PanelProbeResult(heartbeat: parsed);
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('timed out') || msg.contains('TimeoutException')) {
        return PanelProbeResult(
          error: 'Koneksi timeout ke ${uri.host}:${uri.port}. Pastikan server online menyala, internet HP aktif, dan cek https:// vs http://.',
        );
      }
      return PanelProbeResult(error: 'Gagal terhubung ke server: $e');
    }
  }

  Future<HeartbeatResult?> sendHeartbeat({
    required ExamConfig config,
    required String status,
    required int violationCount,
    required String lastViolation,
    required String lockMode,
  }) async {
    if (!config.remoteControlEnabled || config.remoteServerUrl.trim().isEmpty) {
      return null;
    }
    final probe = await probePanelConnection(
      probeConfig: config,
      status: status,
      violationCount: violationCount,
      lastViolation: lastViolation,
      lockMode: lockMode,
    );
    return probe.heartbeat;
  }

  Future<void> sendAck({
    required ExamConfig config,
    required String commandId,
  }) async {
    if (!config.remoteControlEnabled ||
        config.remoteServerUrl.trim().isEmpty ||
        commandId.isEmpty) {
      return;
    }

    final baseUrl = normalizeServerUrl(config.remoteServerUrl);
    final uri = Uri.tryParse('$baseUrl/api/ack.php');
    if (uri == null) return;

    try {
      final req = await _persistentClient.postUrl(uri);
      req.headers.contentType = ContentType.json;
      req.headers.set('User-Agent', 'ExamBroKu-Android/2.0');
      req.headers.set('Connection', 'keep-alive');
      if (config.remoteApiToken.trim().isNotEmpty) {
        final tok = config.remoteApiToken.trim();
        req.headers.set('X-ExamBro-Token', tok);
        req.headers.set('Authorization', 'Bearer $tok');
      }
      req.write(jsonEncode({
        'device_id': config.deviceId,
        'command_id': commandId,
      }));
      final resp = await req.close().timeout(const Duration(milliseconds: 2000));
      await resp.drain<void>().timeout(const Duration(milliseconds: 1500));
    } catch (_) {
      // Best-effort ack
    }
  }

  static ExamConfig? applyServerSync(ExamConfig config, HeartbeatResult resp) {
    if (!resp.ok) return null;

    var updated = config;
    var changed = false;

    if (resp.adminPinSalt.isNotEmpty && resp.adminPinHash.isNotEmpty) {
      if (updated.adminPinSalt != resp.adminPinSalt ||
          updated.adminPinHash != resp.adminPinHash ||
          updated.pinIterations != resp.pinIterations) {
        updated = updated.copyWith(
          adminPinSalt: resp.adminPinSalt,
          adminPinHash: resp.adminPinHash,
          pinIterations: resp.pinIterations > 0 ? resp.pinIterations : 20000,
          isDefaultPin: false,
        );
        changed = true;
      }
    }

    if (resp.examConfigMap != null) {
      final ec = resp.examConfigMap!;
      final syncedSchool = ((ec['school_name'] as String?) ?? '').trim();
      final effectiveSchool =
          syncedSchool.isNotEmpty ? syncedSchool : updated.schoolName;
      final rawLogo = ((ec['school_logo_base64'] as String?) ?? '').trim();
      final syncedLogo = rawLogo.isNotEmpty ? rawLogo : updated.schoolLogoBase64;
      final syncedTitle = ((ec['exam_title'] as String?) ?? '').trim();
      final effectiveTitle =
          syncedTitle.isNotEmpty ? syncedTitle : updated.examTitle;

      if (updated.schoolName != effectiveSchool ||
          updated.schoolLogoBase64 != syncedLogo ||
          updated.examTitle != effectiveTitle) {
        updated = updated.copyWith(
          schoolName: effectiveSchool,
          schoolLogoBase64: syncedLogo,
          examTitle: effectiveTitle,
        );
        changed = true;
      }
    }

    if (updated.syncUrlFromServer &&
        resp.syncUrlToClients &&
        resp.examConfigMap != null) {
      final ec = resp.examConfigMap!;
      final proto = (ec['protocol'] as String?) ?? updated.protocol;
      final host = (ec['host'] as String?) ?? '';
      final port = (ec['port'] as num?)?.toInt() ?? updated.port;
      final path = (ec['path'] as String?) ?? '/';

      final valid = UrlPortHelper.validateAndBuildUri(
        protocol: proto,
        host: host,
        port: port,
        path: path,
      );

      if (valid.isValid && valid.uri != null) {
        if (updated.protocol != proto ||
            updated.host != valid.uri!.host ||
            updated.port != valid.uri!.port ||
            updated.path != valid.uri!.path) {
          updated = updated.copyWith(
            protocol: proto,
            host: valid.uri!.host,
            port: valid.uri!.port,
            path: valid.uri!.path,
          );
          changed = true;
        }
      }
    }

    if (resp.examGateMode.isNotEmpty) {
      final mode = resp.examGateMode == 'ADMIN_ONLY'
          ? 'ADMIN_ONLY'
          : 'FREE_OR_REMOTE';
      if (updated.examGateMode != mode) {
        updated = updated.copyWith(examGateMode: mode);
        changed = true;
      }
    }

    if (resp.securityPolicies != null) {
      final p = resp.securityPolicies!;
      final nextStrict = (p['strict_host_lock'] as bool?) ?? updated.strictHostLock;
      final nextShot = (p['block_screenshots'] as bool?) ?? updated.blockScreenshots;
      final nextCache = (p['clear_cache_on_exit'] as bool?) ?? updated.clearCacheOnExit;
      final nextPin = (p['android_require_pinning'] as bool?) ?? updated.requirePinning;
      final nextAlarm = (p['android_alarm_on_violation'] as bool?) ?? updated.alarmOnViolation;
      final nextCopy = (p['android_block_copy_paste'] as bool?) ?? updated.blockCopyPaste;

      if (updated.strictHostLock != nextStrict ||
          updated.blockScreenshots != nextShot ||
          updated.clearCacheOnExit != nextCache ||
          updated.requirePinning != nextPin ||
          updated.alarmOnViolation != nextAlarm ||
          updated.blockCopyPaste != nextCopy) {
        updated = updated.copyWith(
          strictHostLock: nextStrict,
          blockScreenshots: nextShot,
          clearCacheOnExit: nextCache,
          requirePinning: nextPin,
          alarmOnViolation: nextAlarm,
          blockCopyPaste: nextCopy,
        );
        changed = true;
      }
    }

    return changed ? updated : null;
  }

  Future<Map<String, dynamic>?> lookupStudent({
    required ExamConfig config,
    required String studentNumber,
  }) async {
    final clean = studentNumber.trim();
    if (clean.isEmpty) return null;

    final baseUrl = normalizeServerUrl(config.remoteServerUrl);
    final uri = Uri.tryParse(
      '$baseUrl/api/student_lookup.php?no_peserta=${Uri.encodeComponent(clean)}',
    );
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 4)
      ..idleTimeout = const Duration(seconds: 2);
    try {
      final req = await client.getUrl(uri);
      req.headers.set('User-Agent', 'ExamBroKu-Android/2.0');
      req.headers.set('Accept', 'application/json');
      final resp = await req.close().timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return null;
      final text = await resp.transform(utf8.decoder).join();
      final map = jsonDecode(text) as Map<String, dynamic>;
      if ((map['ok'] as bool?) == true && (map['found'] as bool?) == true) {
        return map['student'] as Map<String, dynamic>?;
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<String?> testPanelConnection({
    required ExamConfig probeConfig,
  }) async {
    final res = await probePanelConnection(
      probeConfig: probeConfig.copyWith(remoteControlEnabled: true),
    );
    return res.error;
  }
}
