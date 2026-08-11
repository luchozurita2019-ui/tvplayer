import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../services/artwork_cache_service.dart';

/// Imagen de arte bajo demanda.
///
/// No inicia red al construirse: primero comprueba si está dentro del viewport
/// visible (con un pequeño margen de prefetch). Al hacer scroll, recién entonces
/// solicita la carátula/logo. Si sale del viewport antes de terminar, libera su
/// interés para que el servicio pueda cancelar esa descarga.
class CachedArtworkImage extends StatefulWidget {
  final String? url;
  final BoxFit fit;
  final Widget fallback;
  final bool allowNetwork;
  final int? cacheWidth;
  final int? cacheHeight;
  final ValueChanged<bool>? onAvailabilityChanged;

  /// Margen adicional alrededor del viewport. 96 px equivale aproximadamente
  /// a anticipar una pequeña parte de la siguiente fila, no decenas de tarjetas.
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
  ScrollPosition? _scrollPosition;
  bool _loading = false;
  bool _interestHeld = false;
  bool _visibilityCheckScheduled = false;
  int _requestGeneration = 0;
  String? _retainedUrl;

  @override
  void initState() {
    super.initState();
    _scheduleVisibilityCheck();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _attachToNearestScrollPosition();
    _scheduleVisibilityCheck();
  }

  @override
  void didUpdateWidget(covariant CachedArtworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.allowNetwork != widget.allowNetwork) {
      _requestGeneration++;
      _releaseInterest();
      _file = null;
      _loading = false;
      widget.onAvailabilityChanged?.call(false);
      _scheduleVisibilityCheck();
    }
  }

  @override
  void dispose() {
    _requestGeneration++;
    _releaseInterest();
    _scrollPosition?.removeListener(_onScroll);
    _scrollPosition = null;
    super.dispose();
  }

  void _attachToNearestScrollPosition() {
    final next = Scrollable.maybeOf(context)?.position;
    if (identical(next, _scrollPosition)) return;
    _scrollPosition?.removeListener(_onScroll);
    _scrollPosition = next;
    _scrollPosition?.addListener(_onScroll);
  }

  void _onScroll() => _scheduleVisibilityCheck();

  void _scheduleVisibilityCheck() {
    if (_visibilityCheckScheduled) return;
    _visibilityCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visibilityCheckScheduled = false;
      if (!mounted) return;
      _evaluateVisibility();
    });
  }

  void _evaluateVisibility() {
    final url = widget.url?.trim();
    if (url == null || url.isEmpty) {
      _releaseInterest();
      return;
    }

    if (_isNearViewport()) {
      unawaited(_ensureResolved());
    } else {
      _releaseInterest();
    }
  }

  bool _isNearViewport() {
    final item = context.findRenderObject();
    if (item is! RenderBox || !item.hasSize) return true;

    final scrollable = Scrollable.maybeOf(context);
    if (scrollable == null) return true;
    final viewport = scrollable.context.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize) return true;

    try {
      final itemTopLeft = item.localToGlobal(Offset.zero);
      final itemBottomRight = item.localToGlobal(
        Offset(item.size.width, item.size.height),
      );
      final viewportTopLeft = viewport.localToGlobal(Offset.zero);
      final viewportBottomRight = viewport.localToGlobal(
        Offset(viewport.size.width, viewport.size.height),
      );

      final itemRect = Rect.fromPoints(itemTopLeft, itemBottomRight);
      final viewportRect = Rect.fromPoints(
        viewportTopLeft,
        viewportBottomRight,
      ).inflate(widget.prefetchExtent);
      return itemRect.overlaps(viewportRect);
    } catch (_) {
      // Si un layout exótico no permite medir el viewport, es preferible cargar
      // la imagen antes que dejar una tarjeta visible permanentemente vacía.
      return true;
    }
  }

  Future<void> _ensureResolved() async {
    if (_file != null || _loading) return;
    final rawUrl = widget.url?.trim();
    if (rawUrl == null || rawUrl.isEmpty) return;

    final service = ArtworkCacheService.instance;
    if (!_interestHeld) {
      service.retain(rawUrl);
      _interestHeld = true;
      _retainedUrl = rawUrl;
    }

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

    return Image.file(
      file,
      fit: widget.fit,
      cacheWidth: widget.cacheWidth,
      cacheHeight: widget.cacheHeight,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, __, ___) {
        widget.onAvailabilityChanged?.call(false);
        return widget.fallback;
      },
    );
  }
}
