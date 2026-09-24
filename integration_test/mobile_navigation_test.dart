import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:myune_music/main.dart' as app;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('compact Android navigation has no clipped primary pages', (
    tester,
  ) async {
    app.main();
    await tester.pump(const Duration(seconds: 6));

    expect(find.text('听歌房'), findsOneWidget);
    expect(find.text('Myune Listening Room'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('listening-room-library')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('listening-room-random')), findsNothing);
    expect(find.text('随机播放'), findsNothing);
    expect(find.text('歌单'), findsNothing);
    expect(find.text('歌手'), findsNothing);
    expect(find.byTooltip('功能菜单'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await binding.convertFlutterSurfaceToImage();
    await tester.pump();
    await binding.takeScreenshot('mobile_library');

    await tester.tap(find.byTooltip('功能菜单'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('外观'), findsOneWidget);
    expect(find.text('在线补充歌词'), findsOneWidget);
    expect(find.text('个性化'), findsNothing);
    expect(find.text('播放页'), findsNothing);
    expect(find.text('快捷键'), findsNothing);
    expect(find.text('音频实验室'), findsNothing);
    expect(find.text('收听统计'), findsNothing);
    expect(tester.takeException(), isNull);
    await binding.takeScreenshot('mobile_settings');
    expect(find.text('平衡歌曲音量'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byTooltip('功能菜单'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('搜索').last);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('搜索歌曲或歌手'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('功能菜单'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('正在播放').last);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('暂无歌词'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('听歌房'), findsOneWidget);

    await tester.tap(find.byTooltip('功能菜单'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('音乐库').last);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('音乐库'), findsOneWidget);
    expect(find.text('全部歌曲'), findsOneWidget);
    final libraryTabs = tester.widget<TabBar>(find.byType(TabBar));
    expect((libraryTabs.tabs.first as Tab).text, '专辑');
    for (final label in ['全部歌曲', '专辑']) {
      await tester.tap(find.text(label));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    }
  });
}
