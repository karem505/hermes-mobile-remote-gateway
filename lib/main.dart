import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:local_auth/local_auth.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:tabler_icons_next/tabler_icons_next.dart' as tb;

import 'api.dart';
import 'connections.dart';
import 'design.dart';
import 'glass.dart';
import 'notify.dart';
import 'background_connection.dart';
import 'store.dart';

// Hermes Desktop dark tokens (apps/desktop/src/styles.css).
const kBg = D.bg;
const kSide = D.surface;
const kCard = D.surface;
const kMuted = D.surfaceHi;
const kBorder = D.border;
const kFg = D.fg;
const kMfg = D.muted;
const kPrimary = D.accent;
const kOk = D.ok;
const kRec = D.danger;

final _auth = LocalAuthentication();
HermesApi? currentApi;

Future<bool> canUseBiometric() async {
  try {
    return await _auth.canCheckBiometrics && (await _auth.getAvailableBiometrics()).isNotEmpty;
  } catch (_) {
    return false;
  }
}

Future<bool> biometricCheck() async {
  try {
    return await _auth.authenticate(
      localizedReason: 'أكّد هويتك لفتح Hermes',
      persistAcrossBackgrounding: true,
    );
  } catch (_) {
    return false;
  }
}

typedef IconCtor = Widget Function({Color? color, double? width, double? height});

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: kBg,
    systemNavigationBarColor: kBg,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const HermesApp());
  Notify.i.init();
}

ShadColorScheme _scheme() => const ShadColorScheme(
      background: D.bg,
      foreground: D.fg,
      card: kCard,
      cardForeground: kFg,
      popover: kCard,
      popoverForeground: kFg,
      primary: D.accent,
      primaryForeground: D.onAccent,
      secondary: D.surfaceHi,
      secondaryForeground: kFg,
      muted: D.surfaceHi,
      mutedForeground: kMfg,
      accent: D.surfaceHi,
      accentForeground: kFg,
      destructive: D.danger,
      destructiveForeground: D.onAccent,
      border: D.border,
      input: D.border,
      ring: D.accent,
      selection: D.accentWash,
    );

Widget ic(IconCtor f, {double size = 18, Color color = kMfg}) => f(color: color, width: size, height: size);

class HermesApp extends StatelessWidget {
  const HermesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ShadApp.custom(
      themeMode: ThemeMode.dark,
      darkTheme: ShadThemeData(
        brightness: Brightness.dark,
        colorScheme: _scheme(),
        radius: BorderRadius.circular(12),
      ),
      appBuilder: (context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Hermes',
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: kBg,
          colorScheme: const ColorScheme.dark(primary: kPrimary, surface: kBg, error: D.danger),
          splashFactory: NoSplash.splashFactory,
          textSelectionTheme: TextSelectionThemeData(
            cursorColor: D.accent,
            selectionColor: D.accent.withValues(alpha: 0.32),
            selectionHandleColor: D.accent,
          ),
          tooltipTheme: TooltipThemeData(
            decoration: BoxDecoration(color: D.surfaceTop, borderRadius: BorderRadius.circular(8),
                border: Border.all(color: D.borderSoft)),
            textStyle: const TextStyle(color: D.fg, fontSize: 12),
          ),
          pageTransitionsTheme: const PageTransitionsTheme(builders: {
            TargetPlatform.android: DPageTransitions(),
          }),
        ),
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => ShadAppBuilder(child: child!),
        home: const Boot(),
      ),
    );
  }
}

/// Loads saved credentials; routes to login or home.
class Boot extends StatefulWidget {
  const Boot({super.key});
  @override
  State<Boot> createState() => _BootState();
}

