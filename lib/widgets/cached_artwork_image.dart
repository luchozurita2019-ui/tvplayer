import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../services/artwork_cache_service.dart';
import '../services/device_performance_service.dart';

/// Artwork demand-driven by the virtualized GridView/ListView child lifecycle.
///
/// A card requests its image when Flutter actually builds that card. When the
/// builder disposes it, its download interest is released. This avoids hundreds
/// of per-card scroll listeners and RenderBox/global-coordinate calculations.
class CachedArtworkImage extends StatefulWidget {
  final String? url;
  final BoxFit fit;
  final Widget fallback;
  final bool allowNetwork;
  final int? cacheWidth;
  final int? cacheHeight;
  final ValueChanged<bool>? onAvailabilityChanged;

  /// Kept for source compatibility. Prefetch is now controlled by the parent
  /// GridView/ListView cache extent instead of every image measuring itself.
  final double prefetchExtent;

  const CachedArtworkImage({
    super.key,
    required this.url,
    required this.fit,
    required this.fallback,
    this.allowNetwork = true,
    this.cacheWidth,
    this.cacheHeight,
    this.onAvailabilityChanged,
    this.prefetchExtent = 96,
  });

  @override
  State<CachedArtworkImage> createState() => _CachedArtworkImageState();
}

class _CachedArtworkImageState extends State<CachedArtworkImage> {
  File? _file;
  bool _loading = false;
  bool _interestHeld = false;
  int _requestGeneration = 0;
  String? _retainedUrl;

  @override
  void initState() {
    super.initState();
    _scheduleResolve();
  }

  @override
  void didUpdateWidget(covariant CachedArtworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.allowNetwork != widget.allowNetwork) {
      _requestGeneration++;
      _loading = false;
      _file = null;
      _releaseInterest();
      widget.onAvailabilityChanged?.call(false);
      _scheduleResolve();
    }
  }

  @override
  void dispose() {
    _requestGeneration++;
    _releaseInterest();
    super.dispose();
  }

  void _scheduleResolve() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_ensureResolved());
    });
  }

  Future<void> _ensureResolved() async {
    if (_file != null || _loading) return;
    final rawUrl = widget.url?.trim();
    if (rawUrl == null || rawUrl.isEmpty) return;

    final service = ArtworkCacheService.instance;
    service.retain(rawUrl);
    _interestHeld = true;
    _retainedUrl = rawUrl;
    _loading = true;
    final generation = ++_requestGeneration;

    final file = await service.resolve(
      rawUrl,
      allowNetwork: widget.allowNetwork,
      demandDriven: true,
    );

    if (!mounted || generation != _requestGeneration) return;
    _loading = false;
    _releaseInterest();
    if (file == null) {
      widget.onAvailabilityChanged?.call(false);
      return;
    }
    setState(() => _file = file);
    widget.onAvailabilityChanged?.call(true);
  }

  void _releaseInterest() {
    if (!_interestHeld) return;
    ArtworkCacheService.instance.release(_retainedUrl);
    _interestHeld = false;
    _retainedUrl = null;
  }

  @override
  Widget build(BuildContext context) {
    final file = _file;
    if (file == null) return widget.fallback;
    final profile = DevicePerformanceService.instance;
    return Image.file(
      file,
      fit: widget.fit,
      cacheWidth: profile.artworkDecodeWidth(widget.cacheWidth),
      cacheHeight: profile.artworkDecodeHeight(widget.cacheHeight),
      filterQuality: profile.lowRam ? FilterQuality.low : FilterQuality.medium,
      errorBuilder: (_, __, ___) {
        widget.onAvailabilityChanged?.call(false);
        return widget.fallback;
      },
    );
  }
}
