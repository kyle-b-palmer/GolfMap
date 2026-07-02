import ActivityKit
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let didFinish = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    registerNativeBridgesIfNeeded()
    DispatchQueue.main.async {
      WatchConnectivityBridge.shared.activate()
      self.startLiveActivityLifecycleObserver()
    }
    return didFinish
  }

  override func applicationWillTerminate(_ application: UIApplication) {
    notifyWatchRoundEndedIfNeeded()
    super.applicationWillTerminate(application)
  }

  override func applicationWillEnterForeground(_ application: UIApplication) {
    LiveActivityBridge.notifyForeground()
    super.applicationWillEnterForeground(application)
  }

  private func startLiveActivityLifecycleObserver() {
    guard #available(iOS 16.1, *) else { return }

    Task {
      for await activity in Activity<LiveActivitiesAppAttributes>.activityUpdates {
        guard activity.activityState == .ended || activity.activityState == .dismissed else {
          continue
        }

        await MainActor.run {
          if Activity<LiveActivitiesAppAttributes>.activities.isEmpty,
             UIApplication.shared.applicationState != .active {
            self.notifyWatchRoundEndedIfNeeded()
          }
        }
      }
    }
  }

  private func notifyWatchRoundEndedIfNeeded() {
    let sessionId = GolfRoundLiveActivityController.shared.activeSessionId()
    guard GolfRoundLiveActivityController.shared.loadState() != nil
      || GolfRoundLiveActivityController.shared.isRoundHostActive() else {
      return
    }

    GolfRoundLiveActivityController.shared.clearSharedState()
    WatchConnectivityBridge.shared.pushSessionReset(sessionId: sessionId)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerLiveActivityBridge(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "HealthWorkoutBridge") {
      HealthWorkoutBridge.register(with: registrar)
    }
    if #available(iOS 17.0, *) {
      _ = GolfRoundLiveActivityIntentsRegistration.intents
    }
  }

  private func registerNativeBridgesIfNeeded() {
    if let controller = window?.rootViewController as? FlutterViewController {
      registerLiveActivityBridge(with: controller.engine)
    }
  }

  private func registerLiveActivityBridge(with registry: FlutterPluginRegistry) {
    if let registrar = registry.registrar(forPlugin: "LiveActivityBridge") {
      LiveActivityBridge.register(with: registrar)
    }
  }
}