class _BootState extends State<Boot> {
  HermesApi? api;
  bool ready = false;
  bool locked = false;
  int _epoch = 0; // bumps on every gateway switch so HomePage rebuilds its store

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final a = await HermesApi.load();
    final bio = a != null && await HermesApi.biometricEnabled();
    setState(() {
      api = a;
      locked = bio;
      ready = true;
    });
    if (bio) _unlock();
  }

  Future<void> _unlock() async {
    if (await biometricCheck()) setState(() => locked = false);
  }

  Future<void> _afterFirstLogin(HermesApi a) async {
    setState(() => api = a);
    if (!await canUseBiometric() || !mounted) return;
    final yes = await showDDialog<bool>(context, (c) => DDialog(
      title: 'الدخول بالبصمة',
      body: 'حُفظت بيانات الدخول على هذا الجهاز. هل تريد طلب البصمة عند فتح التطبيق؟',
      actions: [
        DBtn(label: 'لاحقًا', kind: DBtnKind.outline, onPressed: () => Navigator.of(c).pop(false)),
        DBtn(label: 'تفعيل', onPressed: () => Navigator.of(c).pop(true)),
      ],
    ));
    if (yes == true && await biometricCheck()) await HermesApi.setBiometric(true);
  }

  Future<void> _openConnections() async {
    final a = api;
    if (a == null) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ConnectionsPage(
        api: a,
        onSwitched: (n) {
          Navigator.of(context).pop();
          setState(() {
            api = n;
            _epoch++;
          });
        },
        onLoggedOut: () {
          Navigator.of(context).pop();
          setState(() => api = null);
        },
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (!ready) return const Scaffold(body: Center(child: CircularProgressIndicator(color: kPrimary)));
    if (api == null) return LoginPage(onDone: _afterFirstLogin);
    if (locked) {
      return Scaffold(
        body: DAmbient(child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ic(tb.Fingerprint.new, size: 56, color: kFg),
            const SizedBox(height: 16),
            const Text('Hermes مقفل', style: TextStyle(color: kFg, fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 20),
            DBtn(label: 'فتح بالبصمة', icon: tb.Fingerprint.new, onPressed: _unlock),
          ]),
        )),
      );
    }
    return HomePage(
      key: ValueKey('$_epoch|${api!.connId}|${api!.baseUrl}|${api!.user}'),
      api: api!,
      onConnections: _openConnections,
      onLogout: () async {
        await api!.logout();
        setState(() => api = null);
      },
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.onDone});
  final void Function(HermesApi) onDone;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final url = TextEditingController();
  final user = TextEditingController();
  final pass = TextEditingController();
  bool busy = false;
  String? error;
  List<Conn> saved = [];
  String? usingId;

  @override
  void initState() {
    super.initState();
    () async {
      try {
        final s = await Connections.instance.list();
        final act = await Connections.instance.active();
        if (!mounted) return;
        setState(() {
          saved = s;
          if (act != null) {
            url.text = act.url;
            user.text = act.user;
            pass.text = act.pass;
          }
        });
      } catch (_) {}
    }();
  }

  Future<void> _use(Conn c) async {
    setState(() {
      url.text = c.url;
      user.text = c.user;
      pass.text = c.pass;
      usingId = c.id;
    });
    await submit(of: c.id);
  }

  Future<void> _addRemote() async {
    final r = await Navigator.of(context).push<Object>(MaterialPageRoute(
      builder: (_) => const ConnectionEditorPage(),
    ));
    if (!mounted) return;
    if (r is HermesApi) widget.onDone(r);
  }

  Widget _savedRow(Conn c) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: busy ? null : () => _use(c),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 54),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                ic(tb.World.new, size: 17, color: D.muted),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          c.name.isEmpty ? Connections.defaultName(c.url) : c.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: txt(14, weight: FontWeight.w600, height: 1.3),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          c.url,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: TextDirection.ltr,
                          style: txt(11.5, color: D.faint, height: 1.3),
                        ),
                      ]),
                ),
                if (busy && usingId == c.id)
                  const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: kPrimary))
                else
                  ic(tb.ArrowLeft.new, size: 16, color: D.faint),
              ]),
            ),
          ),
        ),
      );

  Widget _field(String label, TextEditingController c, IconCtor icon,
          {bool obscure = false, ValueChanged<String>? onSubmitted}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(label, style: txt(12.5, color: D.muted, weight: FontWeight.w600)),
        ),
        DInput(
          child: Row(children: [
            ic(icon, size: 16),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: c,
                obscureText: obscure,
                textDirection: TextDirection.ltr,
                onSubmitted: onSubmitted,
                style: txt(14.5),
                cursorColor: D.accent,
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ]),
        ),
      ]);

  Future<void> submit({String? of}) async {
    setState(() {
      busy = true;
      error = null;
    });
    final base = Connections.normalizeUrl(url.text);
    final a = HermesApi(base, user.text.trim(), pass.text)..connId = of ?? usingId;
    try {
      await a.login();
      await a.ticket(); // prove the WS leg, not just HTTP
      await a.save();
      widget.onDone(a);
    } catch (e) {
      setState(() => error = e.toString());
    }
    if (mounted) {
      setState(() {
        busy = false;
        usingId = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DAmbient(child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: Column(children: [
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  color: D.accentWash,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: D.accentDim.withValues(alpha: 0.5)),
                ),
                child: Center(child: ic(tb.Brain.new, size: 36, color: D.accent)),
              ),
              const SizedBox(height: 16),
              Text('Hermes', style: txt(24, weight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('المساعد الشخصي على أجهزتك', style: txt(13, color: D.muted)),
              const SizedBox(height: 22),
              DGlass(
                pad: const EdgeInsets.all(18),
                radius: 26,
                                tint: G.panelTint,
          panel: true,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _field('عنوان الخادم', url, tb.World.new),
                  const SizedBox(height: 14),
                  _field('اسم المستخدم', user, tb.User.new),
                  const SizedBox(height: 14),
                  _field('كلمة المرور', pass, tb.Lock.new, obscure: true, onSubmitted: (_) => submit()),
                  if (error != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: D.danger.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(D.rSm),
                        border: Border.all(color: D.danger.withValues(alpha: 0.4)),
                      ),
                      child: Row(children: [
                        ic(tb.AlertCircle.new, size: 15, color: D.danger),
                        const SizedBox(width: 8),
                        Expanded(child: Text(error!, style: txt(12.5, color: D.danger))),
                      ]),
                    ),
                  ],
                  const SizedBox(height: 20),
                  DBtn(
                    label: busy ? 'جارٍ الاتصال...' : 'دخول',
                    icon: tb.Login.new,
                    onPressed: busy ? null : submit,
                  ),
                ]),
              ),
              if (saved.isNotEmpty) ...[
                const SizedBox(height: 14),
                DGlass(
                  pad: const EdgeInsets.symmetric(vertical: 3),
                  tint: G.panelTint,
          panel: true,
                  child: Column(children: [
                    for (var i = 0; i < saved.length; i++) ...[
                      if (i > 0)
                        Container(
                            height: 1,
                            margin: const EdgeInsets.symmetric(horizontal: 12),
                            color: D.borderSoft),
                      _savedRow(saved[i]),
                    ],
                  ]),
                ),
              ],
              const SizedBox(height: 14),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                DBtn(
                  label: 'إضافة بوابة',
                  kind: DBtnKind.ghost,
                  dense: true,
                  icon: tb.Plus.new,
                  onPressed: busy ? null : _addRemote,
                ),
              ]),
            ]),
          ),
        ),
      )),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.api, required this.onLogout, this.onConnections});
  final HermesApi api;
  final VoidCallback onLogout;
  final VoidCallback? onConnections;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final backgroundConnection = BackgroundConnection();
  late final Gateway gw;
  late final HermesStore store;
  final scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    currentApi = widget.api;
    gw = Gateway(widget.api);
    store = HermesStore(gw);
    store.addListener(_toast);
    store.addListener(_pullOffer);
    WidgetsBinding.instance.addObserver(this);
    backgroundConnection.onNetworkAvailable = () => unawaited(gw.ensureHealthy());
    backgroundConnection.listen();
    gw.addListener(_backgroundStatus);
    unawaited(_startBackground());
    gw.connect();
    Notify.i.tapped.addListener(_openTapped);
    if (Notify.i.tapped.value != null) {
      _openTapped();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => scaffoldKey.currentState?.openDrawer());
    }
  }

  Future<void> _startBackground() async {
    final ok = await backgroundConnection.start();
    if (!mounted) return;
    if (!ok) {
      _snack('تعذر تشغيل الخلفية. افتح التطبيق وأعد المحاولة.');
    } else {
      _backgroundStatus();
    }
  }

  void _backgroundStatus() {
    final status = switch (gw.state) {
      LinkState.connected => 'متصل — تصلك تنبيهات عند انتهاء الرد',
      LinkState.connecting => 'جارٍ استعادة الاتصال بالخادم',
      LinkState.offline => 'الاتصال منقطع — ستتم إعادة المحاولة تلقائيًا',
    };
    unawaited(backgroundConnection.update(status));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(gw.ensureHealthy());
    }
  }

  Future<void> _backgroundSettings() async {
    final status = await backgroundConnection.status();
    if (!mounted) return;
    await showDDialog<void>(context, (c) => DDialog(
      title: 'الاتصال في الخلفية',
      body: '${status['running'] == true ? 'خدمة الاتصال تعمل.' : 'خدمة الاتصال متوقفة.'} '
          '${status['batteryExempt'] == true ? 'تحسين البطارية غير مفعّل لهذا التطبيق.' : 'للاستمرار عند إطفاء الشاشة، افتح إعدادات البطارية واختر Hermes ثم «عدم التحسين» أو «غير مقيّد». قد تحتاج الإعداد نفسه لـ Tailscale.'} '
          'الخدمة تستهلك بطارية إضافية. الإيقاف الإجباري من Android يوقفها.',
      actions: [
        DBtn(label: 'إعدادات البطارية', kind: DBtnKind.outline,
            onPressed: () => backgroundConnection.openBatterySettings()),
        DBtn(label: status['running'] == true ? 'إيقاف الخلفية' : 'تشغيل الخلفية',
            onPressed: () {
              Navigator.of(c).pop();
              if (status['running'] == true) {
                unawaited(backgroundConnection.stop());
              } else {
                unawaited(_startBackground());
              }
            }),
      ],
    ));
  }

  /// Notification tapped: wait for transport readiness before opening history.
  Future<void> _openTapped() async {
    final id = Notify.i.tapped.value;
    if (id == null || id.isEmpty) return;
    await gw.ensureHealthy();
    if (!mounted || gw.state != LinkState.connected) return;
    Notify.i.tapped.value = null;
    if (id != store.storedId) store.openSession(SessionRow(id, '', '', 0, 0));
    scaffoldKey.currentState?.closeDrawer();
  }

  void _toast() {
    final t = store.toast;
    if (t == null || !mounted) return;
    store.toast = null;
    _snack(t);
  }

  bool _pullDialogOpen = false;
  // Heights of the glass bars floating over the transcript. Notifiers, not
  // state: a growing composer must only re-pad the list, never rebuild the
  // whole screen on every animation frame.
  final _topH = ValueNotifier<double>(60), _botH = ValueNotifier<double>(0);

  /// A send was refused because another device owns the session: offer to pull it here.
  Future<void> _pullOffer() async {
    if (store.pendingPull == null || store.pulling || _pullDialogOpen || !mounted) return;
    _pullDialogOpen = true;
    try {
      final ok = await showDDialog<bool>(context, (c) => DDialog(
            title: 'الجلسة مفتوحة على جهاز آخر',
            body: store.pullError ??
                'هذه الجلسة مفتوحة الآن على جهاز آخر. اسحبها إلى الجوال لتكمل من هنا؛ '
                    'وإن كان هناك دور قيد التشغيل فسيُطلب من ذلك الجهاز إيقافه أولًا.',
            actions: [
              DBtn(label: 'اسحب إلى الجوال', onPressed: () => Navigator.of(c).pop(true)),
              DBtn(label: 'إلغاء', kind: DBtnKind.outline, onPressed: () => Navigator.of(c).pop(false)),
            ],
          ));
      if (ok == true) {
        unawaited(store.acceptPull());
      } else {
        store.dismissPull();
      }
    } finally {
      _pullDialogOpen = false;
    }
  }

  void _snack(String t) => DFeedback.show(context, t);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    Notify.i.tapped.removeListener(_openTapped);
    gw.removeListener(_backgroundStatus);
    unawaited(backgroundConnection.stop());
    backgroundConnection.dispose();
    _topH.dispose();
    _botH.dispose();
    store.dispose();
    gw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => Scaffold(
        key: scaffoldKey,
        backgroundColor: kBg,
        drawer: SessionsDrawer(store: store, onLogout: widget.onLogout, onBackground: _backgroundSettings, onConnections: widget.onConnections),
        drawerEdgeDragWidth: 60,
        drawerScrimColor: Colors.black.withValues(alpha: 0.38),
        // The transcript runs the full height; the top bar and the composer
        // float over it as glass, so messages scroll visibly beneath them.
        body: DAmbient(
          child: SafeArea(
            child: DGlassRoot(child: Stack(children: [
              Positioned.fill(
                child: ValueListenableBuilder<double>(
                  valueListenable: _topH,
                  builder: (context, top, _) => ValueListenableBuilder<double>(
                    valueListenable: _botH,
                    builder: (context, bottom, _) =>
                        ChatView(store: store, insets: EdgeInsets.only(top: top, bottom: bottom)),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: DMeasure(
                  onSize: (sz) {
                    if ((sz.height - _topH.value).abs() > 0.5) _topH.value = sz.height;
                  },
                  child: RepaintBoundary(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    TopBar(store: store, onMenu: () => scaffoldKey.currentState?.openDrawer()),
                    DReveal(show: gw.state != LinkState.connected, alignment: Alignment.topCenter, child: LinkBanner(gw: gw)),
                  ])),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: DMeasure(
                  onSize: (sz) {
                    if ((sz.height - _botH.value).abs() > 0.5) _botH.value = sz.height;
                  },
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    DReveal(
                      show: store.pending != null,
                      child: store.pending == null ? const SizedBox.shrink() : RequestCard(store: store),
                    ),
                    // Opening or closing a session materializes the composer
                    // instead of popping it in.
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      reverseDuration: const Duration(milliseconds: 140),
                      switchInCurve: D.ease,
                      switchOutCurve: D.easeIn,
                      transitionBuilder: glassSwitch,
                      child: store.sid != null
                          ? KeyedSubtree(key: const ValueKey('composer'), child: Composer(store: store, api: widget.api))
                          : const SizedBox(key: ValueKey('none'), width: double.infinity),
                    ),
                  ]),
                ),
              ),
            ])),
          ),
        ),
      ),
    );
  }
}

class LinkBanner extends StatelessWidget {
  const LinkBanner({super.key, required this.gw});
  final Gateway gw;
  @override
  Widget build(BuildContext context) {
    final connecting = gw.state == LinkState.connecting;
    return DGlass(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      pad: const EdgeInsetsDirectional.fromSTEB(12, 6, 6, 6),
      radius: D.rLg,
      tint: G.cardTint,
      body: connecting ? D.surface : const Color(0xFF3A1F1B),
      child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 32),
      child: Row(children: [
        ic(connecting ? tb.Loader2.new : tb.WifiOff.new, size: 16, color: connecting ? D.muted : D.danger),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            connecting ? 'جارٍ الاتصال بالخادم...' : 'غير متصل. ${gw.lastError ?? ''}',
            style: const TextStyle(color: kMfg, fontSize: 12),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (!connecting) DBtn(label: 'إعادة', kind: DBtnKind.ghost, dense: true, onPressed: gw.retryNow),
      ]),
      ),
    );
  }
}

TextDirection _dirOf(String s) => dDirOf(s);

class TopBar extends StatelessWidget {
  const TopBar({super.key, required this.store, required this.onMenu});
  final HermesStore store;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final title = store.sid == null ? 'Hermes' : (store.title.isEmpty ? 'جلسة جديدة' : store.title);
    return DGlass(
      margin: const EdgeInsets.fromLTRB(8, 6, 8, 2),
      pad: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      radius: 26,
            child: Row(children: [
        _BarBtn(icon: tb.Menu2.new, tooltip: 'الجلسات', onPressed: onMenu),
        const SizedBox(width: 4),
        Expanded(
          child: DTextSwap(
            title,
            textDirection: _dirOf(title),
            style: txt(15.5, weight: FontWeight.w600, height: 1.3),
          ),
        ),
        if (store.sid != null)
          _BarBtn(
            icon: tb.DoorExit.new,
            tooltip: 'إغلاق الجلسة على الجوال',
            onPressed: () async {
              final ok = await showDDialog<bool>(context, (c) => DDialog(
                  title: 'إغلاق الجلسة على الجوال',
                  kind: DNoticeKind.warning,
                  body: 'سيتوقف الجوال عن الاحتفاظ بهذه الجلسة لتتمكن من فتحها على سطح المكتب. المحادثة محفوظة ويمكن فتحها هنا مجددًا.',
                  actions: [
                    DBtn(label: 'إلغاء', kind: DBtnKind.outline, onPressed: () => Navigator.of(c).pop(false)),
                    DBtn(label: 'إغلاق', icon: tb.DoorExit.new, kind: DBtnKind.danger, haptic: Hx.heavy, onPressed: () => Navigator.of(c).pop(true)),
                  ],
                ),
              );
              if (ok == true) store.closeSession();
            },
          ),
        _BarBtn(icon: tb.Edit.new, tooltip: 'جلسة جديدة', onPressed: store.newSession),
      ]),
    );
  }
}

/// Flat 44px header button: no disc, so the title carries the bar.
class _BarBtn extends StatelessWidget {
  const _BarBtn({required this.icon, required this.tooltip, required this.onPressed});
  final IconCtor icon;
  final String tooltip;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: dGlassTap(
          onTap: onPressed,
          label: tooltip,
          width: 44,
          height: 44,
          clip: const CircleBorder(),
          child: SizedBox(width: 44, height: 44, child: Center(child: ic(icon, size: 20, color: D.fg))),
        ),
      );
}

