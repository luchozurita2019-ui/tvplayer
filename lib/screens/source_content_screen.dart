import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/playlist.dart';
import '../providers/iptv_provider.dart';
import 'xtream_live_screen.dart';
import 'xtream_movies_screen.dart';
import 'xtream_series_screen.dart';

class SourceContentScreen extends StatelessWidget {
  final Playlist playlist;

  const SourceContentScreen({super.key, required this.playlist});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IptvProvider>();
    final active = provider.selectedPlaylist ?? playlist;

    return Scaffold(
      backgroundColor: const Color(0xFF05090F),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(42, 26, 42, 34),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'TV FULL PRO',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .8,
                      ),
                    ),
                  ),
                  if (provider.hasMultiplePlaylists)
                    OutlinedButton.icon(
                      onPressed: () => unawaited(_choosePlaylist(context)),
                      icon: const Icon(Icons.swap_horiz_rounded, size: 20),
                      label: const Text('Cambiar lista'),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                active.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(flex: 2),
              const Text(
                '¿Qué querés ver?',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 22),
              Expanded(
                flex: 9,
                child: Row(
                  children: [
                    Expanded(
                      child: _SectionButton(
                        autofocus: true,
                        eyebrow: 'EN DIRECTO',
                        title: 'TV EN VIVO',
                        icon: Icons.live_tv_rounded,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => XtreamLiveScreen(playlist: active),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: _SectionButton(
                        eyebrow: 'CATÁLOGO',
                        title: 'PELÍCULAS',
                        icon: Icons.movie_outlined,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => XtreamMoviesScreen(playlist: active),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: _SectionButton(
                        eyebrow: 'TEMPORADAS',
                        title: 'SERIES',
                        icon: Icons.video_library_outlined,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => XtreamSeriesScreen(playlist: active),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _choosePlaylist(BuildContext context) async {
    final provider = context.read<IptvProvider>();
    final currentId = provider.selectedPlaylistId;
    final chosen = await showDialog<String>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: const Color(0xFF0C141E),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 520),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Cambiar lista',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 14),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: provider.playlists.length,
                    itemBuilder: (context, index) {
                      final item = provider.playlists[index];
                      final selected = item.id == currentId;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          autofocus: index == 0,
                          selected: selected,
                          selectedTileColor:
                              const Color(0xFF1677FF).withValues(alpha: .18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          title: Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            item.sourceType.name.toUpperCase(),
                            style: const TextStyle(color: Colors.white38),
                          ),
                          trailing:
                              selected ? const Icon(Icons.check_rounded) : null,
                          onTap: () => Navigator.of(dialogContext).pop(item.id),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (chosen != null) await provider.selectPlaylist(chosen);
  }
}

class _SectionButton extends StatefulWidget {
  final String eyebrow;
  final String title;
  final IconData icon;
  final VoidCallback onTap;
  final bool autofocus;

  const _SectionButton({
    required this.eyebrow,
    required this.title,
    required this.icon,
    required this.onTap,
    this.autofocus = false,
  });

  @override
  State<_SectionButton> createState() => _SectionButtonState();
}

class _SectionButtonState extends State<_SectionButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _focused ? 1.025 : 1,
      duration: const Duration(milliseconds: 120),
      child: Material(
        color: _focused ? const Color(0xFF122A40) : const Color(0xFF0B1622),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          autofocus: widget.autofocus,
          borderRadius: BorderRadius.circular(18),
          onFocusChange: (value) => setState(() => _focused = value),
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.all(26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(widget.icon, size: 34, color: const Color(0xFF58B9FF)),
                const Spacer(),
                Text(
                  widget.eyebrow,
                  style: const TextStyle(
                    color: Color(0x73FFFFFF),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
