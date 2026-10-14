import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_mobile/l10n.dart';
import 'package:hermes_mobile/main.dart';

void main() {
  tearDown(() => L10n.locale.value = 'ar');

  test('Arabic is the default and returns the source string unchanged', () {
    expect(L10n.lang, 'ar');
    expect(L10n.isRtl, isTrue);
    expect(L10n.t('إرسال'), 'إرسال');
  });

  test('Chinese and English tables resolve the same keys', () {
    L10n.locale.value = 'zh';
    expect(L10n.isRtl, isFalse);
    expect(L10n.t('إرسال'), '发送');
    expect(L10n.t('اسم المستخدم'), '用户名');

    L10n.locale.value = 'en';
    expect(L10n.t('إرسال'), 'Send');
    expect(L10n.t('اسم المستخدم'), 'Username');
  });

  test('placeholders are substituted per locale', () {
    L10n.locale.value = 'zh';
    expect(L10n.t('النموذج المختار: {0}\n\n', ['gpt-4o']), '所选模型: gpt-4o\n\n');
    L10n.locale.value = 'en';
    expect(L10n.t('/{0}: تم', ['help']), '/help: done');
  });

  test('unknown keys fall back to the key itself', () {
    expect(L10n.t('no-such-key-xyz'), 'no-such-key-xyz');
  });

  test('language names and supported list cover the three shipped locales', () {
    expect(L10n.supported, ['ar', 'zh', 'en']);
    expect(L10n.names['zh'], '简体中文');
    expect(L10n.isSupported('de'), isFalse);
  });

  test('no locale is missing a translation for any Arabic key', () {
    final g = L10n.gaps();
    for (final lang in ['zh', 'en']) {
      expect(g[lang], isEmpty, reason: '$lang 缺译文: ${g[lang]}');
    }
  });

  testWidgets('language picker is fully localized in zh and en', (tester) async {
    for (final tc in [('zh', '选择应用语言', '取消'), ('en', 'Choose the app language', 'Cancel')]) {
      L10n.locale.value = tc.$1;
      await tester.pumpWidget(MaterialApp(home: LoginPage(onDone: (_) {})));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextButton).last);   // 登录页底部的语言入口
      await tester.pumpAndSettle();
      expect(find.text(tc.$2), findsOneWidget, reason: '${tc.$1}: 选择器说明未本地化');
      expect(find.text(tc.$3), findsOneWidget, reason: '${tc.$1}: 取消按钮未本地化');
      expect(find.text('简体中文'), findsWidgets);
      expect(find.text('العربية'), findsWidgets);
      // 关闭
      await tester.tap(find.text(tc.$3));
      await tester.pumpAndSettle();
    }
    L10n.locale.value = 'ar';
  });

  test('zh and en name the same products/protocols and numbers in every string', () {
    // 只比较"跨语言必须一致"的硬事实：产品/协议专名与数字。
    // 阿语会把部分专名音译（تيليجرام=Telegram），所以这条只比 zh/en。
    const terms = [
      'Tailscale', 'Hermes', 'HTTPS', 'HTTP', 'Telegram', 'WhatsApp', 'Android', 'Groq',
      'Claude', 'OpenAI', 'DeepSeek', 'API', 'JSON', 'SSH', 'WS', 'URL', 'ID', 'IP',
      'GPS', 'MB', 'GB', 'MCP', 'CLI', 'TUI', 'SDK',
    ];
    final zh = L10n.debugTables['zh']!, en = L10n.debugTables['en']!;
    final problems = <String>[];
    for (final k in L10n.debugKeys) {
      final a = zh[k], b = en[k];
      if (a == null || b == null) continue;
      List<String> hit(String s) => terms
          .where((x) => RegExp(r'\b' + x + r'\b', caseSensitive: false).hasMatch(s))
          .toList();
      final ta = hit(a), tb = hit(b);
      if (ta.join(',') != tb.join(',')) {
        problems.add('$k → zh=${ta.join("+")} en=${tb.join("+")}');
      }
      Set<String> nums(String s) => RegExp(r'\d+').allMatches(s).map((m) => m.group(0)!).toSet();
      final na = nums(a), nb = nums(b);
      // 只有两边都写了数字才比较（月份等用字的写法允许不同）
      if (na.isNotEmpty && nb.isNotEmpty && na.length != nb.length) {
        problems.add('$k → 数字数 zh=${na.length} en=${nb.length}');
      }
    }
    expect(problems, isEmpty, reason: '中英不一致: ${problems.take(8).toList()}');
  });
}
