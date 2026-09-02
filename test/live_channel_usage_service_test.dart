import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:iptv_player/models/channel.dart';
import 'package:iptv_player/services/live_channel_usage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('destacados prioriza señales deportivas sin nombres hardcodeados',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LiveChannelUsageService.instance.ensureLoaded();

    const general = Channel(
      name: 'Canal General',
      url: 'https://example.test/general',
      group: 'Entretenimiento',
    );
    const sports = Channel(
      name: 'Futbol Central',
      url: 'https://example.test/sports',
      group: 'Deportes',
    );

    expect(LiveChannelUsageService.isSportsChannel(sports), isTrue);
    expect(LiveChannelUsageService.isSportsChannel(general), isFalse);

    final featured = LiveChannelUsageService.instance.featuredChannels(
      const <Channel>[general, sports],
      isFavorite: (_) => false,
      limit: 2,
    );

    expect(featured.first, sports);
  });
}
