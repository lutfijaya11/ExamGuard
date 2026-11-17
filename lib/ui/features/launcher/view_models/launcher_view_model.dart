import 'package:exambroku_android/data/repositories/exam_config_repository.dart';
import 'package:exambroku_android/data/services/native_security_service.dart';
import 'package:exambroku_android/domain/models/exam_config.dart';
import 'package:flutter/foundation.dart';

class LauncherViewModel extends ChangeNotifier {
  LauncherViewModel({
    required ExamConfigRepository repository,
    required NativeSecurityService securityService,
  })  : _repository = repository,
        _securityService = securityService;

  final ExamConfigRepository _repository;
  final NativeSecurityService _securityService;

  ExamConfig? _config;
  ExamConfig? get config => _config;

  DeviceSecurityStatus? _securityStatus;
  DeviceSecurityStatus? get securityStatus => _securityStatus;

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    try {
      _config = await _repository.loadOrCreateDefault();
      _securityStatus = await _securityService.getSecurityStatus();
    } catch (_) {
      // Security status channel may be unavailable in unit/widget tests
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void updateConfig(ExamConfig updated) {
    _config = updated;
    notifyListeners();
  }

  Future<void> refreshSecurityStatus() async {
    try {
      _securityStatus = await _securityService.getSecurityStatus();
      notifyListeners();
    } catch (_) {}
  }
}
