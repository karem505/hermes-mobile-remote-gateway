import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_mobile/background_connection.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('hermes/background');
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return {'running': true, 'batteryExempt': false};
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  test('starts once and updates only changed connection state', () async {
    final bg = BackgroundConnection();
    await bg.start();
    await bg.start();
    await bg.update('متصل');
    await bg.update('متصل');
    await bg.stop();
    expect(calls.map((c) => c.method), ['start', 'update', 'stop']);
  });
  test('failed native start remains retryable', () async {
    var attempts = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'start' && attempts++ == 0) {
        throw PlatformException(code: 'foreground_restricted');
      }
      return {'running': true};
    });
    final bg = BackgroundConnection();
    expect(await bg.start(), false);
    expect(await bg.start(), true);
    expect(attempts, 2);
  });
}
