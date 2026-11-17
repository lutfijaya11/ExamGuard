import 'package:exambroku_android/data/repositories/exam_config_repository.dart';
import 'package:exambroku_android/data/services/native_security_service.dart';
import 'package:exambroku_android/ui/features/launcher/view_models/launcher_view_model.dart';
import 'package:exambroku_android/ui/features/launcher/views/launcher_view.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ExamBroKuApp());
}

class ExamBroKuApp extends StatefulWidget {
  const ExamBroKuApp({super.key});

  @override
  State<ExamBroKuApp> createState() => _ExamBroKuAppState();
}

class _ExamBroKuAppState extends State<ExamBroKuApp> {
  final _repository = ExamConfigRepository();
  final _securityService = NativeSecurityService();
  late final LauncherViewModel _launcherViewModel = LauncherViewModel(
    repository: _repository,
    securityService: _securityService,
  );

  @override
  void dispose() {
    _launcherViewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ExamGuard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.light(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFFF1F5F9),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          brightness: Brightness.light,
        ),
      ),
      home: LauncherView(
        viewModel: _launcherViewModel,
        repository: _repository,
        securityService: _securityService,
      ),
    );
  }
}
