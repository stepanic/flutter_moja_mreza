
import 'package:flutter/material.dart';

import 'flutter_moja_mreza_platform_interface.dart';
export 'moja_mreza_webview_screen.dart';

class FlutterMojaMreza {
  Future<String?> getPlatformVersion() {
    return FlutterMojaMrezaPlatform.instance.getPlatformVersion();
  }

  Future<void> openMojaMreza(BuildContext context) {
    return FlutterMojaMrezaPlatform.instance.openMojaMreza(context);
  }
}
