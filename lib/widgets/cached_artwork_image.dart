import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../services/artwork_cache_service.dart';
import '../services/device_performance_service.dart';

/// Artwork bajo demanda y consciente del viewport.
///
/// En listas/grillas no toca disco ni red hasta que la imagen entra realmente
/// en pantalla (o en el pequeño margen [prefetchExtent]). Esto evita que una TV
/// con poca RAM/ancho de banda desperdicie conexiones en logos que el usuario
/// todavía no ve.
class CachedArtworkImage extends StatefulWidget {
  final String? url;
  final BoxFit fit;
  final Widget fallback;
  final bool allowNetwork;
  final int? cacheWidth;
  final int? cacheHeight;
  final int priority;
  final ValueChanged<bool>? onAvailabilityChanged;
  final double prefetchExtent;

  const CachedArtworkImage({
    super.key,
    required this.url,
    required this.fit,
    required this.fallback,
    this.allowNetwork = true,
    this.cacheWidth,
    this.cacheHeight,
    this.priority = 0,
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
  bool _viewportCheckScheduled = false;
  int _requestGeneration = 0;
  String? _retainedUrl;
  ScrollPosition? _scrollPosition;

  @override
  void initState() {
    super.initState();
    _scheduleViewportCheck();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = Scrollable.maybeOf(context)?.position;
    if (!identical(next, _scrollPosition)) {
      _scrollPosition?.removeListener(_handleScroll);
      _scrollPosition = next;
      _scrollPosition?.addListener(_handleScroll);
    }
    _scheduleViewportCheck();
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
      _scheduleViewportCheck();
      return;
    }
    if (oldWidget.priority != widget.priority && _file == null) {
      ArtworkCacheService.instance.promote(widget.url, widget.priority);
    }
    if (oldWidget.prefetchExtent != widget.prefetchExtent && _file == null) {
      _scheduleViewportCheck();
    }
  }

  @override
  void dispose() {
    _requestGeneration++;
    _scrollPosition?.removeListener(_handleScroll);
    _releaseInterest();
    super.dispose();
  }

  void _handleScroll() {
    if (_file != null || _loading) return;
    _scheduleViewportCheck();
  }

  void _scheduleViewportCheck() {
    if (_viewportCheckScheduled) return;
    _viewportCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewportCheckScheduled = false;
      if (!mounted || _file != null || _loading) return;
      if (_isInLoadViewport()) unawaited(_ensureResolved());
    });
  }

  bool _isInLoadViewport() {
    // Fuera de una lista desplazable (por ejemplo el logo grande del canal
    // seleccionado) se carga inmediatamente y conserva la prioridad máxima.
    if (_scrollPosition == null) return true;

    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox ||
        !renderObject.attached ||
        !renderObject.hasSize) {
      return false;
    }

    final screenSize = MediaQuery.sizeOf(context);
    if (screenSize.isEmpty) return true;
    final origin = renderObject.localToGlobal(Offset.zero);
    final rect = origin & renderObject.size;
    final extent = widget.prefetchExtent.clamp(0.0, 320.0);
    final viewport = Rect.fromLTRB(
      -extent,
      -extent,
      screenSize.width + extent,
      screenSize.height + extent,
    );
    return rect.overlaps(viewport);
  }

  Future<void> _ensureResolved() async {
    if (_file != null || _loading || !_isInLoadViewport()) return;
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
      priority: widget.priority,
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
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) {
        widget.onAvailabilityChanged?.call(false);
        return widget.fallback;
      },
    );
  }
}
