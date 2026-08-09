import 'package:flutter/material.dart';
import '../models/channel.dart';
import 'cached_artwork_image.dart';

class ChannelTile extends StatelessWidget {
  final Channel channel;
  final bool isFavorite;
  final VoidCallback onFavoriteToggle;
  final VoidCallback onTap;
  final bool allowNetworkArtwork;

  const ChannelTile({
    super.key,
    required this.channel,
    required this.isFavorite,
    required this.onFavoriteToggle,
    required this.onTap,
    this.allowNetworkArtwork = true,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: SizedBox(
        width: 48,
        height: 48,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: CachedArtworkImage(
            url: channel.logoUrl,
            fit: BoxFit.cover,
            cacheWidth: 96,
            allowNetwork: allowNetworkArtwork,
            fallback: const _FallbackIcon(),
          ),
        ),
      ),
      title: Text(channel.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: channel.group != null ? Text(channel.group!) : null,
      trailing: IconButton(
        icon: Icon(
          isFavorite ? Icons.favorite : Icons.favorite_border,
          color: isFavorite ? Colors.redAccent : null,
        ),
        onPressed: onFavoriteToggle,
      ),
      onTap: onTap,
    );
  }
}

class _FallbackIcon extends StatelessWidget {
  const _FallbackIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Icon(Icons.live_tv, color: Colors.grey),
    );
  }
}
