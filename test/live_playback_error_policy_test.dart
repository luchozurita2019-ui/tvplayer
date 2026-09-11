import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/services/live_playback_error_policy.dart';

void main() {
  test('401 403 404 410 are terminal and mark channel dead', () {
    for (final status in <int>[401, 403, 404, 410]) {
      final decision = LivePlaybackErrorPolicy.decide(
        code: 'ERROR_CODE_IO_BAD_HTTP_STATUS',
        detail: 'HTTP $status',
        retryCount: 0,
        httpStatus: status,
        nativeRetryable: true,
        category: 'http_terminal',
      );
      expect(decision.shouldRetry, isFalse, reason: '$status must be terminal');
      expect(decision.markDead, isTrue, reason: '$status must cooldown fast');
    }
  });

  test('network failures use bounded 240 600 1200 ms retries', () {
    final delays = <int>[];
    for (var retryCount = 0; retryCount < 3; retryCount++) {
      final decision = LivePlaybackErrorPolicy.decide(
        code: 'ERROR_CODE_IO_NETWORK_CONNECTION_FAILED',
        detail: 'connection reset',
        retryCount: retryCount,
        nativeRetryable: true,
        category: 'network',
      );
      expect(decision.shouldRetry, isTrue);
      expect(decision.markDead, isFalse);
      delays.add(decision.retryDelay.inMilliseconds);
    }
    expect(delays, <int>[240, 600, 1200]);

    final exhausted = LivePlaybackErrorPolicy.decide(
      code: 'ERROR_CODE_IO_NETWORK_CONNECTION_FAILED',
      detail: 'connection reset',
      retryCount: 3,
      nativeRetryable: true,
      category: 'network',
    );
    expect(exhausted.shouldRetry, isFalse);
    expect(exhausted.markDead, isFalse);
  });

  test('5xx is transient and never becomes permanent cooldown by itself', () {
    final decision = LivePlaybackErrorPolicy.decide(
      code: 'ERROR_CODE_IO_BAD_HTTP_STATUS',
      detail: 'HTTP 503',
      retryCount: 3,
      httpStatus: 503,
      nativeRetryable: true,
      category: 'http_transient',
    );
    expect(decision.shouldRetry, isFalse);
    expect(decision.markDead, isFalse);
  });

  test('no progress and exhausted stall are terminal for channel health', () {
    for (final code in <String>[
      'TVFULL_NO_PROGRESS',
      'TVFULL_STALL_EXHAUSTED',
    ]) {
      final decision = LivePlaybackErrorPolicy.decide(
        code: code,
        detail: 'signal stopped',
        retryCount: 0,
        category: 'no_progress',
      );
      expect(decision.shouldRetry, isFalse);
      expect(decision.markDead, isTrue);
    }
  });

  test('decoder errors are not mistaken for network failures', () {
    final decision = LivePlaybackErrorPolicy.decide(
      code: 'ERROR_CODE_DECODING_FAILED',
      detail: 'decoder failed',
      retryCount: 0,
      nativeRetryable: false,
      category: 'decoder',
    );
    expect(decision.shouldRetry, isFalse);
    expect(decision.markDead, isFalse);
    expect(decision.friendlyMessage, 'Formato de video no compatible');
  });
}