String _when(double ts) {
  if (ts <= 0) return '';
  final d = DateTime.fromMillisecondsSinceEpoch((ts * 1000).round());
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final hm = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  if (day == today) return hm;
  if (today.difference(day).inDays == 1) return 'أمس';
  const months = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
  return '${d.day} ${months[d.month - 1]}';
}

String _sourceLabel(String s) => switch (s) {
      'desktop' => 'سطح المكتب',
      'mobile' => 'الجوال',
      'cli' || 'tui' => 'الطرفية',
      'telegram' => 'تيليجرام',
      'whatsapp' => 'واتساب',
      'cron' => 'مهمة مجدولة',
      'import-claude' => 'مستورد من Claude',
      '' => 'جلسة',
      _ => s,
    };

class SessionsDrawer extends StatefulWidget {
  const SessionsDrawer(
      {super.key, required this.store, required this.onLogout, this.onBackground, this.onConnections});
  final VoidCallback? onBackground;
  final VoidCallback? onConnections;
  final HermesStore store;
  final VoidCallback onLogout;
  @override
  State<SessionsDrawer> createState() => _SessionsDrawerState();
}

class _SessionsDrawerState extends State<SessionsDrawer> {
  String q = '';
  String? _connName;

  @override
  void initState() {
    super.initState();
    () async {
      try {
        final act = await Connections.instance.active();
        if (mounted) setState(() => _connName = act?.name);
      } catch (_) {}
    }();
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final rows = store.sessions
        .where((s) => q.isEmpty || s.title.toLowerCase().contains(q.toLowerCase()) || s.id.contains(q))
        .toList();

    Future<void> confirmLogout() async {
      final ok = await showDDialog<bool>(context, (c) => DDialog(
          title: 'تسجيل الخروج',
          kind: DNoticeKind.warning,
          body: 'ستُنهى الجلسة الحالية لهذه البوابة. البوابات المحفوظة تبقى في «البوابات والاتصال».',
          actions: [
            DBtn(label: 'إلغاء', kind: DBtnKind.outline, onPressed: () => Navigator.of(c).pop(false)),
            DBtn(label: 'خروج', icon: tb.Logout.new, kind: DBtnKind.danger, haptic: Hx.heavy, onPressed: () => Navigator.of(c).pop(true)),
          ],
        ),
      );
      if (ok == true) widget.onLogout();
    }

    void open(SessionRow r) {
      H.fire(Hx.light);
      Navigator.of(context).pop();
      store.openSession(r);
    }

    /// Plain text row: title, then source and time. Only the open session is
    /// shaded; a working session gets a small live dot at the end.
    Widget tile(SessionRow r) {
      final on = r.id == store.storedId;
      final busy = store.activeFor(r.id)?.busy == true;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Material(
          color: on ? D.surfaceTop.withValues(alpha: 0.55) : Colors.transparent,
          borderRadius: BorderRadius.circular(D.rMd),
          child: InkWell(
            borderRadius: BorderRadius.circular(D.rMd),
            onTap: () => open(r),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(8, 8, 12, 8),
                child: Row(children: [
                  AnimatedContainer(
                    duration: D.tIn,
                    curve: D.ease,
                    width: 3,
                    height: on ? 22 : 0,
                    decoration: BoxDecoration(color: D.accent, borderRadius: BorderRadius.circular(D.rPill)),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(r.title.isEmpty ? 'جلسة بلا عنوان' : r.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: _dirOf(r.title),
                          style: txt(14, weight: on ? FontWeight.w600 : FontWeight.w400, height: 1.35)),
                      const SizedBox(height: 2),
                      Text('${_sourceLabel(r.source)}  ·  بدأت ${_when(r.startedAt)}',
                          textDirection: TextDirection.rtl, style: txt(11.5, color: D.faint, height: 1.3)),
                    ]),
                  ),
                  if (busy) ...[const SizedBox(width: 10), const StatusDot(busy: true)],
                ]),
              ),
            ),
          ),
        ),
      );
    }

    Widget activeTile(ActiveSession a) {
      final on = a.id == store.sid;
      return Material(
        color: on ? D.surfaceTop.withValues(alpha: 0.55) : Colors.transparent,
        borderRadius: BorderRadius.circular(D.rMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(D.rMd),
          onTap: () => open(SessionRow(a.key.isEmpty ? a.id : a.key, a.title, '', 0, 0)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(children: [
                StatusDot(busy: a.busy),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(a.title.isEmpty ? 'جلسة بلا عنوان' : a.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: _dirOf(a.title),
                      style: txt(14, weight: on ? FontWeight.w600 : FontWeight.w400, height: 1.35)),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (a.busy ? D.ok : D.muted).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(D.rPill),
                  ),
                  child: Text(_statusLabel(a.status), style: txt(11, color: a.busy ? D.ok : D.muted, weight: FontWeight.w600, height: 1.2)),
                ),
              ]),
            ),
          ),
        ),
      );
    }

    Widget footerBtn(IconCtor icon, String label, VoidCallback onTap, {String? value}) => Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(D.rSm),
          child: InkWell(
            borderRadius: BorderRadius.circular(D.rSm),
            onTap: () {
              H.fire(Hx.light);
              onTap();
            },
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(children: [
                  ic(icon, size: 18, color: D.muted),
                  const SizedBox(width: 12),
                  Expanded(child: Text(label, style: txt(14, color: D.fg.withValues(alpha: 0.86)))),
                  if (value != null)
                    Flexible(
                      child: Text(value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.left,
                          style: txt(11.5, color: D.faint)),
                    ),
                ]),
              ),
            ),
          ),
        );

    return Drawer(
      backgroundColor: Colors.transparent,
      elevation: 0,
      width: MediaQuery.of(context).size.width * 0.88,
      shape: const RoundedRectangleBorder(),
      child: SafeArea(
        child: DGlass(
          margin: const EdgeInsetsDirectional.fromSTEB(8, 8, 0, 8),
          radius: 30,
                    tint: G.panelTint,
          panel: true,
          pad: const EdgeInsets.fromLTRB(10, 10, 10, 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 2, 2, 10),
              child: Row(children: [
                Expanded(child: Text('Hermes', style: txt(22, weight: FontWeight.w700, height: 1.2))),
                Tooltip(
                  message: 'تحديث',
                  child: DIconBtn(
                    icon: tb.Refresh.new,
                    size: 40,
                    onPressed: () {
                      store.refreshSessions();
                      store.refreshActive();
                    },
                  ),
                ),
              ]),
            ),
            Row(children: [
              Expanded(
                child: DInput(
                  pad: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  child: Row(children: [
                    ic(tb.Search.new, size: 16),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        onChanged: (v) => setState(() => q = v),
                        style: txt(14),
                        cursorColor: D.accent,
                        decoration: const InputDecoration(
                          isDense: true,
                          hintText: 'ابحث في الجلسات',
                          hintStyle: TextStyle(color: D.faint, fontSize: 14),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(width: 8),
              DIconBtn(
                icon: tb.Edit.new,
                size: 44,
                primary: true,
                tooltip: 'جلسة جديدة',
                onPressed: () {
                  Navigator.of(context).pop();
                  store.newSession();
                },
              ),
            ]),
            Expanded(
              child: store.loadingSessions && store.sessions.isEmpty
                  ? const Center(child: CircularProgressIndicator(color: kPrimary))
                  : ListView(padding: const EdgeInsets.only(top: 4), children: [
                      if (store.active.isNotEmpty) ...[
                        DSection('الجلسات النشطة', trailing: Text('${store.active.length}', style: txt(11.5, color: D.muted))),
                        ...store.active.map(activeTile),
                      ],
                      if (rows.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 48),
                          child: Center(child: Text(q.isEmpty ? 'لا توجد جلسات' : 'لا نتائج', style: txt(13.5, color: D.muted))),
                        ),
                      // The server orders by last activity; the row shows when the
                      // session began, so the list is labelled by activity, not by date.
                      if (rows.isNotEmpty) DSection('الأحدث نشاطًا'),
                      ...rows.map(tile),
                    ]),
            ),
            Container(height: 1, margin: const EdgeInsets.symmetric(vertical: 6), color: D.borderSoft),
            if (widget.onConnections != null)
              footerBtn(tb.Server2.new, 'البوابات والاتصال', widget.onConnections!, value: _connName),
            if (widget.onBackground != null) footerBtn(tb.Bolt.new, 'الاتصال في الخلفية', widget.onBackground!),
            Row(children: [
              Expanded(child: footerBtn(tb.Logout.new, 'تسجيل الخروج', confirmLogout)),
              const BioToggle(),
            ]),
          ]),
        ),
      ),
    );
  }
}

class ChatView extends StatelessWidget {
  const ChatView({super.key, required this.store, this.insets = EdgeInsets.zero});
  final HermesStore store;

  /// Room taken by the glass bars floating over the transcript.
  final EdgeInsets insets;

  static const _starters = <(IconCtor, String)>[
    (tb.ListCheck.new, 'لخّص ما أنجزته في آخر جلسة'),
    (tb.Terminal2.new, 'افحص حالة الخادم وأبلغني بأي مشكلة'),
    (tb.FileText.new, 'اقرأ الملف المرفق واستخرج أهم النقاط'),
  ];

  @override
  Widget build(BuildContext context) {
    // Loading, empty and transcript states cross-dissolve into each other.
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      reverseDuration: const Duration(milliseconds: 120),
      switchInCurve: D.ease,
      switchOutCurve: D.easeIn,
      child: KeyedSubtree(
        key: ValueKey(store.opening ? 'opening' : store.sid == null ? 'none' : (store.items.isEmpty && !store.running) ? 'empty:${store.sid}' : 'chat:${store.sid}'),
        child: _body(context),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (store.opening) return const Center(child: CircularProgressIndicator(color: kPrimary));
    if (store.sid == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ic(tb.Messages.new, size: 36),
            const SizedBox(height: 14),
            Text('اختر جلسة من القائمة أو ابدأ جلسة جديدة',
                textAlign: TextAlign.center, style: txt(14, color: D.muted)),
            const SizedBox(height: 18),
            DBtn(label: 'جلسة جديدة', icon: tb.Edit.new, onPressed: store.newSession),
          ]),
        ),
      );
    }
    if (store.items.isEmpty && !store.running) {
      return LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 24 + insets.top, 20, 12 + insets.bottom),
          child: ConstrainedBox(
            constraints: BoxConstraints(
                minHeight: (box.maxHeight - 36 - insets.vertical).clamp(0, double.infinity), minWidth: box.maxWidth - 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('بماذا نبدأ؟', style: txt(28, weight: FontWeight.w700, height: 1.25)),
                const SizedBox(height: 6),
                Text('يعمل Hermes على خادمك بأدواته وملفاته.', style: txt(14, color: D.muted)),
                const SizedBox(height: 22),
                for (final (icon, label) in _starters)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: DSuggestion(icon: icon, label: label, onTap: () => store.requestDraft(label)),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    final items = store.items.reversed.toList();
    final extra = store.running ? 1 : 0;
    return ListView.builder(
      reverse: true,
      // reverse: the first padding edge is the bottom (composer side).
      padding: EdgeInsets.fromLTRB(16, 12 + insets.top, 16, 12 + insets.bottom),
      itemCount: items.length + extra,
      itemBuilder: (context, i) {
        if (extra == 1 && i == 0) return RunningLine(store: store);
        final it = items[i - extra];
        // Steps sit tight together; conversation turns get room to breathe.
        final older = i - extra + 1 < items.length ? items[i - extra + 1] : null;
        final step = it.kind == 'tool' || it.kind == 'thinking';
        final prevStep = older != null && (older.kind == 'tool' || older.kind == 'thinking');
        final gap = older == null ? 0.0 : (step && prevStep ? 0.0 : (it.kind == 'user' ? 18.0 : 10.0));
        return EnterAnim(
          key: ObjectKey(it),
          child: RepaintBoundary(child: Padding(padding: EdgeInsets.only(top: gap), child: MessageTile(item: it))),
        );
      },
    );
  }
}

