import 'dart:async';

import 'package:flutter/material.dart';

import '../models/channel.dart';
import '../services/channel_logo_resolver_service.dart';
import 'cached_artwork_image.dart';

/// Imagen de canal con prioridad estricta:
/// proveedor -> respaldo reconocido -> fallback genérico.
class ChannelLogoImage extends StatefulWidget {
  final Channel channel;
  final BoxFit fit;
  final Widget fallback;
  final bool allowNetwork;
  final int? cacheWidth;
  final int? cacheHeight;
  final int priority;
  final double prefetchExtent;

  const ChannelLogoImage({
    super.key,
    required this.channel,
    required this.fit,
    required this.fallback,
    this.allowNetwork = true,
    this.cacheWidth,
    this.cacheHeight,
    this.priority = 0,
    this.prefetchExtent = 96,
  });

  @override
  State<ChannelLogoImage> createState() => _ChannelLogoImageState();
}

class _ChannelLogoImageState extends State<ChannelLogoImage> {
  bool _providerFailed = false;
  bool _resolvingFallback = false;
  String? _fallbackUrl;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    if (_providerLogo.isEmpty) _scheduleFallback();
  }

  @override
  void didUpdateWidget(covariant ChannelLogoImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channel.uniqueKey != widget.channel.uniqueKey ||
        oldWidget.channel.logoUrl != widget.channel.logoUrl ||
        oldWidget.allowNetwork != widget.allowNetwork) {
      _generation++;
      _providerFailed = false;
      _resolvingFallback = false;
      _fallbackUrl = null;
      if (_providerLogo.isEmpty) _scheduleFallback();
    }
  }

  String get _providerLogo => widget.channel.logoUrl?.trim() ?? '';

  void _scheduleFallback() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_resolveFallback());
    });
  }

  void _onProviderAvailability(bool available) {
    if (available || _providerFailed) return;
    setState(() => _providerFailed = true);
    _scheduleFallback();
  }

  Future<void> _resolveFallback() async {
    if (_resolvingFallback || _fallbackUrl != null) return;
    _resolvingFallback = true;
    final generation = ++_generation;
    final resolved = await ChannelLogoResolverService.instance.resolveFallback(
      widget.channel,
      allowNetwork: widget.allowNetwork,
    );
    if (!mounted || generation != _generation) return;
    _resolvingFallback = false;
    if (resolved == null || resolved.trim().isEmpty) return;
    setState(() => _fallbackUrl = resolved.trim());
  }

  @override
  Widget build(BuildContext context) {
    final provider = _providerLogo;
    if (provider.isNotEmpty && !_providerFailed) {
      return CachedArtworkImage(
        url: provider,
        fit: widget.fit,
        fallback: widget.fallback,
        allowNetwork: widget.allowNetwork,
        cacheWidth: widget.cacheWidth,
        cacheHeight: widget.cacheHeight,
        priority: widget.priority,
        prefetchExtent: widget.prefetchExtent,
        onAvailabilityChanged: _onProviderAvailability,
      );
    }

    final fallbackUrl = _fallbackUrl;
    if (fallbackUrl != null && fallbackUrl.isNotEmpty) {
      return CachedArtworkImage(
        url: fallbackUrl,
        fit: widget.fit,
        fallback: widget.fallback,
        allowNetwork: widget.allowNetwork,
        cacheWidth: widget.cacheWidth,
        cacheHeight: widget.cacheHeight,
        priority: widget.priority,
        prefetchExtent: widget.prefetchExtent,
      );
    }
    return widget.fallback;
  }
}
