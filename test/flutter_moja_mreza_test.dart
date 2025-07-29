import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_moja_mreza/flutter_moja_mreza.dart';
import 'package:flutter_moja_mreza/flutter_moja_mreza_platform_interface.dart';
import 'package:flutter_moja_mreza/flutter_moja_mreza_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFlutterMojaMrezaPlatform
    with MockPlatformInterfaceMixin
    implements FlutterMojaMrezaPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final FlutterMojaMrezaPlatform initialPlatform = FlutterMojaMrezaPlatform.instance;

  test('$MethodChannelFlutterMojaMreza is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelFlutterMojaMreza>());
  });

  test('getPlatformVersion', () async {
    FlutterMojaMreza flutterMojaMrezaPlugin = FlutterMojaMreza();
    MockFlutterMojaMrezaPlatform fakePlatform = MockFlutterMojaMrezaPlatform();
    FlutterMojaMrezaPlatform.instance = fakePlatform;

    expect(await flutterMojaMrezaPlugin.getPlatformVersion(), '42');
  });
}
