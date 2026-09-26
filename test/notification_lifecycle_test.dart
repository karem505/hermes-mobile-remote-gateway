import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_mobile/notify.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('resume never cancels native foreground-service notification', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    final methods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      if (call.method == 'getNotificationAppLaunchDetails') return {'notificationLaunchedApp': false};
      return true;
    });
    try {
      await Notify.i.init();
      Notify.i.didChangeAppLifecycleState(AppLifecycleState.paused);
      Notify.i.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      expect(methods, isNot(contains('cancelAll')));
    } finally {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    }
  });
}
