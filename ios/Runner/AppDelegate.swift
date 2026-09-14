import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "com.musclememory/rest_timer",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      let center = UNUserNotificationCenter.current()
      switch call.method {
      case "schedule":
        guard
          let arguments = call.arguments as? [String: Any],
          let seconds = arguments["seconds"] as? Int
        else {
          result(FlutterError(code: "invalid_arguments", message: nil, details: nil))
          return
        }
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
          if let error = error {
            result(FlutterError(code: "notification_permission", message: error.localizedDescription, details: nil))
            return
          }
          guard granted else {
            result(nil)
            return
          }
          center.removePendingNotificationRequests(withIdentifiers: ["musclemory_rest_timer"])
          let content = UNMutableNotificationContent()
          content.title = "MUSCLEMORY"
          content.body = "休憩終了。次のセットへ！"
          content.sound = .default
          let request = UNNotificationRequest(
            identifier: "musclemory_rest_timer",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(max(1, seconds)), repeats: false)
          )
          center.add(request) { error in
            if let error = error {
              result(FlutterError(code: "notification_schedule", message: error.localizedDescription, details: nil))
            } else {
              result(nil)
            }
          }
        }
      case "cancel":
        center.removePendingNotificationRequests(withIdentifiers: ["musclemory_rest_timer"])
        center.removeDeliveredNotifications(withIdentifiers: ["musclemory_rest_timer"])
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
