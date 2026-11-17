import 'dart:math';

class ExamConfig {
  static const String defaultAdminPin = '123456';
  static const String lockedPanelUrl = 'https://cbtpanel.mmc.biz.id';
  static const String lockedCbtHost = '116.193.190.12';

  const ExamConfig({
    this.schoolName = 'MAS AL HUDA',
    this.schoolLogoBase64 = '',
    required this.examTitle,
    required this.protocol,
    required this.host,
    required this.port,
    required this.path,
    required this.adminPinHash,
    required this.adminPinSalt,
    required this.pinIterations,
    required this.isDefaultPin,
    required this.deviceId,
    required this.studentName,
    required this.studentId,
    required this.remoteControlEnabled,
    required this.remoteServerUrl,
    required this.remoteApiToken,
    required this.syncUrlFromServer,
    this.examGateMode = 'FREE_OR_REMOTE',
    this.setupCompleted = false,
    required this.strictHostLock,
    required this.requirePinning,
    required this.blockScreenshots,
    required this.alarmOnViolation,
    required this.blockCopyPaste,
    required this.clearCacheOnExit,
  });

  final String schoolName;
  final String schoolLogoBase64;
  final String examTitle;
  final String protocol;
  final String host;
  final int port;
  final String path;
  final String adminPinHash;
  final String adminPinSalt;
  final int pinIterations;
  final bool isDefaultPin;
  final String deviceId;
  final String studentName;
  final String studentId;
  final bool remoteControlEnabled;
  final String remoteServerUrl;
  final String remoteApiToken;
  final bool syncUrlFromServer;
  final String examGateMode;
  final bool setupCompleted;
  final bool strictHostLock;
  final bool requirePinning;
  final bool blockScreenshots;
  final bool alarmOnViolation;
  final bool blockCopyPaste;
  final bool clearCacheOnExit;

  static String generateDeviceId() {
    final rng = Random.secure();
    final buf = StringBuffer('and_');
    for (var i = 0; i < 16; i++) {
      buf.write(rng.nextInt(16).toRadixString(16));
    }
    return buf.toString();
  }

  factory ExamConfig.initial({
    required String adminPinHash,
    required String adminPinSalt,
    int pinIterations = 20000,
    String? deviceId,
  }) {
    return ExamConfig(
      schoolName: 'MAS AL HUDA',
      examTitle: 'Sumatif Akhir Semester',
      protocol: 'http',
      host: lockedCbtHost,
      port: 9988,
      path: '/',
      adminPinHash: adminPinHash,
      adminPinSalt: adminPinSalt,
      pinIterations: pinIterations,
      isDefaultPin: true,
      deviceId: (deviceId != null && deviceId.isNotEmpty)
          ? deviceId
          : generateDeviceId(),
      studentName: '',
      studentId: '',
      remoteControlEnabled: true,
      remoteServerUrl: lockedPanelUrl,
      remoteApiToken: '',
      syncUrlFromServer: true,
      examGateMode: 'FREE_OR_REMOTE',
      setupCompleted: true,
      strictHostLock: true,
      requirePinning: true,
      blockScreenshots: true,
      alarmOnViolation: true,
      blockCopyPaste: true,
      clearCacheOnExit: true,
    );
  }