class RunningLine extends StatelessWidget {
  const RunningLine({super.key, required this.store});
  final HermesStore store;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        const StatusDot(busy: true),
        const SizedBox(width: 10),
        Expanded(
          child: Text(store.statusText.isEmpty ? 'Hermes يعمل الآن...' : store.statusText,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: txt(12.5, color: D.muted)),
        ),
      ]),
    );
  }
}

class MessageTile extends StatefulWidget {
  const MessageTile({super.key, required this.item});
  final ChatItem item;
  @override
  State<MessageTile> createState() => _MessageTileState();
}

class _MessageTileState extends State<MessageTile> {
  bool open = false;

  void _snack(String t) => DFeedback.show(context, t);

  void _copy(String t) {
    HapticFeedback.mediumImpact();
    Clipboard.setData(ClipboardData(text: t));
    _snack('تم النسخ');
  }

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    switch (it.kind) {
      case 'user':
        return Align(
          alignment: AlignmentDirectional.centerStart,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.84),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              for (final f in it.files)
                Padding(padding: const EdgeInsets.only(bottom: 6), child: MediaCard(path: f, compact: true)),
              if (it.text.isNotEmpty)
                GestureDetector(
                  onLongPress: () => _copy(it.text),
                  child: DCard(
                    color: D.bubble,
                    radius: D.rLg,
                    shadow: const [],
                    pad: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                    child: Text(it.text, textDirection: _dirOf(it.text), style: txt(15, height: 1.55)),
                  ),
                ),
            ]),
          ),
        );
      case 'assistant':
        final media = RegExp(r'MEDIA:\s*(\S[^\n]*)').allMatches(it.text).map((m) => m[1]!.trim()).toList();
        final body = it.text.replaceAll(RegExp(r'^[ \t]*MEDIA:[^\n]*\n?', multiLine: true), '').trim();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (body.isNotEmpty)
            GestureDetector(
              onLongPress: () => _copy(body),
              child: GptMarkdownTheme(
                gptThemeData: _mdTheme,
                child: GptMarkdown(
                  body,
                  textDirection: _dirOf(body),
                  style: txt(15, height: 1.7),
                  codeBuilder: (context, name, code, closed) => DCodeBlock(
                    language: name,
                    code: code,
                    onCopy: () => _copy(code),
                  ),
                ),
              ),
            ),
          for (final path in media)
            Padding(padding: const EdgeInsets.only(top: 8), child: MediaCard(path: path)),
          if (body.isNotEmpty && it.done)
            DActionRow(textDirection: _dirOf(body), actions: [
              (tb.Copy.new, 'نسخ', () => _copy(body)),
            ]),
        ]);
      case 'thinking':
        final live = !it.done;
        final label = live
            ? 'يفكر...'
            : it.seconds != null && it.seconds! > 0
                ? 'فكّر لمدة ${_arDuration(it.seconds!)}'
                : 'التفكير';
        return DStepRow(
          icon: tb.Brain.new,
          tone: live ? D.accent : D.muted,
          label: label,
          labelDirection: TextDirection.rtl,
          detail: !open && live ? _tail(it.text, 80) : '',
          trailing: live ? DElapsed(from: it.started) : null,
          open: open,
          onTap: it.text.trim().isEmpty ? null : () => setState(() => open = !open),
          body: Text(
            it.text.trim(),
            textDirection: _dirOf(it.text),
            style: txt(13, color: D.muted, height: 1.6),
          ),
        );
      case 'tool':
        return DStepRow(
          icon: _toolIcon(it.text),
          tone: it.done ? D.muted : D.accent,
          label: it.text,
          labelDirection: TextDirection.ltr,
          detail: it.detail,
          open: open,
          onTap: it.detail.isEmpty ? null : () => setState(() => open = !open),
          trailing: DSwap(
            id: it.done,
            turn: false,
            child: it.done
                ? Row(mainAxisSize: MainAxisSize.min, children: [
                    if (it.duration != null)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 6),
                        child: Text(dSeconds(it.duration!), textDirection: TextDirection.ltr, style: txt(11, color: D.muted)),
                      ),
                    ic(tb.Check.new, size: 14, color: D.ok),
                  ])
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    DElapsed(from: it.started),
                    const SizedBox(width: 6),
                    const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.6, color: D.accent)),
                  ]),
          ),
          body: Directionality(
            textDirection: TextDirection.ltr,
            child: SelectableText(it.detail,
                style: txt(11.5, color: D.muted, height: 1.5).copyWith(fontFamily: 'monospace')),
          ),
        );
      default:
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: D.danger.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(D.rMd),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(top: 2), child: ic(tb.AlertCircle.new, size: 15, color: D.danger)),
            const SizedBox(width: 9),
            Expanded(
              child: SelectableText(it.text,
                  textDirection: _dirOf(it.text), style: txt(12.5, color: D.fg, height: 1.5)),
            ),
          ]),
        );
    }
  }
}

/// "12 ثانية" / "1 د 04 ث": Arabic units, Latin digits (as elsewhere in the app).
/// Answer typography: accent links, quiet inline code chips, heading weights
/// that step down instead of shouting, hairline rules.
final _mdTheme = GptMarkdownThemeData(
  brightness: Brightness.dark,
  highlightColor: D.surfaceHi,
  linkColor: D.accent,
  linkHoverColor: D.accent,
  hrLineColor: D.borderSoft,
  hrLineThickness: 1,
  h1: txt(21, weight: FontWeight.w700, height: 1.45),
  h2: txt(18.5, weight: FontWeight.w700, height: 1.45),
  h3: txt(16.5, weight: FontWeight.w600, height: 1.5),
  h4: txt(15.5, weight: FontWeight.w600, height: 1.5),
  inlineCode: InlineCodeStyle(
    color: D.fg,
    backgroundColor: D.surfaceHi,
    borderColor: D.borderSoft,
    borderWidth: 1,
    borderRadius: Radius.circular(6),
    fontSizeFactor: 0.88,
  ),
);

String _arDuration(int s) {
  if (s < 60) return '$s ثانية';
  return '${s ~/ 60} د ${(s % 60).toString().padLeft(2, '0')} ث';
}

String _tail(String s, int n) {
  final t = s.trim().replaceAll(RegExp(r'\s+'), ' ');
  return t.length <= n ? t : '...${t.substring(t.length - n)}';
}

/// Icon per tool family so a column of steps can be scanned without reading.
IconCtor _toolIcon(String name) {
  final n = name.toLowerCase();
  if (n.contains('terminal') || n.contains('shell') || n.contains('bash') || n.contains('process')) return tb.Terminal2.new;
  if (n.contains('search') || n.contains('grep') || n.contains('find')) return tb.Search.new;
  if (n.contains('read') || n.contains('file') || n.contains('write') || n.contains('patch')) return tb.FileText.new;
  if (n.contains('web') || n.contains('browser') || n.contains('fetch') || n.contains('extract')) return tb.World.new;
  if (n.contains('delegate') || n.contains('agent')) return tb.BinaryTree.new;
  if (n.contains('image') || n.contains('vision')) return tb.Photo.new;
  if (n.contains('memory') || n.contains('skill')) return tb.Bookmark.new;
  return tb.Tool.new;
}

class RequestCard extends StatefulWidget {
  const RequestCard({super.key, required this.store});
  final HermesStore store;
  @override
  State<RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends State<RequestCard> {
  final ctl = TextEditingController();

  String _firstQuestion(Map<String, dynamic> p) {
    final qs = p['questions'] as List?;
    return (qs != null && qs.isNotEmpty) ? '${qs.first['question']}' : '';
  }

  List<String> _firstChoices(Map<String, dynamic> p) {
    final qs = p['questions'] as List?;
    if (qs == null || qs.isEmpty) return const [];
    return ((qs.first['choices'] as List?) ?? const []).map((e) => '$e').toList();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.store.pending!;
    final isApproval = p.method == 'approval';
    final direct = ((p.params['choices'] as List?) ?? const []).map((e) => '$e').toList();
    final choices = direct.isEmpty ? _firstChoices(p.params) : direct;
    return DGlass(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 6),
      pad: const EdgeInsets.all(12),
      radius: D.rLg,
      tint: G.panelTint,
          panel: true,
      body: const Color(0xFF2A1E1A), // warm accent-tinted panel: needs attention
      child: ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            ic(isApproval ? tb.ShieldCheck.new : tb.HelpCircle.new, size: 16, color: kFg),
            const SizedBox(width: 8),
            Text(isApproval ? 'مطلوب إذن بالتنفيذ' : 'سؤال من Hermes',
                style: const TextStyle(fontWeight: FontWeight.w600, color: kFg)),
          ]),
          const SizedBox(height: 8),
          if (isApproval) ...[
            if ('${p.params['description'] ?? ''}'.isNotEmpty)
              Text('${p.params['description']}', style: const TextStyle(color: kMfg, fontSize: 12)),
            const SizedBox(height: 6),
            Container(
              constraints: const BoxConstraints(maxHeight: 120),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: kBg.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(8)),
              child: SingleChildScrollView(
                child: Text('${p.params['command'] ?? ''}',
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(color: kFg, fontSize: 12, fontFamily: 'monospace')),
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                  child: DBtn(label: 'سماح', dense: true, haptic: Hx.heavy, onPressed: () => widget.store.answer({'choice': 'once'}))),
              const SizedBox(width: 8),
              if (p.params['allow_session'] != false) ...[
                Expanded(
                    child: DBtn(
                        label: 'للجلسة',
                        dense: true,
                        kind: DBtnKind.outline,
                        onPressed: () => widget.store.answer({'choice': 'session'}))),
                const SizedBox(width: 8),
              ],
              Expanded(
                  child: DBtn(
                      label: 'رفض',
                      dense: true,
                      kind: DBtnKind.outline,
                      haptic: Hx.heavy,
                      onPressed: () => widget.store.answer({'choice': 'deny'}))),
            ]),
          ] else ...[
            Text('${p.params['question'] ?? _firstQuestion(p.params)}', style: const TextStyle(color: kFg, height: 1.5)),
            const SizedBox(height: 8),
            for (final c in choices)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: DBtn(
                  label: c,
                  kind: DBtnKind.outline,
                  onPressed: () => widget.store.answer({'answer': c}),
                ),
              ),
            Row(children: [
              Expanded(
                child: DInput(
                  child: TextField(
                    controller: ctl,
                    style: txt(13.5),
                    cursorColor: D.accent,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'إجابة أخرى',
                      hintStyle: TextStyle(color: D.muted, fontSize: 13.5),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              DIconBtn(
                icon: tb.ArrowUp.new,
                primary: true,
                onPressed: () {
                  if (ctl.text.trim().isNotEmpty) widget.store.answer({'answer': ctl.text.trim()});
                },
              ),
            ]),
          ],
        ]),
      ),
      ),
    );
  }
}

