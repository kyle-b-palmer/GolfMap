import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    WatchConnectivityBridge.shared.activate()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func applicationWillEnterForeground(_ application: UIApplication) {
    LiveActivityBridge.notifyForeground()
    super.applicationWillEnterForeground(application)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LiveActivityBridge") {
      LiveActivityBridge.register(with: registrar)
    }
    if #available(iOS 17.0, *) {
      _ = GolfRoundLiveActivityIntentsRegistration.intents
    }
  }
}
