import UIKit
import Flutter
import LocalAuthentication

@main
@objc class AppDelegate: FlutterAppDelegate {

    private var pendingDeepLink: String?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)

        guard let controller = window?.rootViewController as? FlutterViewController else {
            return super.application(application, didFinishLaunchingWithOptions: launchOptions)
        }
        let messenger = controller.binaryMessenger

        // Register SLM plugin
        SlmPlugin.register(with: messenger)

        // Intent channel (deep link)
        let intentChannel = FlutterMethodChannel(name: "com.kiya.bankinggenie/intent", binaryMessenger: messenger)
        intentChannel.setMethodCallHandler { [weak self] call, result in
            switch call.method {
            case "getInitialIntent":
                result(self?.pendingDeepLink)
                self?.pendingDeepLink = nil
            case "flutterReady":
                let link = self?.pendingDeepLink
                self?.pendingDeepLink = nil
                result(link)
            default:
                result(FlutterMethodNotImplemented)
            }
        }

        // App channel (exitApp — no-op on iOS; apps cannot self-terminate)
        let appChannel = FlutterMethodChannel(name: "com.kiya.bankinggenie/app", binaryMessenger: messenger)
        appChannel.setMethodCallHandler { _, result in
            // iOS does not allow programmatic termination; ignore silently
            result(nil)
        }

        // Biometric channel — delegates to local_auth plugin on iOS, but kept for
        // compatibility with direct MethodChannel calls in home_page.dart
        let bioChannel = FlutterMethodChannel(name: "com.kiya.bankinggenie/biometric", binaryMessenger: messenger)
        bioChannel.setMethodCallHandler { _, result in
            let context = LAContext()
            var error: NSError?
            let canEval = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
            guard canEval else {
                result("success") // fail-open: no biometrics enrolled
                return
            }
            context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Authenticate to access BankingGenie"
            ) { success, _ in
                DispatchQueue.main.async {
                    result(success ? "success" : "cancelled")
                }
            }
        }

        // Metaverse channel — Unity not available on iOS; return gracefully
        let metaChannel = FlutterMethodChannel(name: "com.kiya.bankinggenie/metaverse", binaryMessenger: messenger)
        metaChannel.setMethodCallHandler { _, result in
            result(FlutterError(code: "UNAVAILABLE", message: "Metaverse is not available on iOS.", details: nil))
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // Handle deep links: bankinggenie://register?branchID=X&token=Y
    override func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        guard url.scheme == "bankinggenie" else { return false }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let branchID = components?.queryItems?.first(where: { $0.name == "branchID" })?.value ?? ""
        let token    = components?.queryItems?.first(where: { $0.name == "token" })?.value ?? ""
        let host     = url.host ?? ""
        pendingDeepLink = "{\"host\":\"\(host)\",\"branchID\":\"\(branchID)\",\"token\":\"\(token)\"}"
        return true
    }
}