class Composer extends StatefulWidget {
  const Composer({super.key, required this.store, required this.api});
  final HermesStore store;
  final HermesApi api;
  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  final ctl = TextEditingController();
  final rec = AudioRecorder();
  bool recording = false;
  bool transcribing = false;
  Duration elapsed = Duration.zero;
  Timer? ticker;

  @override
  void initState() {
    super.initState();
    ctl.addListener(() => setState(() {}));
    widget.store.addListener(_takeDraft);
  }

  /// A suggestion chip filled the composer: place it, focus nothing, send nothing.
  void _takeDraft() {
    final d = widget.store.draftRequest;
    if (d == null || !mounted) return;
    widget.store.takeDraft();
    ctl.text = d;
    ctl.selection = TextSelection.collapsed(offset: d.length);
  }

  @override
  void dispose() {
    widget.store.removeListener(_takeDraft);
    ticker?.cancel();
    rec.dispose();
    ctl.dispose();
    super.dispose();
  }

  void _snack(String t) => DFeedback.show(context, t);

  String get slashQuery {
    final t = ctl.text;
    if (!t.startsWith('/') || t.contains(' ') || t.contains('\n')) return '';
    return t;
  }

  void _say(String t) => _snack(t);

  Future<void> startRec() async {
    if (!await rec.hasPermission()) {
      if (mounted) _say('يلزم إذن الميكروفون');
      return;
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/hermes-${DateTime.now().millisecondsSinceEpoch}.m4a';
    await rec.start(const RecordConfig(encoder: AudioEncoder.aacLc, sampleRate: 16000, numChannels: 1, bitRate: 48000),
        path: path);
    HapticFeedback.mediumImpact();
    setState(() {
      recording = true;
      elapsed = Duration.zero;
    });
    ticker = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => elapsed += const Duration(seconds: 1)));
  }

  Future<void> stopRec({bool cancel = false}) async {
    ticker?.cancel();
    final path = await rec.stop();
    setState(() => recording = false);
    if (path == null) return;
    if (cancel) {
      File(path).delete().ignore();
      return;
    }
    setState(() => transcribing = true);
    try {
      final bytes = await File(path).readAsBytes();
      final text = await widget.api.transcribe(bytes, 'audio/m4a');
      if (text.isNotEmpty) {
        final cur = ctl.text.trim();
        ctl.text = cur.isEmpty ? text : '$cur $text';
        ctl.selection = TextSelection.collapsed(offset: ctl.text.length);
      } else if (mounted) {
        _say('لم يُلتقط كلام');
      }
    } catch (e) {
      if (mounted) _say('$e');
    } finally {
      File(path).delete().ignore();
      if (mounted) setState(() => transcribing = false);
    }
  }

  Future<void> send() async {
    final t = ctl.text;
    final accepted = await widget.store.send(t);
    if (mounted && accepted && ctl.text == t) ctl.clear();
  }

  Future<void> pickFiles() async {
    final List<PlatformFile> files;
    try {
      files = await FilePicker.pickFiles();
    } catch (e) {
      _say('تعذر فتح منتقي الملفات: $e');
      return;
    }
    for (final f in files) {
      final len = await f.length() ?? 0;
      if (len > 25 * 1024 * 1024) {
        _say('${f.name} أكبر من 25 ميجابايت');
        continue;
      }
      widget.store.attach(f.name, await f.readAsBytes());
    }
  }

  Future<void> steerOrQueue({required bool steer}) async {
    final t = ctl.text;
    final accepted = steer ? await widget.store.steer(t) : await widget.store.enqueue(t);
    if (mounted && accepted && ctl.text == t) ctl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final q = slashQuery.toLowerCase();
    final matches = q.isEmpty
        ? <CommandEntry>[]
        : (store.commands.where((c) => c.name.toLowerCase().startsWith(q)).toList()
          ..sort((a, b) => a.name.length.compareTo(b.name.length)));
    final shown = matches.take(40).toList();
    final effort = '${store.info['reasoning_effort'] ?? ''}';
    final canAct = ctl.text.trim().isNotEmpty || store.attachments.isNotEmpty;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      BackgroundStrip(
        items: store.background,
        onStop: store.stopBackground,
        onDismiss: store.dismissBackground,
      ),
      DReveal(
        show: store.queued.isNotEmpty,
        child: DGlass(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          pad: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          radius: D.rLg,
          tint: G.cardTint,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              ic(tb.Clock.new, size: 15),
              const SizedBox(width: 7),
              Expanded(child: Text('في الطابور (${store.queued.length})', style: txt(12.5, weight: FontWeight.w600))),
              if (!store.running)
                DIconBtn(
                  icon: tb.Refresh.new, size: 28, tooltip: 'إعادة إرسال الطابور',
                  onPressed: store.submitting ? null : store.retryQueue,
                ),
            ]),
            for (var i = 0; i < store.queued.length; i++)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Expanded(
                      child: Text(store.queued[i].text.isEmpty ? 'مرفقات' : store.queued[i].text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: _dirOf(store.queued[i].text),
                          style: txt(12.5, color: D.muted)),
                    ),
                    const SizedBox(width: 6),
                    DIconBtn(icon: tb.X.new, size: 26, onPressed: () => store.unqueue(i)),
                  ]),
                  for (final file in store.queued[i].files)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: MediaCard(path: file.path, compact: true),
                    ),
                ]),
              ),
          ]),
        ),
      ),
      DReveal(
        show: shown.isNotEmpty,
        child: DGlass(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          radius: D.rLg,
          tint: G.panelTint,
          panel: true,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.42),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4),
              shrinkWrap: true,
              itemCount: shown.length,
              itemBuilder: (context, i) {
                final c = shown[i];
                final isSkill = c.group == 'المهارات';
                final warn = c.name == '/yolo';
                return InkWell(
                  borderRadius: BorderRadius.circular(D.rMd),
                  onTap: () {
                    H.fire(Hx.select);
                    ctl.text = '${c.name} ';
                    ctl.selection = TextSelection.collapsed(offset: ctl.text.length);
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    constraints: const BoxConstraints(minHeight: 44),
                    decoration: BoxDecoration(
                      color: warn ? D.danger.withValues(alpha: 0.10) : Colors.transparent,
                      borderRadius: BorderRadius.circular(D.rMd),
                    ),
                    child: Row(children: [
                      Text(c.name,
                          textDirection: TextDirection.ltr,
                          style: txt(13.5, color: warn ? D.danger : D.fg, weight: FontWeight.w600)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          isSkill ? 'مهارة' : c.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: _dirOf(c.description),
                          style: txt(12, color: D.faint),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ic(isSkill ? tb.Sparkles.new : tb.Slash.new, size: 15, color: isSkill ? D.accent : D.muted),
                    ]),
                  ),
                );
              },
            ),
          ),
        ),
      ),
      DGlass(
        margin: const EdgeInsets.fromLTRB(10, 6, 10, 10),
        pad: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        radius: 28,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
          DReveal(
            show: store.attachments.isNotEmpty,
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 6),
              child: SizedBox(
                height: store.attachments.any((a) => a.isImage && a.bytes.isNotEmpty) ? 56 : 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: store.attachments.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) => AttachChip(a: store.attachments[i], onRemove: store.detach),
                ),
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: D.tIn,
            reverseDuration: D.tOut,
            switchInCurve: D.ease,
            switchOutCurve: D.easeIn,
            transitionBuilder: (w, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(
                position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(a),
                child: w,
              ),
            ),
            child: recording
            ? Padding(
              key: const ValueKey('rec'),
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                Container(width: 8, height: 8, decoration: const BoxDecoration(color: D.danger, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text('${elapsed.inMinutes}:${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}',
                    textDirection: TextDirection.ltr, style: txt(13, color: D.danger)),
                const SizedBox(width: 10),
                Expanded(child: Text('جارٍ التسجيل، يُفرَّغ عبر Groq عند الإيقاف', style: txt(12, color: D.muted))),
              ]),
            )
          : Padding(
              key: const ValueKey('text'),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: TextField(
              controller: ctl,
              minLines: 1,
              maxLines: 6,
              textDirection: _dirOf(ctl.text.isEmpty ? 'ا' : ctl.text),
              style: txt(15, height: 1.45),
              cursorColor: D.accent,
              decoration: InputDecoration(
                hintText: transcribing
                    ? 'جارٍ التفريغ...'
                    : store.running
                        ? 'Hermes يعمل الآن: اكتب للتوجيه أو للطابور'
                        : 'اكتب رسالة أو / للأوامر',
                hintStyle: txt(14, color: D.muted),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
            ),
          ),
          DReveal(
            show: store.running && canAct && !recording,
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 8),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  DBtn(
                    label: 'توجيه',
                    icon: tb.Directions.new,
                    dense: true,
                    haptic: Hx.heavy,
                    onPressed: store.submitting ? null : () => steerOrQueue(steer: true),
                  ),
                  DBtn(
                    label: 'إلى الطابور',
                    icon: tb.Clock.new,
                    kind: DBtnKind.outline,
                    dense: true,
                    haptic: Hx.medium,
                    onPressed: store.submitting ? null : () => steerOrQueue(steer: false),
                  ),
                ]),
              ),
            ),
          ),

          Row(children: [
            if (recording) ...[
              DBtn(
                label: 'إلغاء',
                icon: tb.X.new,
                kind: DBtnKind.ghost,
                dense: true,
                onPressed: () => stopRec(cancel: true),
              ),
              const Spacer(),
            ] else ...[
              DIconBtn(icon: tb.Paperclip.new, size: 40, tooltip: 'إرفاق ملف', onPressed: pickFiles),
              DIconBtn(
                icon: tb.Slash.new,
                size: 40,
                tooltip: 'الأوامر',
                onPressed: () {
                  ctl.text = '/';
                  ctl.selection = const TextSelection.collapsed(offset: 1);
                },
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: DModelChip(
                    model: store.currentModel,
                    effort: _effortLabel(effort),
                    onTap: () => showModelSheet(context, store),
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],
            if (transcribing)
              const Padding(
                padding: EdgeInsets.all(8),
                child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: D.muted)),
              )
            else
              DIconBtn(
                icon: recording ? tb.PlayerStop.new : tb.Microphone.new,
                active: recording,
                size: 40,
                tooltip: recording ? 'إنهاء التسجيل' : 'إملاء صوتي',
                haptic: recording ? Hx.medium : Hx.heavy,
                onPressed: recording ? () => stopRec() : startRec,
              ),
            if (!recording) ...[
              const SizedBox(width: 4),
              DIconBtn(
                icon: store.running ? tb.PlayerStop.new : tb.ArrowUp.new,
                primary: true,
                active: store.running,
                size: 40,
                tooltip: store.running ? 'إيقاف' : 'إرسال',
                haptic: store.running ? Hx.heavy : Hx.medium,
                onPressed: store.running ? store.interrupt : (canAct ? send : null),
              ),
            ],
          ]),
        ]),
      ),
    ]);
  }
}

