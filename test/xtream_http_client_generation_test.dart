import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/services/xtream_http_client.dart';

void main() {
  test('new browsing operation invalidates the previous generation', () {
    final first = XtreamHttpClient.beginBrowsingOperation();
    XtreamHttpClient.ensureGeneration(first);

    final second = XtreamHttpClient.beginBrowsingOperation();
    expect(second, greaterThan(first));
    XtreamHttpClient.ensureGeneration(second);
    expect(
      () => XtreamHttpClient.ensureGeneration(first),
      throwsA(isA<XtreamRequestCancelled>()),
    );
  });

  test('transport restart keeps the same browsing generation', () {
    final generation = XtreamHttpClient.beginBrowsingOperation();
    XtreamHttpClient.restartTransport();
    expect(XtreamHttpClient.generation, generation);
    XtreamHttpClient.ensureGeneration(generation);
  });
}
