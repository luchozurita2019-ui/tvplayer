class LivePlaybackDecision {
  final bool shouldRetry;
  final bool markDead;
  final Duration retryDelay;
  final String friendlyMessage;
  final String category;

  const LivePlaybackDecision({
    required this.shouldRetry,
    required this.markDead,
    required this.retryDelay,
    required this.friendlyMessage,
    required this.category,
  });
}

class LivePlaybackErrorPolicy {
  LivePlaybackErrorPolicy._();

  static const List<Duration> _retryBackoff = <Duration>[
    Duration(milliseconds: 240),
    Duration(milliseconds: 600),
    Duration(milliseconds: 1200),
  ];

  static LivePlaybackDecision decide({
    required String code,
    required String detail,
    required int retryCount,
    int? httpStatus,
    bool? nativeRetryable,
    String? category,
  }) {
    final normalizedCode = code.toLowerCase();
    final normalizedCategory = (category ?? '').toLowerCase();
    final combined = '$code $detail ${category ?? ''}'.toLowerCase();

    final terminalHttp = _isTerminalHttp(httpStatus, combined);
    final transientHttp = !terminalHttp &&
        (httpStatus == 408 ||
            httpStatus == 429 ||
            (httpStatus != null && httpStatus >= 500 && httpStatus <= 599));
    final exhaustedSignal = normalizedCode.contains('tvfull_no_progress') ||
        normalizedCode.contains('tvfull_stall_exhausted') ||
        normalizedCode.contains('stream_ended');
    final transientCategory = <String>{
      'dns',
      'timeout',
      'network',
      'segment',
      'microcut',
      'http_transient',
    }.contains(normalizedCategory);
    final transientText = combined.contains('tvfull_fast_io') ||
        combined.contains('network') ||
        combined.contains('timeout') ||
        combined.contains('connection reset') ||
        combined.contains('connection refused');

    final retryableSignal = !terminalHttp &&
        !exhaustedSignal &&
        (transientHttp ||
            nativeRetryable == true ||
            transientCategory ||
            transientText);
    final shouldRetry = retryableSignal && retryCount < _retryBackoff.length;
    final markDead = terminalHttp || exhaustedSignal;

    return LivePlaybackDecision(
      shouldRetry: shouldRetry,
      markDead: markDead,
      retryDelay: shouldRetry ? _retryBackoff[retryCount] : Duration.zero,
      friendlyMessage: _friendlyMessage(
        combined,
        httpStatus: httpStatus,
        category: normalizedCategory,
      ),
      category: normalizedCategory.isEmpty ? 'playback' : normalizedCategory,
    );
  }

  static bool _isTerminalHttp(int? status, String text) {
    if (status != null) {
      return status == 401 || status == 403 || status == 404 || status == 410;
    }
    return text.contains('401') ||
        text.contains('403') ||
        text.contains('404') ||
        text.contains('410');
  }

  static String _friendlyMessage(
    String value, {
    required int? httpStatus,
    required String category,
  }) {
    if (category == 'decoder' ||
        value.contains('decoder') ||
        value.contains('codec')) {
      return 'Formato de video no compatible';
    }
    if (category == 'manifest' ||
        category == 'parser' ||
        value.contains('parsing_manifest') ||
        value.contains('parsing_container') ||
        value.contains('malformed')) {
      return 'Formato de señal no compatible';
    }
    if (category == 'dns' ||
        category == 'timeout' ||
        category == 'network' ||
        value.contains('timeout') ||
        value.contains('network') ||
        value.contains('connection')) {
      return 'Problema de conexión';
    }
    if (httpStatus != null ||
        category.startsWith('http') ||
        value.contains('response_code')) {
      return 'Canal no disponible';
    }
    return 'Canal temporalmente no disponible';
  }
}
