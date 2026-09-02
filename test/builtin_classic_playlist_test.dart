import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/services/m3u_fetcher.dart';
import 'package:iptv_player/services/m3u_parser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Lista clásica se lee desde el asset y contiene canales válidos',
      () async {
    const source = 'asset://assets/playlists/lista_clasica.m3u';
    final parser = M3uLineParser();
    var channels = 0;
    await for (final line in M3uFetcher.fetchLines(source)) {
      if (parser.addLine(line) != null) channels++;
    }
    expect(channels, greaterThan(100));
  });
}
