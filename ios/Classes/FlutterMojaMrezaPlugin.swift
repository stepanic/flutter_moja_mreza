import Flutter
import UIKit

public class FlutterMojaMrezaPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "flutter_moja_mreza", binaryMessenger: registrar.messenger())
    let instance = FlutterMojaMrezaPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("iOS " + UIDevice.current.systemVersion)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