String _effortLabel(String e) => switch (e) {
      'none' => 'None',
      'minimal' => 'Minimal',
      'low' => 'Low',
      'medium' => 'Medium',
      'high' => 'High',
      'xhigh' => 'Extra high',
      'max' => 'Max',
      '' => 'Default',
      _ => e,
    };

/// Compact Thinking level for tight segment cells (always English).
String _effortShort(String e) => switch (e) {
      'medium' => 'Med',
      'xhigh' => 'X-High',
      _ => _effortLabel(e),
    };

Future<void> showModelSheet(BuildContext context, HermesStore store) {
  store.loadModels();
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.42),
    sheetAnimationStyle: const AnimationStyle(
      duration: Duration(milliseconds: 300),
      reverseDuration: Duration(milliseconds: 180),
      curve: Cubic(0.2, 1.1, 0.3, 1), // rises with a soft liquid overshoot
      reverseCurve: D.easeIn,
    ),
    builder: (c) => ModelSheet(store: store),
  );
}

Future<T?> showDDialog<T>(BuildContext context, WidgetBuilder builder) => showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'close',
      barrierColor: Colors.black.withValues(alpha: 0.42),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (c, _, _) => builder(c),
      // The dialog materializes like iOS 26 glass: it settles in from slightly
      // oversized and dissolves on exit.
      transitionBuilder: (c, a, _, child) =>
          dMaterialize(CurvedAnimation(parent: a, curve: D.ease, reverseCurve: D.easeIn), child, scaleFrom: 1.06),
    );

class ModelSheet extends StatefulWidget {
  const ModelSheet({super.key, required this.store});
  final HermesStore store;
  @override
  State<ModelSheet> createState() => _ModelSheetState();
}

class _ModelSheetState extends State<ModelSheet> {
  String q = '';
  bool busy = false;

  Widget _switchRow(IconCtor icon, String label, bool value, ValueChanged<bool> onChanged) => Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(14, 4, 8, 4),
        child: Row(children: [
          ic(icon, size: 17, color: value ? D.accent : D.muted),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: txt(14))),
          Switch(
            value: value,
            onChanged: (v) {
              H.fire(Hx.select);
              onChanged(v);
            },
            activeThumbColor: Colors.white,
            activeTrackColor: D.accent,
            inactiveThumbColor: D.muted,
            inactiveTrackColor: D.surfaceTop,
            trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
          ),
        ]),
      );

  Widget _effortRow(String effort) {
    const options = ['low', 'medium', 'high', 'xhigh', 'max'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          ic(tb.Brain.new, size: 17, color: D.accent),
          const SizedBox(width: 12),
          Text('Thinking', textDirection: TextDirection.ltr, style: txt(14, weight: FontWeight.w500)),
          const Spacer(),
          Text(_effortLabel(effort), textDirection: TextDirection.ltr, style: txt(12, color: D.faint)),
        ]),
        const SizedBox(height: 10),
        DSegmented(
          options: options,
          // Segment cells are ~60 px on a phone: short labels so every level
          // fits on one line. The full name stays in the header row above.
          labels: [for (final e in options) _effortShort(e)],
          value: effort,
          onChanged: (e) => widget.store.setConfig('reasoning', e),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    final kb = MediaQuery.of(context).viewInsets.bottom;
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final s = widget.store;
        final terms = q.toLowerCase().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
        final list = s.models
            .where((m) => terms.every((t) => '${m.model} ${m.provider} ${m.providerName}'.toLowerCase().contains(t)))
            .toList();
        // The current provider's group comes first so the selected model is in view.
        if (q.isEmpty) {
          final mine = list.where((m) => m.provider == s.currentProvider).toList();
          list
            ..removeWhere((m) => m.provider == s.currentProvider)
            ..insertAll(0, mine);
        }
        final fast = s.info['fast'] == true;
        final yolo = s.info['yolo'] == true;
        final effort = '${s.info['reasoning_effort'] ?? ''}';
        String? lastProv;
        final rows = <Widget>[];
        for (final m in list.take(150)) {
          if (m.provider != lastProv) {
            lastProv = m.provider;
            rows.add(Padding(
              padding: const EdgeInsets.fromLTRB(12, 18, 12, 6),
              child: Text(m.providerName.toUpperCase(),
                  textDirection: TextDirection.ltr,
                  style: txt(11, color: D.faint, weight: FontWeight.w700).copyWith(letterSpacing: 0.6)),
            ));
          }
          final cur = m.model == s.currentModel && m.provider == s.currentProvider;
          rows.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Material(
              color: cur ? D.surfaceHi.withValues(alpha: 0.9) : Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(D.rLg),
                side: BorderSide(color: cur ? D.hairline : Colors.transparent),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(D.rMd),
                onTap: busy
                    ? null
                    : () async {
                        H.fire(Hx.medium);
                        setState(() => busy = true);
                        final ok = await s.setConfig('model', '${m.model} --provider ${m.provider}',
                          confirm: (message) async {
                            if (!context.mounted) return false;
                            return await showDDialog<bool>(context, (c) => DDialog(
                              title: 'تأكيد تغيير النموذج',
                              kind: DNoticeKind.warning,
                              body: 'النموذج المختار: ${m.model}\n\n'
                                  'قد يؤثر التغيير على سعة السياق أو تكلفة المحادثة. راجع تحذير الخادم:\n\n'
                                  '$message',
                              actions: [
                                DBtn(label: 'إبقاء النموذج الحالي', kind: DBtnKind.outline,
                                    onPressed: () => Navigator.of(c).pop(false)),
                                DBtn(label: 'تغيير النموذج', icon: tb.Check.new,
                                    onPressed: () => Navigator.of(c).pop(true)),
                              ],
                            )) ?? false;
                          },
                        );
                        if (!context.mounted) return;
                        setState(() => busy = false);
                        if (ok) Navigator.of(context).pop();
                      },
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 52),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Directionality(
                      textDirection: TextDirection.ltr,
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                            Text(dModelShort(m.model),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: txt(14, weight: cur ? FontWeight.w600 : FontWeight.w500, height: 1.3)),
                            if (dModelShort(m.model) != m.model)
                              Text(m.model,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: txt(11, color: D.muted, height: 1.35)),
                          ]),
                        ),
                        // Selected mark: a small glass drop (same rim, lit top
                        // edge and soft shadow as every glass control) holding
                        // a coral check, scaling in when the row becomes current.
                        AnimatedSwitcher(
                          duration: D.tIn,
                          switchInCurve: D.spring,
                          switchOutCurve: D.easeIn,
                          transitionBuilder: (w, a) => ScaleTransition(scale: a, child: w),
                          child: cur
                              ? Padding(
                                  key: const ValueKey('on'),
                                  padding: const EdgeInsets.only(left: 10),
                                  child: DGlassPill(
                                    width: 28,
                                    height: 28,
                                    radius: 14,
                                    body: D.surfaceTop,
                                    tint: 0.95,
                                    child: Center(child: ic(tb.Check.new, size: 15, color: D.accent)),
                                  ),
                                )
                              : const SizedBox(key: ValueKey('off')),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ));
        }
        return Padding(
          padding: EdgeInsets.only(bottom: kb),
          child: DGlass(
            height: h * 0.86,
            margin: const EdgeInsets.fromLTRB(6, 0, 6, 6),
            radius: 34,
                        tint: G.panelTint,
          panel: true,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(top: 10, bottom: 14),
                  decoration: BoxDecoration(color: D.surfaceTop, borderRadius: BorderRadius.circular(D.rPill)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(children: [
                  ic(tb.Cpu.new, size: 18, color: D.accent),
                  const SizedBox(width: 8),
                  Expanded(child: Text('النموذج والإعدادات', style: txt(17, weight: FontWeight.w700))),
                  AnimatedOpacity(
                    opacity: busy ? 1 : 0,
                    duration: D.tIn,
                    child: const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 1.8, color: D.accent)),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: D.bg.withValues(alpha: 0.32),
                    borderRadius: BorderRadius.circular(D.rLg),
                    border: Border.all(color: D.hairline),
                  ),
                  child: Column(children: [
                    _effortRow(effort),
                    Container(height: 1, margin: const EdgeInsetsDirectional.only(start: 43), color: D.borderSoft),
                    _switchRow(tb.Bolt.new, 'الوضع السريع', fast, (v) => s.setConfig('fast', v ? 'fast' : 'normal')),
                    Container(height: 1, margin: const EdgeInsetsDirectional.only(start: 43), color: D.borderSoft),
                    _switchRow(tb.ShieldOff.new, 'الموافقة التلقائية لهذه الجلسة', yolo,
                        (v) => s.setConfig('yolo', v ? 'on' : 'off')),
                  ]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Text('النماذج', style: txt(12, color: D.faint, weight: FontWeight.w600, height: 1.3)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: DInput(
                  child: Row(children: [
                    ic(tb.Search.new, size: 16),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        onChanged: (v) => setState(() => q = v),
                        style: txt(14),
                        cursorColor: D.accent,
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'ابحث عن نموذج أو مزوّد',
                          hintStyle: txt(14, color: D.faint),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    Text('${list.length}', style: txt(11, color: D.faint)),
                  ]),
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: AnimatedSwitcher(
                  duration: D.tIn,
                  switchInCurve: D.ease,
                  child: s.models.isEmpty
                      ? const Center(key: ValueKey('load'), child: CircularProgressIndicator(color: D.accent))
                      : list.isEmpty
                          ? Center(key: const ValueKey('none'), child: Text('لا نتائج', style: txt(13, color: D.muted)))
                          : ListView(
                              key: const ValueKey('list'),
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              children: rows,
                            ),
                ),
              ),
              const SizedBox(height: 8),
            ]),
          ),
        );
      },
    );
  }
}


