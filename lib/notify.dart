import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'l10n.dart';

/// Local "agent finished" notifications, only while the app is backgrounded.
class Notify with WidgetsBindingObserver {
  Notify._();
  static final Notify i = Notify._();

  final _p = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool background = false;

  /// Row id of the session whose notification was tapped; the home screen opens it.
  final ValueNotifier<String?> tapped = ValueNotifier(null);

  static AndroidNotificationDetails get _done => AndroidNotificationDetails(
    'agent_done',
    L10n.t('انتهاء المهام'),
    channelDescription: L10n.t('تنبيه عند انتهاء الوكيل من مهمته والتطبيق في الخلفية'),
    importance: Importance.high,
    priority: Priority.high,
    color: Color(0xFFD97757),
    enableVibration: true,
    styleInformation: BigTextStyleInformation(''),
  );
  static AndroidNotificationDetails get _ask => AndroidNotificationDetails(
    'agent_ask',
    L10n.t('طلبات الموافقة'),
    channelDescription: L10n.t('تنبيه عندما يحتاج الوكيل إلى موافقتك أو إجابتك'),
    importance: Importance.max,
    priority: Priority.max,
    color: Color(0xFFD97757),
    enableVibration: true,
  );

  Future<void> init() async {
    if (_ready) return;
    WidgetsBinding.instance.addObserver(this);
    await _p.initialize(
      const InitializationSettings(android: AndroidInitializationSettings('ic_notification')),
      onDidReceiveNotificationResponse: (r) => tapped.value = r.payload,
    );
    final launch = await _p.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) tapped.value = launch!.notificationResponse?.payload;
    await _p
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    _ready = true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    background = state != AppLifecycleState.resumed;
    // Do not cancelAll: it also removes the native foreground-service entry.
    // Completion notifications auto-cancel when tapped.
  }

  Future<void> done({required String title, required String body, String? session, bool failed = false}) async {
    if (!_ready || !background) return;
    final text = body.replaceAll(RegExp(r'MEDIA:\S+'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
    final short = text.length > 180 ? '${text.substring(0, 180)}...' : text;
    await _p.show(
      (session ?? 'x').hashCode & 0x7fffffff,
      failed ? L10n.t('توقف Hermes: {0}', [title]) : L10n.t('انتهى Hermes: {0}', [title]),
      short.isEmpty ? L10n.t('اكتملت المهمة') : short,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _done.channelId,
          _done.channelName,
          channelDescription: _done.channelDescription,
          importance: _done.importance,
          priority: _done.priority,
          color: _done.color,
          styleInformation: BigTextStyleInformation(short.isEmpty ? L10n.t('اكتملت المهمة') : short),
        ),
      ),
      payload: session,
    );
  }

  Future<void> ask({required String title, required String body, String? session}) async {
    if (!_ready || !background) return;
    await _p.show(
      ((session ?? 'x').hashCode + 1) & 0x7fffffff,
      L10n.t('Hermes ينتظرك: {0}', [title]),
      body,
      NotificationDetails(android: _ask),
      payload: session,
    );
  }
}
