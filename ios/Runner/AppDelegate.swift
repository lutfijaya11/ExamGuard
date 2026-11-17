import UIKit
import Flutter
import AudioToolbox
#if canImport(AutomaticAssessmentConfiguration)
import AutomaticAssessmentConfiguration
#endif

@available(iOS 13.4, *)
class AssessmentManager: NSObject, AEAssessmentSessionDelegate {
    static let shared = AssessmentManager()
    var session: AEAssessmentSession?
    var onViolation: ((String, String) -> Void)?

    func start() {
        if session == nil {
            let config = AEAssessmentConfiguration()
            if #available(iOS 14.0, *) {
                config.autocorrectMode = .none
                config.spellCheckMode = .none
                config.allowsSpellCheck = false
                config.allowsPredictiveKeyboard = false
                config.allowsActivityContinuation = false
                config.allowsDictation = false
                config.allowsAccessibilitySpeech = false
            }
            let s = AEAssessmentSession(configuration: config)
            s.delegate = self
            self.session = s
            s.begin()
        }
    }

    func stop() {
        session?.end()
        session = nil
    }

    var isActive: Bool {
        return session?.isActive ?? false
    }

    func assessmentSessionDidBegin(_ session: AEAssessmentSession) {}
    func assessmentSession(_ session: AEAssessmentSession, failedToBeginWithError error: Error) {}
    func assessmentSessionWasInterrupted(_ session: AEAssessmentSession) {
        onViolation?("assessment_interrupted", "Sesi ujian terputus atau layar dilepas.")
    }
    func assessmentSessionDidEnd(_ session: AEAssessmentSession) {
        self.session = nil
    }
}

@main
@objc class AppDelegate: FlutterAppDelegate {
    private var methodChannel: FlutterMethodChannel?
    private var isExamActive: Bool = false
    private var secureField: UITextField?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        UIDevice.current.isBatteryMonitoringEnabled = true

        let controller: FlutterViewController = window?.rootViewController as! FlutterViewController
        methodChannel = FlutterMethodChannel(
            name: "id.sch.exambroku/security",
            binaryMessenger: controller.binaryMessenger
        )

        if #available(iOS 13.4, *) {
            AssessmentManager.shared.onViolation = { [weak self] code, reason in
                self?.notifyViolation(code: code, reason: reason)
            }
        }

        methodChannel?.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
            guard let self = self else { return }
            switch call.method {
            case "enableExamLock":
                let args = call.arguments as? [String: Any]
                let blockScreenshots = (args?["blockScreenshots"] as? Bool) ?? true
                self.enableExamLock(blockScreenshots: blockScreenshots)
                result(self.getSecurityStatusMap())

            case "disableExamLock":
                self.disableExamLock()
                result(true)

            case "exitApp":
                self.disableExamLock()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    UIControl().sendAction(#selector(URLSessionTask.suspend), to: UIApplication.shared, for: nil)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        exit(0)
                    }
                }
                result(true)

            case "unlockViolation":
                if self.isExamActive {
                    if #available(iOS 13.4, *) {
                        AssessmentManager.shared.start()
                    }
                }
                result(true)

            case "getSecurityStatus":
                result(self.getSecurityStatusMap())

            case "triggerViolationAlarm":
                self.triggerAlarm()
                result(true)

            case "reapplyImmersive":
                self.applyScreenLocks()
                result(true)

            case "getCurrentWifiInfo":
                result([
                    "connected": true,
                    "ssid": "Apple WiFi",
                    "bssid": "",
                    "ipAddress": "127.0.0.1",
                    "signalLevel": 4
                ])

            case "scanWifiNetworks":
                result([])

            case "connectToWifi", "disconnectWifi", "resetNetworkRoute":
                result(true)

            default:
                result(FlutterMethodNotImplemented)
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenCaptureChange),
            name: UIScreen.capturedDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleUserScreenshot),
            name: UIApplication.userDidTakeScreenshotNotification,
            object: nil
        )

        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    private func enableExamLock(blockScreenshots: Bool) {
        isExamActive = true
        UIApplication.shared.isIdleTimerDisabled = true

        if #available(iOS 13.4, *) {
            AssessmentManager.shared.start()
        }

        if blockScreenshots {
            enableSecureScreenLayer()
        }

        applyScreenLocks()
    }

    private func disableExamLock() {
        isExamActive = false
        UIApplication.shared.isIdleTimerDisabled = false

        if #available(iOS 13.4, *) {
            AssessmentManager.shared.stop()
        }

        disableSecureScreenLayer()
    }

    private func applyScreenLocks() {
        UIApplication.shared.isStatusBarHidden = true
    }

    private func enableSecureScreenLayer() {
        guard secureField == nil, let window = self.window else { return }
        let field = UITextField()
        field.isSecureTextEntry = true
        window.addSubview(field)
        field.centerYAnchor.constraint(equalTo: window.centerYAnchor).isActive = true
        field.centerXAnchor.constraint(equalTo: window.centerXAnchor).isActive = true
        window.layer.superlayer?.addSublayer(field.layer)
        field.layer.sublayers?.first?.addSublayer(window.layer)
        self.secureField = field
    }

    private func disableSecureScreenLayer() {
        secureField?.removeFromSuperview()
        secureField = nil
    }

    private func getSecurityStatusMap() -> [String: Any] {
        var isPinned = false
        if UIAccessibility.isGuidedAccessEnabled {
            isPinned = true
        }
        if #available(iOS 13.4, *) {
            if AssessmentManager.shared.isActive {
                isPinned = true
            }
        }

        let battery = Int(UIDevice.current.batteryLevel * 100)
        let externalDisplays = max(0, UIScreen.screens.count - 1)

        return [
            "isDeviceOwner": isPinned,
            "lockTaskState": isPinned ? 2 : 0,
            "isPinned": isPinned,
            "isInMultiWindow": false,
            "externalDisplayCount": externalDisplays,
            "batteryLevel": battery >= 0 ? battery : 100,
            "wifiConnected": true,
            "wifiEnabled": true,
            "isWifiSettingsActive": false,
            "isAccessibilityRunning": false
        ]
    }

    private func triggerAlarm() {
        AudioServicesPlayAlertSound(kSystemSoundID_Vibrate)
        AudioServicesPlaySystemSound(1005)
    }

    @objc private func handleScreenCaptureChange() {
        if isExamActive && UIScreen.main.isCaptured {
            notifyViolation(code: "screen_recording", reason: "Peringatan: Terdeteksi perekaman layar (Screen Recording) atau AirPlay!")
        }
    }

    @objc private func handleUserScreenshot() {
        if isExamActive {
            notifyViolation(code: "screenshot_attempt", reason: "Peringatan: Tangkapan layar (Screenshot) dilarang selama ujian!")
        }
    }

    private func notifyViolation(code: String, reason: String) {
        DispatchQueue.main.async { [weak self] in
            self?.methodChannel?.invokeMethod("onSecurityViolation", arguments: [
                "code": code,
                "reason": reason
            ])
        }
    }

    override func applicationWillResignActive(_ application: UIApplication) {
        if isExamActive {
            notifyViolation(code: "leave_attempt", reason: "Peserta mencoba beralih aplikasi atau membuka Control Center.")
        }
        super.applicationWillResignActive(application)
    }
}
