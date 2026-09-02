import 'dart:async';

import '../models/channel.dart';
import 'tv_local_store.dart';

enum ChannelHealthState { unknown, ok, slow, dead }

class _ChannelHealthEntry {
  final ChannelHealthState state;
  final DateTime expiresAt;

  const _ChannelHealthEntry(this.state, this.expiresAt);
}

/// Memoria liviana de salud LIVE.
///
/// Los canales sanos se recuerdan sólo en RAM. Los canales que fallaron de
/// forma concluyente se persisten durante un cooldown corto para que el zapping
/// no vuelva a perder tiempo con la misma URL una y otra vez.
class ChannelHealthService {
  ChannelHealthService._();

  static final ChannelHealthService instance = ChannelHealthService._();

  static const Duration deadCooldown = Duration(minutes: 10);
  static const Duration healthyMemoryTtl = Duration(hours: 24);

  final Map<String, _ChannelHealthEntry> _entries =
      <String, _ChannelHealthEntry>{};
  bool _loaded = false;
  Future<void>? _loadFuture;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final active = _loadFuture;
    if (active != null) {
      await active;
      return;
    }

    final future = _loadPersisted();
    _loadFuture = future;
    try {
      await future;
    } finally {
      if (identical(_loadFuture, future)) _loadFuture = null;
    }
  }

  Future<void> _loadPersisted() async {
    try {
      final rows = await TvLocalStore.instance.loadChannelHealthRows();
      final now = DateTime.now();
      for (final row in rows) {
        final key = row['channel_key']?.toString().trim() ?? '';
        final rawStatus = row['status']?.toString().trim() ?? '';
        final rawExpires = row['expires_at'];
        final expiresMillis = rawExpires is int
            ? rawExpires
            : int.tryParse(rawExpires?.toString() ?? '');
        if (key.isEmpty || expiresMillis == null) continue;
        final expiresAt = DateTime.fromMillisecondsSinceEpoch(expiresMillis);
        if (!expiresAt.isAfter(now)) continue;
        final state = switch (rawStatus) {
          'dead' => ChannelHealthState.dead,
          'slow' => ChannelHealthState.slow,
          'ok' => ChannelHealthState.ok,
          _ => ChannelHealthState.unknown,
        };
        if (state != ChannelHealthState.unknown) {
          _entries[key] = _ChannelHealthEntry(state, expiresAt);
        }
      }
      unawaited(TvLocalStore.instance.pruneChannelHealth());
    } catch (_) {
      // La salud es una optimización. Nunca debe impedir abrir el reproductor.
    } finally {
      _loaded = true;
    }
  }

  ChannelHealthState statusOf(Channel channel) {
    final key = channel.uniqueKey;
    final entry = _entries[key];
    if (entry == null) return ChannelHealthState.unknown;
    if (!entry.expiresAt.isAfter(DateTime.now())) {
      _entries.remove(key);
      if (entry.state == ChannelHealthState.dead) {
        unawaited(TvLocalStore.instance.deleteChannelHealth(key));
      }
      return ChannelHealthState.unknown;
    }
    return entry.state;
  }

  bool isTemporarilyDead(Channel channel) =>
      statusOf(channel) == ChannelHealthState.dead;

  void markHealthy(Channel channel, {required bool slow}) {
    final key = channel.uniqueKey;
    final previous = _entries[key];
    _entries[key] = _ChannelHealthEntry(
      slow ? ChannelHealthState.slow : ChannelHealthState.ok,
      DateTime.now().add(healthyMemoryTtl),
    );
    if (previous?.state == ChannelHealthState.dead) {
      unawaited(TvLocalStore.instance.deleteChannelHealth(key));
    }
  }

  void markDead(Channel channel, {String reason = ''}) {
    final key = channel.uniqueKey;
    final now = DateTime.now();
    final current = _entries[key];
    if (current?.state == ChannelHealthState.dead &&
        current!.expiresAt.difference(now) > const Duration(minutes: 9)) {
      return;
    }

    final expiresAt = now.add(deadCooldown);
    _entries[key] = _ChannelHealthEntry(ChannelHealthState.dead, expiresAt);
    unawaited(
      TvLocalStore.instance.upsertChannelHealth(
        channelKey: key,
        status: 'dead',
        reason: reason,
        expiresAt: expiresAt,
      ),
    );
  }
}
