import 'package:flutter/material.dart';
import '../models/channel.dart';

class ChannelTile extends StatelessWidget {
  final Channel channel;
  final bool isFavorite;
  final VoidCallback onFavoriteToggle;
  final VoidCallback onTap;

  const ChannelTile({
    super.key,
    required this.channel,
    required this.isFavorite,
    required this.onFavoriteToggle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: SizedBox(
        width: 48,
        height: 48,
        child: channel.logoUrl != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(
                  channel.logoUrl!,
                  fit: BoxFit.cover,
                  // Si el logo falla o tarda, no bloquea la lista:
                  // cae a un ícono genérico al instante.
                  errorBuilder: (_, __, ___) => const _FallbackIcon(),
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return const _FallbackIcon();
                  },
                ),
              )
            : const _FallbackIcon(),
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
