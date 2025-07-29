import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_moja_mreza_method_channel.dart';

abstract class FlutterMojaMrezaPlatform extends PlatformInterface {
  /// Constructs a FlutterMojaMrezaPlatform.
  FlutterMojaMrezaPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterMojaMrezaPlatform _instance = MethodChannelFlutterMojaMreza();

  /// The default instance of [FlutterMojaMrezaPlatform] to use.
  ///
  /// Defaults to [MethodChannelFlutterMojaMreza].
  static FlutterMojaMrezaPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FlutterMojaMrezaPlatform] when
  /// they register themselves.
  static set instance(FlutterMojaMrezaPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
