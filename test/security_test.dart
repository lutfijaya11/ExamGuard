import 'package:exambroku_android/data/services/crypto_service.dart';
import 'package:exambroku_android/data/services/native_security_service.dart';
import 'package:exambroku_android/data/services/remote_control_service.dart';
import 'package:exambroku_android/domain/models/exam_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UrlPortHelper', () {
    test('builds valid http URL with custom port and path', () {
      final res = UrlPortHelper.validateAndBuildUri(
        protocol: 'http',
        host: '192.168.1.50',
        port: 8080,
        path: '/cbt/login',
      );
      expect(res.isValid, isTrue);
      expect(res.uri.toString(), 'http://192.168.1.50:8080/cbt/login');
    });

    test('builds valid https URL and normalizes leading slash', () {
      final res = UrlPortHelper.validateAndBuildUri(
        protocol: 'https',
        host: 'ujian.sekolah.sch.id',
        port: 8443,
        path: 'ujian',
      );
      expect(res.isValid, isTrue);
      expect(res.uri?.scheme, 'https');
      expect(res.uri?.host, 'ujian.sekolah.sch.id');
      expect(res.uri?.port, 8443);
      expect(res.uri?.path, '/ujian');
    });

    test('rejects invalid port and unsupported schemes', () {
      expect(
        UrlPortHelper.validateAndBuildUri(
          protocol: 'ftp',
          host: '192.168.1.1',
          port: 21,
          path: '/',
        ).isValid,
        isFalse,
      );
      expect(
        UrlPortHelper.validateAndBuildUri(
          protocol: 'http',
          host: '192.168.1.1',
          port: 0,
          path: '/',
        ).isValid,
        isFalse,
      );
      expect(
        UrlPortHelper.validateAndBuildUri(
          protocol: 'http',
          host: '192.168.1.1',
          port: 70000,
          path: '/',
        ).isValid,
        isFalse,
      );
    });

    test('enforces strict host and port navigation lock', () {
      final pair = PinHasher.hashPin('Admin#2026!');
      final cfg = ExamConfig.initial(
        adminPinHash: pair.hashBase64,
        adminPinSalt: pair.saltBase64,
      ).copyWith(
        protocol: 'http',
        host: '192.168.1.50',
        port: 8080,
        path: '/exam',
        strictHostLock: true,
      );

      expect(
        UrlPortHelper.isNavigationAllowed(
          Uri.parse('http://192.168.1.50:8080/exam/soal/1'),
          cfg,
        ),
        isTrue,
      );
      expect(
        UrlPortHelper.isNavigationAllowed(
          Uri.parse('http://192.168.1.50:9090/exam'),
          cfg,
        ),
        isFalse,
      );
      expect(
        UrlPortHelper.isNavigationAllowed(
          Uri.parse('https://google.com'),
          cfg,
        ),
        isFalse,
      );
      expect(
        UrlPortHelper.isNavigationAllowed(
          Uri.parse('intent://scan/#Intent;end'),
          cfg,
        ),
        isFalse,
      );

      final domainCfg = cfg.copyWith(
        protocol: 'http',
        host: 'ujian.sekolah.sch.id',
        port: 80,
        path: '/',
      );
      expect(
        UrlPortHelper.isNavigationAllowed(
          Uri.parse('https://www.ujian.sekolah.sch.id/login'),
          domainCfg,
        ),
        isTrue,
      );
      expect(
        UrlPortHelper.isNavigationAllowed(
          Uri.parse('https://evil.com/ujian.sekolah.sch.id'),
          domainCfg,
        ),
        isFalse,
      );
    });
  });

  group('PinHasher and PinAttemptGuard', () {
    test('hashes and verifies Admin PIN with PBKDF2-SHA256', () {
      final pair = PinHasher.hashPin('Rahasia99');
      final cfg = ExamConfig.initial(
        adminPinHash: pair.hashBase64,
        adminPinSalt: pair.saltBase64,
      );

      expect(PinHasher.verifyPin(cfg, 'Rahasia99'), isTrue);
      expect(PinHasher.verifyPin(cfg, '123456'), isFalse);
      expect(PinHasher.verifyPin(cfg, ''), isFalse);
    });

    test('locks out after 5 consecutive wrong attempts', () {
      final guard = PinAttemptGuard();
      for (var i = 0; i < 4; i++) {
        expect(guard.recordFailure(), 0);
      }
      expect(guard.recordFailure(), 15);
      expect(guard.remainingCooldownSeconds(), greaterThan(0));
      guard.recordSuccess();
      expect(guard.remainingCooldownSeconds(), 0);
    });
  });

  group('RemoteControlService', () {
    test('syncs remote Admin PIN hash and exam URL from PHP server', () {
      final initialPair = PinHasher.hashPin('123456');
      final cfg = ExamConfig.initial(
        adminPinHash: initialPair.hashBase64,
        adminPinSalt: initialPair.saltBase64,
      ).copyWith(remoteControlEnabled: true, syncUrlFromServer: true);

      final newPair = PinHasher.hashPin('AdminPusat88');
      final resp = HeartbeatResult(
        ok: true,
        command: 'NONE',
        commandId: '',
        adminPinSalt: newPair.saltBase64,
        adminPinHash: newPair.hashBase64,
        pinIterations: 20000,
        syncUrlToClients: true,
        examGateMode: 'ADMIN_ONLY',
        securityPolicies: {
          'strict_host_lock': true,
          'block_screenshots': false,
          'clear_cache_on_exit': false,
          'android_require_pinning': false,
          'android_alarm_on_violation': true,
          'android_block_copy_paste': false,
        },
        examConfigMap: {
          'exam_title': 'PAS Semester',
          'protocol': 'http',
          'host': '192.168.10.5',
          'port': 8085,
          'path': '/cbt',
        },
      );

      final synced = RemoteControlService.applyServerSync(cfg, resp);
      expect(synced, isNotNull);
      expect(PinHasher.verifyPin(synced!, 'AdminPusat88'), isTrue);
      expect(PinHasher.verifyPin(synced, '123456'), isFalse);
      expect(synced.host, '192.168.10.5');
      expect(synced.port, 8085);
      expect(synced.examTitle, 'PAS Semester');
      expect(synced.examGateMode, 'ADMIN_ONLY');
      expect(synced.blockScreenshots, isFalse);
      expect(synced.requirePinning, isFalse);
      expect(synced.blockCopyPaste, isFalse);
      expect(synced.alarmOnViolation, isTrue);
    });

    test('setupCompleted defaults true with embedded cbtpanel and preserves backward compatibility in fromJson', () {
      final pair = PinHasher.hashPin('123456');
      final fresh = ExamConfig.initial(
        adminPinHash: pair.hashBase64,
        adminPinSalt: pair.saltBase64,
      );
      expect(fresh.setupCompleted, isTrue);
      expect(fresh.remoteServerUrl, ExamConfig.lockedPanelUrl);

      final legacyRemote = ExamConfig.fromJson({
        ...fresh.toJson(),
        'remoteControlEnabled': true,
      }..remove('setupCompleted'));
      expect(legacyRemote.setupCompleted, isTrue);

      final legacyDefault = ExamConfig.fromJson(
        fresh.toJson()..remove('setupCompleted'),
      );
      expect(legacyDefault.setupCompleted, isTrue);

      expect(
        RemoteControlService.normalizeServerUrl('cbtpanel.mmc.biz.id/exambro/'),
        'https://cbtpanel.mmc.biz.id/exambro',
      );
      expect(
        RemoteControlService.normalizeServerUrl('http://192.168.1.10:8000/'),
        'http://192.168.1.10:8000',
      );
    });

    test('syncs school branding and parses WiFi native status', () {
      final pair = PinHasher.hashPin('123456');
      final cfg = ExamConfig.initial(
        adminPinHash: pair.hashBase64,
        adminPinSalt: pair.saltBase64,
      );

      final resp = HeartbeatResult(
        ok: true,
        command: 'NONE',
        commandId: '',
        adminPinSalt: '',
        adminPinHash: '',
        pinIterations: 20000,
        syncUrlToClients: false,
        examGateMode: 'FREE_OR_REMOTE',
        examConfigMap: const {
          'school_name': 'SMA Negeri 1 Merdeka',
          'school_logo_base64': 'iVBORw0KGgoAAAANSUhEUg==',
          'exam_title': 'Sumatif Akhir Semester',
        },
      );

      final synced = RemoteControlService.applyServerSync(cfg, resp);
      expect(synced, isNotNull);
      expect(synced!.schoolName, 'SMA Negeri 1 Merdeka');
      expect(synced.schoolLogoBase64, 'iVBORw0KGgoAAAANSUhEUg==');
      expect(synced.examTitle, 'Sumatif Akhir Semester');

      final status = DeviceSecurityStatus.fromMap({
        'isDeviceOwner': false,
        'isPinned': true,
        'isInMultiWindow': false,
        'externalDisplayCount': 0,
        'batteryLevel': 88,
        'wifiConnected': true,
        'wifiEnabled': true,
        'isWifiSettingsActive': false,
      });
      expect(status.wifiConnected, isTrue);
      expect(status.wifiEnabled, isTrue);
      expect(status.isWifiSettingsActive, isFalse);
    });
  });
}