String _statusLabel(String s) => switch (s) {
      'working' => 'يعمل',
      'streaming' => 'يكتب',
      'waiting' => 'ينتظر ردك',
      'starting' => 'يبدأ',
      'resuming' => 'يستأنف',
      _ => 'خامل',
    };

/// Pulsing green dot for sessions/agents that are working.
class StatusDot extends StatefulWidget {
  const StatusDot({super.key, required this.busy});
  final bool busy;
  @override
  State<StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<StatusDot> with SingleTickerProviderStateMixin {
  late final AnimationController c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.busy) {
      return Container(width: 9, height: 9, decoration: const BoxDecoration(color: kMfg, shape: BoxShape.circle));
    }
    return FadeTransition(
      opacity: Tween(begin: 0.35, end: 1.0).animate(c),
      child: Container(width: 9, height: 9, decoration: const BoxDecoration(color: kOk, shape: BoxShape.circle)),
    );
  }
}

class BioToggle extends StatefulWidget {
  const BioToggle({super.key});
  @override
  State<BioToggle> createState() => _BioToggleState();
}

class _BioToggleState extends State<BioToggle> {
  bool on = false;
  bool avail = false;

  void _snack(String t) => DFeedback.show(context, t);

  @override
  void initState() {
    super.initState();
    () async {
      final a = await canUseBiometric();
      final o = await HermesApi.biometricEnabled();
      if (mounted) {
        setState(() {
          avail = a;
          on = o;
        });
      }
    }();
  }

  @override
  Widget build(BuildContext context) {
    if (!avail) return const SizedBox.shrink();
    return DIconBtn(
      icon: tb.Fingerprint.new,
      size: 40,
      tint: on ? kOk : kMfg,
      tooltip: on ? 'القفل بالبصمة مفعّل' : 'القفل بالبصمة متوقف',
      onPressed: () async {
        if (!await biometricCheck()) return;
        await HermesApi.setBiometric(!on);
        setState(() => on = !on);
        if (context.mounted) {
          _snack(on ? 'تم تفعيل القفل بالبصمة' : 'تم إيقاف القفل بالبصمة');
        }
      },
    );
  }
}


IconCtor _fileIcon(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  if (const {'png', 'jpg', 'jpeg', 'webp', 'gif', 'heic', 'bmp'}.contains(ext)) return tb.Photo.new;
  if (const {'md', 'txt', 'pdf', 'docx', 'doc', 'csv', 'json', 'html', 'log'}.contains(ext)) return tb.FileText.new;
  return tb.File.new;
}

/// Pending upload in the composer: spinner while uploading, x to drop it.
class AttachChip extends StatelessWidget {
  const AttachChip({super.key, required this.a, required this.onRemove});
  final Attachment a;
  final void Function(Attachment) onRemove;

  @override
  Widget build(BuildContext context) {
    final thumb = a.isImage && a.bytes.isNotEmpty && a.error == null;
    if (thumb) {
      return Tooltip(
        message: a.name,
        child: Stack(clipBehavior: Clip.none, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(D.rSm),
            child: SizedBox(
              width: 56,
              height: 56,
              child: Stack(fit: StackFit.expand, children: [
                Image.memory(Uint8List.fromList(a.bytes), fit: BoxFit.cover, gaplessPlayback: true,
                    errorBuilder: (_, _, _) => Container(color: D.surfaceHi, child: Center(child: ic(tb.Photo.new, size: 18)))),
                if (a.uploading)
                  Container(
                    color: Colors.black.withValues(alpha: 0.45),
                    child: const Center(
                        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 1.8, color: D.fg))),
                  ),
              ]),
            ),
          ),
          PositionedDirectional(
            top: -6,
            end: -6,
            child: Material(
              color: D.surfaceHi,
              shape: const CircleBorder(side: BorderSide(color: D.bg, width: 2)),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () {
                  H.fire(Hx.light);
                  onRemove(a);
                },
                child: SizedBox(width: 24, height: 24, child: Center(child: ic(tb.X.new, size: 12, color: D.fg))),
              ),
            ),
          ),
        ]),
      );
    }
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 4, 4),
      decoration: BoxDecoration(
        color: D.surfaceHi,
        borderRadius: BorderRadius.circular(D.rSm),
        border: Border.all(color: a.error == null ? D.borderSoft : D.danger),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        a.uploading
            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.6, color: D.accent))
            : Tooltip(
                message: a.error == null ? a.name : 'فشل الرفع؛ أعد الإرسال للمحاولة: ${a.error}',
                child: ic(a.error == null ? _fileIcon(a.name) : tb.AlertCircle.new,
                    size: 15, color: a.error == null ? D.accent : D.danger),
              ),
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 150),
          child: Text(a.name,
              maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr, style: txt(12.5)),
        ),
        const SizedBox(width: 2),
        DIconBtn(icon: tb.X.new, size: 28, onPressed: () => onRemove(a)),
      ]),
    );
  }
}

/// A file the agent sent (`MEDIA:<path>`): tap to download and open it,
/// images preview inline once fetched.
class MediaCard extends StatefulWidget {
  const MediaCard({super.key, required this.path, this.compact = false});
  final String path;
  final bool compact;
  @override
  State<MediaCard> createState() => _MediaCardState();
}

class _MediaCardState extends State<MediaCard> {
  bool busy = false;
  List<int>? bytes;
  String? error;

  String get name => widget.path.split('/').last;
  bool get isImage => _fileIcon(name) == tb.Photo.new;

  @override
  void initState() {
    super.initState();
    if (isImage) _fetch();
  }

  Future<List<int>?> _fetch() async {
    final api = currentApi;
    if (api == null) return null;
    if (bytes != null) return bytes;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final b = await api.download(widget.path);
      if (mounted) setState(() => bytes = b);
      return b;
    } catch (e) {
      if (mounted) setState(() => error = '$e');
      return null;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _open() async {
    final b = await _fetch();
    if (b == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final f = File('${dir.path}/received/$name');
    await f.parent.create(recursive: true);
    await f.writeAsBytes(b);
    final r = await OpenFilex.open(f.path);
    if (r.type != ResultType.done && mounted) setState(() => error = 'لا يوجد تطبيق لفتح هذا الملف');
  }

  @override
  Widget build(BuildContext context) {
    return DCard(
      color: D.surfaceHi,
      radius: D.rMd,
      border: D.borderSoft,
      pad: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(D.rMd),
        onTap: busy
            ? null
            : () {
                H.fire(Hx.light);
                _open();
              },
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (isImage && bytes != null)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(D.rMd)),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: widget.compact ? 220 : 320),
                child: Image.memory(Uint8List.fromList(bytes!),
                    width: double.infinity, fit: BoxFit.cover, gaplessPlayback: true),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              ic(_fileIcon(name), size: 18, color: D.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: TextDirection.ltr,
                      style: txt(13.5, weight: FontWeight.w600)),
                  Text(error ?? (bytes == null ? 'اضغط للتنزيل والفتح' : 'اضغط للفتح'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: txt(11.5, color: error != null ? D.danger : D.muted)),
                ]),
              ),
              busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 1.8, color: D.accent))
                  : ic(bytes == null ? tb.Download.new : tb.Share.new, size: 17),
            ]),
          ),
        ]),
      ),
    );
  }
}


/// New messages rise 10px and fade in once; rebuilds don't replay it.
class EnterAnim extends StatelessWidget {
  const EnterAnim({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: D.tIn,
      curve: D.ease,
      child: child,
      builder: (context, t, c) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 10), child: c),
      ),
    );
  }
}


/// Route transition: incoming page slides 8% from the end edge and fades in on
/// the decelerate curve; the outgoing one drifts back and dims, accelerating away.
class DPageTransitions extends PageTransitionsBuilder {
  const DPageTransitions();

  @override
  Duration get transitionDuration => const Duration(milliseconds: 280);
  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 200);

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    // Incoming page: slides from the end edge with a slight liquid overshoot.
    final a = CurvedAnimation(parent: animation, curve: const Cubic(0.2, 1.08, 0.3, 1), reverseCurve: D.easeIn);
    final b = CurvedAnimation(parent: secondaryAnimation, curve: D.ease, reverseCurve: D.easeIn);
    // Outgoing page drifts back slightly; transforms only (no scale or fade
    // of a glass-heavy page, which forces its layers to re-render per frame).
    return SlideTransition(
      position: Tween(begin: Offset.zero, end: Offset(rtl ? 0.08 : -0.08, 0)).animate(b),
      child: SlideTransition(
        position: Tween(begin: Offset(rtl ? -1.0 : 1.0, 0), end: Offset.zero).animate(a),
        child: child,
      ),
    );
  }
}

/// Small header for pushed pages: back on the right (RTL), title after it.
class _PageBar extends StatelessWidget {
  const _PageBar({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) => DGlass(
        margin: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        pad: const EdgeInsets.fromLTRB(4, 4, 12, 4),
        radius: 26,
                child: Row(children: [
          DIconBtn(
            icon: tb.ArrowRight.new,
            size: 40,
            tooltip: 'رجوع',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 6),
          Expanded(child: Text(title, style: txt(17, weight: FontWeight.w700))),
        ]),
      );
}

/// Saved gateways: switch, add, edit, delete. Switching logs in to the chosen
/// gateway and hands the fresh [HermesApi] back to the caller.
class ConnectionsPage extends StatefulWidget {
  const ConnectionsPage({super.key, required this.api, required this.onSwitched, required this.onLoggedOut});

  final HermesApi api;
  final void Function(HermesApi) onSwitched;
  final VoidCallback onLoggedOut;

  @override
  State<ConnectionsPage> createState() => _ConnectionsPageState();
}

class _ConnectionsPageState extends State<ConnectionsPage> {
  List<Conn> conns = [];
  String? activeId;
  String busyId = '';
  String? error;
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final s = await Connections.instance.list();
    final id = await Connections.instance.activeId();
    if (!mounted) return;
    setState(() {
      conns = s;
      activeId = id;
      loaded = true;
    });
  }

