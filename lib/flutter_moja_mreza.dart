
import 'flutter_moja_mreza_platform_interface.dart';

class FlutterMojaMreza {
  Future<String?> getPlatformVersion() {
    return FlutterMojaMrezaPlatform.instance.getPlatformVersion();
  }
}
