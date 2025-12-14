import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Enable background fetch (minimum interval)
    UIApplication.shared.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalMinimum)

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Handle background fetch
  override func application(
    _ application: UIApplication,
    performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    // Get the Flutter engine and call the background upload method
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(name: "com.dakar301/background", binaryMessenger: controller.binaryMessenger)

      channel.invokeMethod("processQueue", arguments: nil) { result in
        if let success = result as? Bool, success {
          completionHandler(.newData)
        } else {
          completionHandler(.noData)
        }
      }

      // Timeout after 25 seconds (iOS gives 30 max)
      DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
        completionHandler(.noData)
      }
    } else {
      completionHandler(.noData)
    }
  }
}
