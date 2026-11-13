import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    let hapticChannel = FlutterMethodChannel(name: "com.example.mycorvia/haptic",
                                              binaryMessenger: controller.binaryMessenger)
    hapticChannel.setMethodCallHandler({
      (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      if call.method == "isHapticSupported" {
        #if targetEnvironment(simulator)
        result(false)
        #else
        // Modern physical iPhones (iPhone 7 and later) all support haptic feedback
        result(true)
        #endif
      } else {
        result(FlutterMethodNotImplemented)
      }
    })

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