  Future<void> _switchTo(Conn c) async {
    setState(() {
      busyId = c.id;
      error = null;
    });
    final a = HermesApi(Connections.normalizeUrl(c.url), c.user, c.pass)..connId = c.id;
    try {
      await a.login();
      await a.ticket(); // prove the WS leg before leaving the page
      await a.save();
      if (!mounted) return;
      widget.onSwitched(a);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        busyId = '';
        error = 'تعذر الاتصال بـ «${c.name.isEmpty ? Connections.defaultName(c.url) : c.name}»: $e';
      });
    }
  }

  Future<void> _addNew() async {
    final r = await Navigator.of(context).push<Object>(
        MaterialPageRoute(builder: (_) => const ConnectionEditorPage()));
    if (!mounted) return;
    if (r is HermesApi) {
      widget.onSwitched(r);
    } else if (r == 'deleted') {
      await _reload();
    }
  }

  Future<void> _edit(Conn c) async {
    final r = await Navigator.of(context)
        .push<Object>(MaterialPageRoute(builder: (_) => ConnectionEditorPage(existing: c)));
    if (!mounted) return;
    if (r is HermesApi) {
      // Saved and verified: it is now the active gateway, reconnect to it.
      widget.onSwitched(r);
    } else if (r == 'deleted') {
      if (c.id == activeId) {
        widget.onLoggedOut();
      } else {
        await _reload();
      }
    }
  }

  Widget _row(Conn c) {
    final active = c.id == activeId;
    final busy = busyId == c.id;
    final label = c.name.isEmpty ? Connections.defaultName(c.url) : c.name;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: busy ? null : () => active ? _edit(c) : _switchTo(c),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 58),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 6, 9),
            child: Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: active ? D.accentWash : D.surfaceHi,
                  borderRadius: BorderRadius.circular(D.rSm),
                  border: Border.all(color: active ? D.accentDim.withValues(alpha: 0.5) : D.borderSoft),
                ),
                child: Center(child: ic(active ? tb.PlugConnected.new : tb.World.new, size: 17, color: active ? D.accent : D.muted)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: txt(14.5, weight: FontWeight.w600, height: 1.3)),
                      const SizedBox(height: 2),
                      Text(c.url,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: TextDirection.ltr,
                          style: txt(11.5, color: D.faint, height: 1.3)),
                    ]),
              ),
              if (busy)
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: kPrimary))
              else if (active)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  child: ic(tb.CircleCheck.new, size: 19, color: D.accent),
                ),
              DIconBtn(icon: tb.Edit.new, size: 36, tooltip: 'تعديل', onPressed: busy ? null : () => _edit(c)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _addRow() => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _addNew,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: D.surfaceHi,
                    borderRadius: BorderRadius.circular(D.rSm),
                    border: Border.all(color: D.borderSoft),
                  ),
                  child: Center(child: ic(tb.Plus.new, size: 17, color: D.accent)),
                ),
                const SizedBox(width: 12),
                Expanded(
                    child: Text('إضافة بوابة', style: txt(14.5, weight: FontWeight.w600, color: D.accent))),
              ]),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: DAmbient(child: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const _PageBar(title: 'البوابات والاتصال'),
          Expanded(
            child: !loaded
                ? const Center(child: CircularProgressIndicator(color: kPrimary))
                : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 22), children: [
                    if (error != null) ...[
                      Container(
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          color: D.danger.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(D.rSm),
                          border: Border.all(color: D.danger.withValues(alpha: 0.4)),
                        ),
                        child: Row(children: [
                          ic(tb.AlertCircle.new, size: 15, color: D.danger),
                          const SizedBox(width: 8),
                          Expanded(child: Text(error!, style: txt(12.5, color: D.danger))),
                        ]),
                      ),
                      const SizedBox(height: 12),
                    ],
                    const DSection('البوابات المحفوظة'),
                    DGlass(
                      tint: G.panelTint,
          panel: true,
                      pad: const EdgeInsets.symmetric(vertical: 3),
                      child: Column(children: [
                        for (var i = 0; i < conns.length; i++) ...[
                          if (i > 0)
                            Container(
                                height: 1,
                                margin: const EdgeInsets.symmetric(horizontal: 12),
                                color: D.borderSoft),
                          _row(conns[i]),
                        ],
                        if (conns.isNotEmpty)
                          Container(
                              height: 1,
                              margin: const EdgeInsets.symmetric(horizontal: 12),
                              color: D.borderSoft),
                        _addRow(),
                      ]),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        'المحلي يعمل عبر Tailscale والريموت عبر HTTPS بدون Tailscale. التبديل يغلق الجلسة الحالية ويفتح اتصالًا جديدًا بالبوابة المختارة.',
                        style: txt(11.5, color: D.faint, height: 1.5),
                      ),
                    ),
                  ]),
          ),
        ]),
      )),
    );
  }
}

/// Add or edit one gateway. Saving verifies login + WS ticket first, then hands
/// the ready [HermesApi] back; deleting returns the string `deleted`.
class ConnectionEditorPage extends StatefulWidget {
  const ConnectionEditorPage({super.key, this.existing});

  final Conn? existing;

  @override
  State<ConnectionEditorPage> createState() => _ConnectionEditorPageState();
}

class _ConnectionEditorPageState extends State<ConnectionEditorPage> {
  late final TextEditingController name = TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController url = TextEditingController(text: widget.existing?.url ?? '');
  late final TextEditingController user = TextEditingController(text: widget.existing?.user ?? '');
  late final TextEditingController pass = TextEditingController(text: widget.existing?.pass ?? '');
  bool obscure = true;
  bool busy = false;
  bool testBusy = false;
  String? error;
  String? okMsg;

  @override
  void dispose() {
    name.dispose();
    url.dispose();
    user.dispose();
    pass.dispose();
    super.dispose();
  }

  String? _validate() {
    if (url.text.trim().isEmpty) return 'أدخل عنوان الخادم.';
    if (user.text.trim().isEmpty) return 'أدخل اسم المستخدم.';
    if (pass.text.isEmpty) return 'أدخل كلمة المرور.';
    return null;
  }

  HermesApi? _candidate() {
    final err = _validate();
    if (err != null) {
      setState(() {
        error = err;
        okMsg = null;
      });
      return null;
    }
    return HermesApi(Connections.normalizeUrl(url.text), user.text.trim(), pass.text)
      ..connId = widget.existing?.id;
  }

  Future<void> _test() async {
    final a = _candidate();
    if (a == null) return;
    setState(() {
      testBusy = true;
      error = null;
      okMsg = null;
    });
    try {
      await a.login();
      await a.ticket();
      if (mounted) setState(() => okMsg = 'الاتصال ناجح — الخادم يستجيب.');
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
    if (mounted) setState(() => testBusy = false);
  }

  Future<void> _save() async {
    final a = _candidate();
    if (a == null) return;
    setState(() {
      busy = true;
      error = null;
      okMsg = null;
    });
    try {
      await a.login();
      await a.ticket();
      await a.save();
      if (!mounted) return;
      Navigator.of(context).pop(a);
      return;
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e';
          busy = false;
        });
      }
    }
  }

  Future<void> _delete() async {
    final c = widget.existing;
    if (c == null) return;
    final label = c.name.isEmpty ? Connections.defaultName(c.url) : c.name;
    final ok = await showDDialog<bool>(context, (x) => DDialog(
          title: 'حذف البوابة',
          kind: DNoticeKind.warning,
          body: 'سيُحذف «$label» من هذا الجهاز. يمكن إضافته مرة أخرى في أي وقت.',
          actions: [
            DBtn(label: 'إلغاء', kind: DBtnKind.outline, onPressed: () => Navigator.of(x).pop(false)),
            DBtn(label: 'حذف', icon: tb.Trash.new, kind: DBtnKind.danger, haptic: Hx.heavy, onPressed: () => Navigator.of(x).pop(true)),
          ],
        ));
    if (ok != true || !mounted) return;
    await Connections.instance.remove(c.id);
    if (!mounted) return;
    Navigator.of(context).pop('deleted');
  }

  Widget _efield(String label, TextEditingController c, IconCtor icon,
      {String? hint, bool obscureField = false, Widget? suffix}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 6),
        child: Text(label, style: txt(12.5, color: D.muted, weight: FontWeight.w600)),
      ),
      DInput(
        child: Row(children: [
          ic(icon, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: c,
              obscureText: obscureField,
              textDirection: TextDirection.ltr,
              style: txt(14.5),
              cursorColor: D.accent,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: hint,
                hintStyle: txt(13.5, color: D.faint),
              ),
            ),
          ),
          ?suffix,
        ]),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return Scaffold(
      backgroundColor: kBg,
      body: DAmbient(child: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _PageBar(title: editing ? 'تعديل البوابة' : 'بوابة جديدة'),
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
              DGlass(
                pad: const EdgeInsets.all(16),
                radius: 24,
                                tint: G.panelTint,
          panel: true,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _efield('الاسم', name, tb.Tag.new, hint: 'اختياري'),
                  const SizedBox(height: 14),
                  _efield('عنوان الخادم', url, tb.World.new),
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 4, right: 4),
                    child: Text('مثال: 100.64.0.1:9131 أو https://gateway.example.com',
                        style: txt(11, color: D.faint, height: 1.4)),
                  ),
                  const SizedBox(height: 12),
                  _efield('اسم المستخدم', user, tb.User.new),
                  const SizedBox(height: 14),
                  _efield(
                    'كلمة المرور',
                    pass,
                    tb.Lock.new,
                    obscureField: obscure,
                    suffix: DIconBtn(
                      icon: (obscure ? tb.Eye.new : tb.EyeOff.new),
                      size: 32,
                      tooltip: obscure ? 'إظهار' : 'إخفاء',
                      onPressed: () => setState(() => obscure = !obscure),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: D.danger.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(D.rSm),
                        border: Border.all(color: D.danger.withValues(alpha: 0.4)),
                      ),
                      child: Row(children: [
                        ic(tb.AlertCircle.new, size: 15, color: D.danger),
                        const SizedBox(width: 8),
                        Expanded(child: Text(error!, style: txt(12.5, color: D.danger))),
                      ]),
                    ),
                  ],
                  if (okMsg != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: D.ok.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(D.rSm),
                        border: Border.all(color: D.ok.withValues(alpha: 0.4)),
                      ),
                      child: Row(children: [
                        ic(tb.CircleCheck.new, size: 15, color: D.ok),
                        const SizedBox(width: 8),
                        Expanded(child: Text(okMsg!, style: txt(12.5, color: D.ok))),
                      ]),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Row(children: [
                    Expanded(
                      child: DBtn(
                        label: testBusy ? 'جارٍ الاختبار...' : 'اختبار الاتصال',
                        kind: DBtnKind.outline,
                        icon: tb.PlugConnected.new,
                        onPressed: (busy || testBusy) ? null : _test,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DBtn(
                        label: busy ? 'جارٍ الحفظ...' : (editing ? 'حفظ واتصال' : 'إضافة واتصال'),
                        icon: tb.Check.new,
                        onPressed: (busy || testBusy) ? null : _save,
                      ),
                    ),
                  ]),
                ]),
              ),
              if (editing) ...[
                const SizedBox(height: 22),
                DBtn(
                  label: 'حذف البوابة',
                  kind: DBtnKind.danger,
                  icon: tb.Trash.new,
                  onPressed: busy ? null : _delete,
                ),
              ],
            ]),
          ),
        ]),
      )),
    );
  }
}
