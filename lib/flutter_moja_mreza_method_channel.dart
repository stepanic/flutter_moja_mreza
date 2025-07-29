import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_moja_mreza_platform_interface.dart';

/// An implementation of [FlutterMojaMrezaPlatform] that uses method channels.
class MethodChannelFlutterMojaMreza extends FlutterMojaMrezaPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_moja_mreza');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
