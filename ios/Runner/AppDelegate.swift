import UIKit
import Flutter
import AudioToolbox

@main
@objc class AppDelegate: FlutterAppDelegate {
    private var methodChannel: FlutterMethodChannel?
    private var isExamActive: Bool = false
    private var secureField: UITextField?
    private var dynamicAssessmentSession: AnyObject?

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
                    self.startAssessmentSessionIfNeeded()
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

        // Pengawas rekaman layar & tangkapan layar bawaan iOS
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleGuidedAccessChange),
            name: UIAccessibility.guidedAccessStatusDidChangeNotification,
            object: nil
        )

        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    private func enableExamLock(blockScreenshots: Bool) {
        isExamActive = true
        UIApplication.shared.isIdleTimerDisabled = true

        startAssessmentSessionIfNeeded()

        if blockScreenshots {
            enableSecureScreenLayer()
        }

        applyScreenLocks()
    }

    private func disableExamLock() {
        isExamActive = false
        UIApplication.shared.isIdleTimerDisabled = false

        stopAssessmentSessionIfNeeded()
        disableSecureScreenLayer()
    }

    private func startAssessmentSessionIfNeeded() {
        // Dynamic Assessment Session Loader (Aman dari linker error)
        guard dynamicAssessmentSession == nil else { return }
        if let configClass = NSClassFromString("AEAssessmentConfiguration") as? NSObject.Type,
           let sessionClass = NSClassFromString("AEAssessmentSession") as? NSObject.Type {
            let config = configClass.init()
            // Inisialisasi AEAssessmentSession(configuration: config) via reflection
            let allocSession = sessionClass.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue()
            if let sessionInstance = allocSession?.perform(NSSelectorFromString("initWithConfiguration:"), with: config)?.takeUnretainedValue() {
                self.dynamicAssessmentSession = sessionInstance
                _ = sessionInstance.perform(NSSelectorFromString("begin"))
            }
        }
    }

    private func stopAssessmentSessionIfNeeded() {
        if let session = dynamicAssessmentSession {
            _ = session.perform(NSSelectorFromString("end"))
            dynamicAssessmentSession = nil
        }
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
        if let session = dynamicAssessmentSession {
            let active = session.perform(NSSelectorFromString("isActive")) != nil
            if active {
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

    @objc private func handleGuidedAccessChange() {
        if isExamActive && !UIAccessibility.isGuidedAccessEnabled {
            notifyViolation(code: "unpinned", reason: "Peringatan: Akses Terpandu (Guided Access) dilepas oleh peserta!")
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
