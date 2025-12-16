import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var backgroundCompletionHandler: ((UIBackgroundFetchResult) -> Void)?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Enable background fetch (minimum interval)
    UIApplication.shared.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalMinimum)

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Handle background fetch - called by iOS when it decides to wake the app
  override func application(
    _ application: UIApplication,
    performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    print("DAKAR301: Background fetch triggered by iOS")

    // Store completion handler
    backgroundCompletionHandler = completionHandler

    // Get the Flutter engine
    guard let controller = window?.rootViewController as? FlutterViewController else {
      print("DAKAR301: No FlutterViewController found")
      completionHandler(.failed)
      return
    }

    let channel = FlutterMethodChannel(
      name: "com.dakar301/background",
      binaryMessenger: controller.binaryMessenger
    )

    // First check if there are files in the queue
    channel.invokeMethod("getQueueCount", arguments: nil) { [weak self] result in
      guard let count = result as? Int, count > 0 else {
        print("DAKAR301: No files in queue")
        completionHandler(.noData)
        return
      }

      print("DAKAR301: \(count) files in queue, processing...")

      // Process the queue
      channel.invokeMethod("processQueue", arguments: nil) { result in
        if let success = result as? Bool, success {
          print("DAKAR301: Background upload successful")
          completionHandler(.newData)
        } else {
          print("DAKAR301: Background upload returned no new data")
          completionHandler(.noData)
        }
        self?.backgroundCompletionHandler = nil
      }
    }

    // Timeout after 25 seconds (iOS gives ~30 seconds max)
    DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in
      if self?.backgroundCompletionHandler != nil {
        print("DAKAR301: Background fetch timeout")
        self?.backgroundCompletionHandler?(.noData)
        self?.backgroundCompletionHandler = nil
      }
    }
  }
}
