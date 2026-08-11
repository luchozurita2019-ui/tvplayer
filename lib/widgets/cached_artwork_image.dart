import 'dart:io';

import 'package:flutter/material.dart';

import '../services/artwork_cache_service.dart';

class CachedArtworkImage extends StatefulWidget {
  final String? url;
  final BoxFit fit;
  final Widget fallback;
  final bool allowNetwork;
  final int? cacheWidth;
  final int? cacheHeight;
  final ValueChanged<bool>? onAvailabilityChanged;

  const CachedArtworkImage({
    super.key,
    required this.url,
    required this.fit,
    required this.fallback,
    this.allowNetwork = true,
    this.cacheWidth,
    this.cacheHeight,
    this.onAvailabilityChanged,
  });

  @override
  State<CachedArtworkImage> createState() => _CachedArtworkImageState();
}

class _CachedArtworkImageState extends State<CachedArtworkImage> {
  late Future<File?> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant CachedArtworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.allowNetwork != widget.allowNetwork) {
      _reload();
    }
  }

  void _reload() {
    final future = ArtworkCacheService.instance.resolve(
      widget.url,
      allowNetwork: widget.allowNetwork,
    );
    _future = future;
    final callback = widget.onAvailabilityChanged;
    if (callback != null) {
      future.then((file) {
        if (mounted) callback(file != null);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File?>(
      future: _future,
      builder: (context, snapshot) {
        final file = snapshot.data;
        if (file == null) return widget.fallback;
        return Image.file(
          file,
          fit: widget.fit,
          cacheWidth: widget.cacheWidth,
          cacheHeight: widget.cacheHeight,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, __, ___) => widget.fallback,
        );
      },
    );
  }
}