  ExamConfig copyWith({
    String? schoolName,
    String? schoolLogoBase64,
    String? examTitle,
    String? protocol,
    String? host,
    int? port,
    String? path,
    String? adminPinHash,
    String? adminPinSalt,
    int? pinIterations,
    bool? isDefaultPin,
    String? deviceId,
    String? studentName,
    String? studentId,
    bool? remoteControlEnabled,
    String? remoteServerUrl,
    String? remoteApiToken,
    bool? syncUrlFromServer,
    String? examGateMode,
    bool? setupCompleted,
    bool? strictHostLock,
    bool? requirePinning,
    bool? blockScreenshots,
    bool? alarmOnViolation,
    bool? blockCopyPaste,
    bool? clearCacheOnExit,
  }) {
    return ExamConfig(
      examTitle: examTitle ?? this.examTitle,
      protocol: protocol ?? this.protocol,
      host: host ?? this.host,
      port: port ?? this.port,
      path: path ?? this.path,
      adminPinHash: adminPinHash ?? this.adminPinHash,
      adminPinSalt: adminPinSalt ?? this.adminPinSalt,
      pinIterations: pinIterations ?? this.pinIterations,
      isDefaultPin: isDefaultPin ?? this.isDefaultPin,
      deviceId: deviceId ?? this.deviceId,
      studentName: studentName ?? this.studentName,
      studentId: studentId ?? this.studentId,
      remoteControlEnabled: remoteControlEnabled ?? this.remoteControlEnabled,
      remoteServerUrl: remoteServerUrl ?? this.remoteServerUrl,
      remoteApiToken: remoteApiToken ?? this.remoteApiToken,
      syncUrlFromServer: syncUrlFromServer ?? this.syncUrlFromServer,
      examGateMode: examGateMode ?? this.examGateMode,
      setupCompleted: setupCompleted ?? this.setupCompleted,
      strictHostLock: strictHostLock ?? this.strictHostLock,
      requirePinning: requirePinning ?? this.requirePinning,
      blockScreenshots: blockScreenshots ?? this.blockScreenshots,
      alarmOnViolation: alarmOnViolation ?? this.alarmOnViolation,
      blockCopyPaste: blockCopyPaste ?? this.blockCopyPaste,
      clearCacheOnExit: clearCacheOnExit ?? this.clearCacheOnExit,
      schoolName: schoolName ?? this.schoolName,
      schoolLogoBase64: schoolLogoBase64 ?? this.schoolLogoBase64,
    );
  }

  Map<String, dynamic> toJson() => {
        'schoolName': schoolName,
        'schoolLogoBase64': schoolLogoBase64,
        'examTitle': examTitle,
        'protocol': protocol,
        'host': host,
        'port': port,
        'path': path,
        'adminPinHash': adminPinHash,
        'adminPinSalt': adminPinSalt,
        'pinIterations': pinIterations,
        'isDefaultPin': isDefaultPin,
        'deviceId': deviceId,
        'studentName': studentName,
        'studentId': studentId,
        'remoteControlEnabled': remoteControlEnabled,
        'remoteServerUrl': remoteServerUrl,
        'remoteApiToken': remoteApiToken,
        'syncUrlFromServer': syncUrlFromServer,
        'examGateMode': examGateMode,
        'setupCompleted': setupCompleted,
        'strictHostLock': strictHostLock,
        'requirePinning': requirePinning,
        'blockScreenshots': blockScreenshots,
        'alarmOnViolation': alarmOnViolation,
        'blockCopyPaste': blockCopyPaste,
        'clearCacheOnExit': clearCacheOnExit,
      };

  factory ExamConfig.fromJson(Map<String, dynamic> json) {
    final parsedId = (json['deviceId'] as String?) ?? '';
    return ExamConfig(
      schoolName: (json['schoolName'] as String?) ?? 'ExamGuard CBT School',
      schoolLogoBase64: (json['schoolLogoBase64'] as String?) ?? '',
      examTitle: (json['examTitle'] as String?) ?? 'Ujian CBT Terpadu',
      protocol: (json['protocol'] as String?) ?? 'https',
      host: (json['host'] as String?) ?? 'contoh-ujian.sekolah.sch.id',
      port: (json['port'] as num?)?.toInt() ?? 443,
      path: (json['path'] as String?) ?? '/',
      adminPinHash: (json['adminPinHash'] as String?) ?? '',
      adminPinSalt: (json['adminPinSalt'] as String?) ?? '',
      pinIterations: (json['pinIterations'] as num?)?.toInt() ?? 20000,
      isDefaultPin: (json['isDefaultPin'] as bool?) ?? true,
      deviceId: parsedId.isNotEmpty ? parsedId : generateDeviceId(),
      studentName: (json['studentName'] as String?) ?? '',
      studentId: (json['studentId'] as String?) ?? '',
      remoteControlEnabled: (json['remoteControlEnabled'] as bool?) ?? false,
      remoteServerUrl:
          (json['remoteServerUrl'] as String?) ?? 'http://192.168.1.10:8000',
      remoteApiToken: (json['remoteApiToken'] as String?) ?? '',
      syncUrlFromServer: (json['syncUrlFromServer'] as bool?) ?? true,
      examGateMode: (json['examGateMode'] as String?) == 'ADMIN_ONLY'
          ? 'ADMIN_ONLY'
          : 'FREE_OR_REMOTE',
      setupCompleted: (json['setupCompleted'] as bool?) ??
          (((json['remoteControlEnabled'] as bool?) ?? false) ||
              ((json['host'] as String?) ?? 'contoh-ujian.sekolah.sch.id') !=
                  'contoh-ujian.sekolah.sch.id'),
      strictHostLock: (json['strictHostLock'] as bool?) ?? true,
      requirePinning: (json['requirePinning'] as bool?) ?? true,
      blockScreenshots: (json['blockScreenshots'] as bool?) ?? true,
      alarmOnViolation: (json['alarmOnViolation'] as bool?) ?? true,
      blockCopyPaste: (json['blockCopyPaste'] as bool?) ?? true,
      clearCacheOnExit: (json['clearCacheOnExit'] as bool?) ?? true,
    );
  }
}

