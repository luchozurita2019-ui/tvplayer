enum BufferProfile { auto, ultraFast, balanced, stable, slowConnection, custom }

class PlaybackSettings {
  final BufferProfile profile;
  final int bufferMb;
  final double readaheadSeconds;
  final double recoveryBufferSeconds;
  final int connectTimeoutSeconds;
  final int maxRetries;
  final int stallThresholdSeconds;

  const PlaybackSettings({
    required this.profile,
    required this.bufferMb,
    required this.readaheadSeconds,
    required this.recoveryBufferSeconds,
    required this.connectTimeoutSeconds,
    required this.maxRetries,
    required this.stallThresholdSeconds,
  });

  /// Punto de partida del modo automático. El motor puede modificar
  /// temporalmente estos valores por servidor sin alterar la preferencia
  /// guardada del usuario.
  static const auto = PlaybackSettings(
    profile: BufferProfile.auto,
    bufferMb: 16,
    readaheadSeconds: 1.5,
    recoveryBufferSeconds: 1.0,
    connectTimeoutSeconds: 7,
    maxRetries: 4,
    stallThresholdSeconds: 8,
  );

  static const balanced = PlaybackSettings(
    profile: BufferProfile.balanced,
    bufferMb: 16,
    readaheadSeconds: 2.0,
    recoveryBufferSeconds: 1.0,
    connectTimeoutSeconds: 8,
    maxRetries: 4,
    stallThresholdSeconds: 8,
  );

  static const ultraFast = PlaybackSettings(
    profile: BufferProfile.ultraFast,
    bufferMb: 8,
    readaheadSeconds: 0.8,
    recoveryBufferSeconds: 0.5,
    connectTimeoutSeconds: 5,
    maxRetries: 3,
    stallThresholdSeconds: 6,
  );

  static const stable = PlaybackSettings(
    profile: BufferProfile.stable,
    bufferMb: 32,
    readaheadSeconds: 5.0,
    recoveryBufferSeconds: 2.5,
    connectTimeoutSeconds: 12,
    maxRetries: 5,
    stallThresholdSeconds: 12,
  );

  /// Perfil pensado para conexiones de poco ancho de banda o Wi-Fi irregular.
  /// No intenta "tomar" Internet del sistema: reserva más datos por adelantado,
  /// espera más a mpv/FFmpeg y evita reconstruir la sesión ante microcortes.
  static const slowConnection = PlaybackSettings(
    profile: BufferProfile.slowConnection,
    bufferMb: 64,
    readaheadSeconds: 8.0,
    recoveryBufferSeconds: 4.0,
    connectTimeoutSeconds: 15,
    maxRetries: 5,
    stallThresholdSeconds: 18,
  );

  int get bufferBytes => bufferMb * 1024 * 1024;

  PlaybackSettings copyWith({
    BufferProfile? profile,
    int? bufferMb,
    double? readaheadSeconds,
    double? recoveryBufferSeconds,
    int? connectTimeoutSeconds,
    int? maxRetries,
    int? stallThresholdSeconds,
  }) {
    return PlaybackSettings(
      profile: profile ?? this.profile,
      bufferMb: bufferMb ?? this.bufferMb,
      readaheadSeconds: readaheadSeconds ?? this.readaheadSeconds,
      recoveryBufferSeconds:
          recoveryBufferSeconds ?? this.recoveryBufferSeconds,
      connectTimeoutSeconds:
          connectTimeoutSeconds ?? this.connectTimeoutSeconds,
      maxRetries: maxRetries ?? this.maxRetries,
      stallThresholdSeconds:
          stallThresholdSeconds ?? this.stallThresholdSeconds,
    );
  }

  Map<String, dynamic> toJson() => {
        'profile': profile.name,
        'bufferMb': bufferMb,
        'readaheadSeconds': readaheadSeconds,
        'recoveryBufferSeconds': recoveryBufferSeconds,
        'connectTimeoutSeconds': connectTimeoutSeconds,
        'maxRetries': maxRetries,
        'stallThresholdSeconds': stallThresholdSeconds,
      };

  factory PlaybackSettings.fromJson(Map<String, dynamic> json) {
    final profileName = json['profile'] as String?;
    final profile = BufferProfile.values.firstWhere(
      (value) => value.name == profileName,
      orElse: () => BufferProfile.balanced,
    );

    final defaults = switch (profile) {
      BufferProfile.auto => auto,
      BufferProfile.ultraFast => ultraFast,
      BufferProfile.balanced => balanced,
      BufferProfile.stable => stable,
      BufferProfile.slowConnection => slowConnection,
      BufferProfile.custom => balanced,
    };
    return PlaybackSettings(
      profile: profile,
      bufferMb: (json['bufferMb'] as num?)?.toInt() ?? defaults.bufferMb,
      readaheadSeconds: (json['readaheadSeconds'] as num?)?.toDouble() ??
          defaults.readaheadSeconds,
      recoveryBufferSeconds:
          (json['recoveryBufferSeconds'] as num?)?.toDouble() ??
              defaults.recoveryBufferSeconds,
      connectTimeoutSeconds: (json['connectTimeoutSeconds'] as num?)?.toInt() ??
          defaults.connectTimeoutSeconds,
      maxRetries: (json['maxRetries'] as num?)?.toInt() ?? defaults.maxRetries,
      stallThresholdSeconds: (json['stallThresholdSeconds'] as num?)?.toInt() ??
          defaults.stallThresholdSeconds,
    );
  }
}
