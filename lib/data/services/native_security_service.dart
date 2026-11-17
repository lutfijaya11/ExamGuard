import 'package:flutter/services.dart';

class DeviceSecurityStatus {
  const DeviceSecurityStatus({
    required this.isDeviceOwner,
    required this.isPinned,
    required this.isInMultiWindow,
    required this.externalDisplayCount,
    required this.batteryLevel,
    this.wifiConnected = false,
    this.wifiEnabled = false,
    this.isWifiSettingsActive = false,
    this.isAccessibilityRunning = false,
  });

  final bool isDeviceOwner;
  final bool isPinned;
  final bool isInMultiWindow;
  final int externalDisplayCount;
  final int batteryLevel;
  final bool wifiConnected;
  final bool wifiEnabled;
  final bool isWifiSettingsActive;
  final bool isAccessibilityRunning;

  factory DeviceSecurityStatus.fromMap(Map<dynamic, dynamic> map) {
    return DeviceSecurityStatus(
      isDeviceOwner: (map['isDeviceOwner'] as bool?) ?? false,
      isPinned: (map['isPinned'] as bool?) ?? false,
      isInMultiWindow: (map['isInMultiWindow'] as bool?) ?? false,
      externalDisplayCount: (map['externalDisplayCount'] as num?)?.toInt() ?? 0,
      batteryLevel: (map['batteryLevel'] as num?)?.toInt() ?? -1,
      wifiConnected: (map['wifiConnected'] as bool?) ?? false,
      wifiEnabled: (map['wifiEnabled'] as bool?) ?? false,
      isWifiSettingsActive: (map['isWifiSettingsActive'] as bool?) ?? false,
      isAccessibilityRunning: (map['isAccessibilityRunning'] as bool?) ?? false,
    );
  }
}

class WifiNetworkItem {
  const WifiNetworkItem({
    required this.ssid,
    required this.bssid,
    required this.level,
    required this.signalLevel,
    required this.isSecure,
    required this.capabilities,
  });

  final String ssid;
  final String bssid;
  final int level;
  final int signalLevel;
  final bool isSecure;
  final String capabilities;

  factory WifiNetworkItem.fromMap(Map<dynamic, dynamic> map) {
    return WifiNetworkItem(
      ssid: (map['ssid'] as String?) ?? '',
      bssid: (map['bssid'] as String?) ?? '',
      level: (map['level'] as num?)?.toInt() ?? -100,
      signalLevel: (map['signalLevel'] as num?)?.toInt() ?? 1,
      isSecure: (map['isSecure'] as bool?) ?? false,
      capabilities: (map['capabilities'] as String?) ?? '',
    );
  }
}

class CurrentWifiInfo {
  const CurrentWifiInfo({
    required this.connected,
    required this.ssid,
    required this.bssid,
    required this.ipAddress,
    required this.signalLevel,
  });

  final bool connected;
  final String ssid;
  final String bssid;
  final String ipAddress;
  final int signalLevel;

  factory CurrentWifiInfo.fromMap(Map<dynamic, dynamic> map) {
    return CurrentWifiInfo(
      connected: (map['connected'] as bool?) ?? false,
      ssid: (map['ssid'] as String?) ?? '',
      bssid: (map['bssid'] as String?) ?? '',
      ipAddress: (map['ipAddress'] as String?) ?? '',
      signalLevel: (map['signalLevel'] as num?)?.toInt() ?? 0,
    );
  }
}

typedef SecurityViolationCallback = void Function(String code, String reason);

class NativeSecurityService {
  static const MethodChannel _channel = MethodChannel('id.sch.exambroku/security');

  SecurityViolationCallback? _violationCallback;

  NativeSecurityService() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onSecurityViolation') {
        final args = call.arguments as Map<dynamic, dynamic>? ?? {};
        final code = (args['code'] as String?) ?? 'unknown';
        final reason = (args['reason'] as String?) ?? 'Pelanggaran keamanan terdeteksi.';
        _violationCallback?.call(code, reason);
      }
    });
  }

  void setViolationListener(SecurityViolationCallback? callback) {
    _violationCallback = callback;
  }

  Future<DeviceSecurityStatus> enableExamLock({
    required bool requirePinning,
    required bool blockScreenshots,
  }) async {
    final result = await _channel.invokeMapMethod<dynamic, dynamic>(
      'enableExamLock',
      {
        'requirePinning': requirePinning,
        'blockScreenshots': blockScreenshots,
      },
    );
    return DeviceSecurityStatus.fromMap(result ?? {});
  }

  Future<void> disableExamLock() async {
    await _channel.invokeMethod<void>('disableExamLock');
  }

  Future<void> unlockViolation() async {
    try {
      await _channel.invokeMethod<void>('unlockViolation');
    } catch (_) {}
  }

  Future<void> exitApp() async {
    try {
      await _channel.invokeMethod<void>('exitApp');
    } catch (_) {
      try {
        await SystemNavigator.pop();
      } catch (_) {}
    }
  }

  Future<DeviceSecurityStatus> getSecurityStatus() async {
    final result = await _channel.invokeMapMethod<dynamic, dynamic>('getSecurityStatus');
    return DeviceSecurityStatus.fromMap(result ?? {});
  }

  Future<void> triggerViolationAlarm() async {
    await _channel.invokeMethod<void>('triggerViolationAlarm');
  }

  Future<void> reapplyImmersive() async {
    await _channel.invokeMethod<void>('reapplyImmersive');
  }

  Future<bool> openWifiSettings() async {
    final opened = await _channel.invokeMethod<bool>('openWifiSettings');
    return opened ?? false;
  }

  Future<bool> openAccessibilitySettings() async {
    final opened = await _channel.invokeMethod<bool>('openAccessibilitySettings');
    return opened ?? false;
  }

  Future<List<WifiNetworkItem>> scanWifiNetworks() async {
    final list = await _channel.invokeListMethod<dynamic>('scanWifiNetworks');
    if (list == null) return [];
    return list
        .whereType<Map<dynamic, dynamic>>()
        .map(WifiNetworkItem.fromMap)
        .toList();
  }

  Future<CurrentWifiInfo> getCurrentWifiInfo() async {
    final map = await _channel.invokeMapMethod<dynamic, dynamic>('getCurrentWifiInfo');
    return CurrentWifiInfo.fromMap(map ?? {});
  }

  Future<Map<String, dynamic>> connectToWifi(String ssid, String password) async {
    final res = await _channel.invokeMapMethod<dynamic, dynamic>(
      'connectToWifi',
      {
        'ssid': ssid,
        'password': password,
      },
    );
    return {
      'success': (res?['success'] as bool?) ?? false,
      'message': (res?['message'] as String?) ?? '',
    };
  }

  Future<bool> disconnectWifi() async {
    final disconnected = await _channel.invokeMethod<bool>('disconnectWifi');
    return disconnected ?? false;
  }

  Future<void> setWifiDialogActive(bool active) async {
    try {
      await _channel.invokeMethod<void>('setWifiDialogActive', {'active': active});
    } catch (_) {}
  }

  Future<bool> resetNetworkRoute() async {
    try {
      final res = await _channel.invokeMethod<bool>('resetNetworkRoute');
      return res ?? true;
    } catch (_) {
      return false;
    }
  }
}
