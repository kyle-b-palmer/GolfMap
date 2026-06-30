import Flutter
import UIKit

final class LiveActivityBridge: NSObject, FlutterPlugin, FlutterStreamHandler {
    private static var foregroundSink: FlutterEventSink?

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.golfmapapp/live_activity_round",
            binaryMessenger: registrar.messenger()
        )
        let eventChannel = FlutterEventChannel(
            name: "com.golfmapapp/live_activity_round/events",
            binaryMessenger: registrar.messenger()
        )
        let instance = LiveActivityBridge()
        registrar.addMethodCallDelegate(instance, channel: channel)
        eventChannel.setStreamHandler(instance)
    }

    static func notifyForeground() {
        foregroundSink?("foreground")
    }

    static func notifyWatchStateChanged() {
        foregroundSink?("watchState")
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        LiveActivityBridge.foregroundSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        LiveActivityBridge.foregroundSink = nil
        return nil
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "supportsInteractiveControls":
            result(GolfRoundLiveActivitySupport.interactiveControlsAvailable)
        case "syncRoundState":
            guard let args = call.arguments as? [String: Any],
                  let holes = args["holes"] as? [String],
                  let selectedHole = args["selectedHole"] as? String,
                  let courseName = args["courseName"] as? String,
                  let revision = args["revision"] as? Int else {
                result(FlutterError(code: "bad_args", message: "Invalid round state", details: nil))
                return
            }
            let scores = intMap(from: args["scores"])
            let putts = intMap(from: args["putts"])
            let pars = intMap(from: args["pars"])
            let handicaps = intMap(from: args["handicaps"])
            let yardsToGreen = args["yardsToGreen"] as? Int ?? -1
            let greenLatitude = args["greenLatitude"] as? Double ?? 0
            let greenLongitude = args["greenLongitude"] as? Double ?? 0
            GolfRoundLiveActivityController.shared.syncFromFlutter(
                holes: holes,
                selectedHole: selectedHole,
                scores: scores,
                putts: putts,
                pars: pars,
                handicaps: handicaps,
                courseName: courseName,
                yardsToGreen: yardsToGreen,
                revision: revision,
                greenLatitude: greenLatitude,
                greenLongitude: greenLongitude
            )
            WatchConnectivityBridge.shared.pushRoundStateIfNeeded()
            result(nil)
        case "updateGreenTarget":
            guard let args = call.arguments as? [String: Any] else {
                result(FlutterError(code: "bad_args", message: "Invalid green target", details: nil))
                return
            }
            let greenLatitude = args["greenLatitude"] as? Double ?? 0
            let greenLongitude = args["greenLongitude"] as? Double ?? 0
            GolfRoundLiveActivityController.shared.updateGreenTarget(
                greenLatitude: greenLatitude,
                greenLongitude: greenLongitude
            )
            WatchConnectivityBridge.shared.pushRoundStateIfNeeded()
            result(nil)
        case "getSharedGpsYardage":
            guard let state = GolfRoundLiveActivityController.shared.loadState() else {
                result(nil)
                return
            }
            result([
                "yardsToGreen": state.yardsToGreen,
                "gpsRefreshRevision": state.gpsRefreshRevision,
            ])
        case "consumeWidgetChanges":
            let lastRevision = (call.arguments as? [String: Any])?["revision"] as? Int ?? 0
            guard let state = GolfRoundLiveActivityController.shared.consumeChanges(after: lastRevision) else {
                result(nil)
                return
            }
            result([
                "courseName": state.courseName,
                "selectedHole": state.selectedHole,
                "scores": state.scores,
                "putts": state.putts,
                "revision": state.revision,
                "pendingGpsPins": state.pendingGpsPins.map { pin in
                    [
                        "hole": pin.hole,
                        "latitude": pin.latitude,
                        "longitude": pin.longitude,
                    ]
                },
                "pendingGpsPinUndos": state.pendingGpsPinUndos.map { pin in
                    [
                        "hole": pin.hole,
                        "latitude": pin.latitude,
                        "longitude": pin.longitude,
                    ]
                },
            ])
        case "acknowledgePendingGpsPins":
            GolfRoundLiveActivityController.shared.clearPendingGpsPins()
            result(nil)
        case "clearPendingGpsPinUndos":
            GolfRoundLiveActivityController.shared.clearPendingGpsPinUndos()
            result(nil)
        case "reportPinnedShotRemoved":
            guard let args = call.arguments as? [String: Any],
                  let hole = args["hole"] as? String,
                  let latitude = args["latitude"] as? Double,
                  let longitude = args["longitude"] as? Double else {
                result(FlutterError(code: "bad_args", message: "Invalid pin removal", details: nil))
                return
            }
            let scores = intMap(from: args["scores"])
            GolfRoundLiveActivityController.shared.reportPinnedShotRemoved(
                hole: hole,
                latitude: latitude,
                longitude: longitude,
                scores: scores
            )
            WatchConnectivityBridge.shared.pushRoundStateIfNeeded()
            result(nil)
        case "pushWatchRoundState":
            WatchConnectivityBridge.shared.pushRoundStateIfNeeded()
            result(nil)
        case "getSharedRevision":
            result(GolfRoundLiveActivityController.shared.loadState()?.revision ?? 0)
        case "clearSharedState":
            GolfRoundLiveActivityController.shared.clearSharedState()
            WatchConnectivityBridge.shared.pushRoundStateIfNeeded()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func intMap(from value: Any?) -> [String: Int] {
        guard let raw = value as? [String: Any] else { return [:] }
        var mapped: [String: Int] = [:]
        for (key, entry) in raw {
            if let intValue = entry as? Int {
                mapped[key] = intValue
            } else if let number = entry as? NSNumber {
                mapped[key] = number.intValue
            }
        }
        return mapped
    }
}