class UrlValidationResult {
  const UrlValidationResult({this.uri, this.error});

  final Uri? uri;
  final String? error;

  bool get isValid => uri != null && error == null;
}

class UrlPortHelper {
  static UrlValidationResult validateAndBuildUri({
    required String protocol,
    required String host,
    required int port,
    required String path,
  }) {
    final cleanProto = protocol.trim().toLowerCase();
    if (cleanProto != 'http' && cleanProto != 'https') {
      return const UrlValidationResult(error: 'Protokol harus http atau https.');
    }

    var cleanHost = host.trim();
    if (cleanHost.toLowerCase().startsWith('http://') ||
        cleanHost.toLowerCase().startsWith('https://')) {
      final parsed = Uri.tryParse(cleanHost);
      if (parsed != null && parsed.host.isNotEmpty) {
        cleanHost = parsed.host;
      }
    }
    final slashIdx = cleanHost.indexOf('/');
    if (slashIdx >= 0) {
      cleanHost = cleanHost.substring(0, slashIdx);
    }

    if (cleanHost.isEmpty || cleanHost.contains(' ')) {
      return const UrlValidationResult(
        error: 'Host / IP / Domain ujian tidak boleh kosong atau mengandung spasi.',
      );
    }

    if (port < 1 || port > 65535) {
      return const UrlValidationResult(
        error: 'Port harus di antara 1 sampai 65535.',
      );
    }

    var cleanPath = path.trim();
    if (cleanPath.isEmpty) cleanPath = '/';
    if (!cleanPath.startsWith('/')) cleanPath = '/$cleanPath';

    try {
      final uri = Uri(
        scheme: cleanProto,
        host: cleanHost,
        port: port,
        path: cleanPath,
      );
      if (uri.host.isEmpty) {
        return const UrlValidationResult(error: 'Format Host tidak valid.');
      }
      return UrlValidationResult(uri: uri);
    } catch (e) {
      return UrlValidationResult(error: 'URL tidak valid: $e');
    }
  }

  static String formatDisplayUrl(ExamConfig config) {
    final res = validateAndBuildUri(
      protocol: config.protocol,
      host: config.host,
      port: config.port,
      path: config.path,
    );
    if (!res.isValid || res.uri == null) return '(URL belum valid)';
    final u = res.uri!;
    return '${u.scheme}://${u.host}:${u.port}${u.path}';
  }

  static bool isNavigationAllowed(Uri? target, ExamConfig config) {
    if (target == null) return false;
    final scheme = target.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return false;

    if (!config.strictHostLock) return true;

    final configured = validateAndBuildUri(
      protocol: config.protocol,
      host: config.host,
      port: config.port,
      path: config.path,
    );
    if (!configured.isValid || configured.uri == null) return false;

    final cfgUri = configured.uri!;
    final targetHost = target.host.toLowerCase();
    final cfgHost = cfgUri.host.toLowerCase();
    final isIp = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$').hasMatch(cfgHost) ||
        cfgHost.contains(':');

    var sameHost = targetHost == cfgHost;
    if (!sameHost && !isIp) {
      final baseCfg = cfgHost.startsWith('www.') ? cfgHost.substring(4) : cfgHost;
      sameHost = targetHost == baseCfg || targetHost.endsWith('.$baseCfg');
    }

    final samePort = target.port == cfgUri.port ||
        (cfgUri.port == 80 && scheme == 'https' && target.port == 443);
    return sameHost && samePort;
  }
}
