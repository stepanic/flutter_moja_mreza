import Flutter
import UIKit

public class FlutterMojaMrezaPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "flutter_moja_mreza", binaryMessenger: registrar.messenger())
    let instance = FlutterMojaMrezaPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    Task { @MainActor in
      let sesija = MojaMrezaSesija.shared
      do {
        switch call.method {
        case "getPlatformVersion":
          result("iOS " + UIDevice.current.systemVersion)
        case "prijava":
          result(try await sesija.prijava())
        case "dohvati":
          result(try await sesija.dohvati(args?["putanja"] as? String ?? "/"))
        case "napredak":
          sesija.napredak(args?["poruka"] as? String ?? "")
          result(nil)
        case "zatvori":
          sesija.zatvori()
          result(nil)
        case "odjava":
          await sesija.odjava()
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      } catch let greska as MojaMrezaGreska {
        result(FlutterError(code: greska.kod, message: greska.poruka, details: nil))
      } catch {
        result(FlutterError(code: "mreza", message: error.localizedDescription, details: nil))
      }
    }
  }
}
