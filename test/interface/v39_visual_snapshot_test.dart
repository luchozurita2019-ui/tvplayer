import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/widgets/tv_live_theater.dart';

void main() {
  testWidgets('render approved V39 live theater at 1280x720', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(
          body: TvLiveTheater(
            video: const _VideoPreview(),
            channels: const _ChannelPreviewList(),
            channelName: 'Mundo 24',
            channelGroup: 'Noticias · Ahora: Panorama Central',
            onFullscreen: () {},
            onCategories: () {},
            onHome: () {},
            onChangeList: () {},
            onRefreshLists: () {},
            onParentalControl: () {},
            onSectionRequested: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(TvLiveTheater),
      matchesGoldenFile('goldens/v39-live-theater-1280x720.png'),
    );
  });
}

class _VideoPreview extends StatelessWidget {
  const _VideoPreview();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF142D4C), Color(0xFF07111F)],
            ),
          ),
        ),
        Center(
          child: Container(
            width: 250,
            height: 128,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .035),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white10),
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.live_tv_rounded, size: 42, color: Color(0xFF42D6FF)),
                SizedBox(height: 10),
                Text(
                  'REPRODUCTOR EN VIVO',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ChannelPreviewList extends StatelessWidget {
  const _ChannelPreviewList();

  static const names = <String>[
    'Mundo 24',
    'Sport Max',
    'Cine Plus',
    'Serie Uno',
    'Kids Zone',
    'Action Live',
    'Music Beat',
  ];

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      itemCount: names.length,
      itemBuilder: (context, index) {
        final selected = index == 0;
        return Container(
          height: 51,
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFF1677FF).withValues(alpha: .22)
                : Colors.white.withValues(alpha: .025),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: selected
                  ? const Color(0xFF42D6FF).withValues(alpha: .62)
                  : Colors.white.withValues(alpha: .06),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: .05),
                ),
                child: Icon(
                  selected ? Icons.public_rounded : Icons.live_tv_rounded,
                  size: 16,
                  color: selected ? const Color(0xFF42D6FF) : Colors.white38,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  names[index],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.white60,
                    fontSize: 11.5,
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                  ),
                ),
              ),
              if (selected)
                Container(
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFF4059),
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
