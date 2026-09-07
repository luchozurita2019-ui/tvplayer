import 'package:flutter/material.dart';

import 'tv_full_premium_ui.dart';

/// Keeps the video inside one player route while switching between the
/// browsing layout and fullscreen. The native player is never recreated.
class TvLiveTheater extends StatelessWidget {
  final Widget video;
  final Widget channels;
  final String channelName;
  final VoidCallback onFullscreen;
  final VoidCallback onCategories;
  final VoidCallback onHome;
  final VoidCallback? onAudio;

  const TvLiveTheater({
    super.key,
    required this.video,
    required this.channels,
    required this.channelName,
    required this.onFullscreen,
    required this.onCategories,
    required this.onHome,
    this.onAudio,
  });

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: const Color(0xFF050913),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 850;
              final railWidth = compact ? 68.0 : 170.0;
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                    child: Row(
                      children: [
                        const Text(
                          'TV FULL',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 24,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        const SizedBox(width: 7),
                        const Text(
                          'PRO',
                          style: TextStyle(
                            color: tvFullViolet,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Spacer(),
                        if (!compact) const TvFullClock(),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        SizedBox(
                          width: railWidth,
                          child: ListView(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 16,
                            ),
                            children: [
                              _action(
                                Icons.live_tv_rounded,
                                'TV en vivo',
                                onFullscreen,
                                compact: compact,
                                selected: true,
                              ),
                              _action(
                                Icons.grid_view_rounded,
                                'Categorías',
                                onCategories,
                                compact: compact,
                              ),
                              _action(
                                Icons.dashboard_outlined,
                                'Destacados',
                                onHome,
                                compact: compact,
                              ),
                              if (onAudio != null)
                                _action(
                                  Icons.audiotrack_outlined,
                                  'Audio',
                                  onAudio!,
                                  compact: compact,
                                ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(6, 8, 12, 20),
                            child: Column(
                              children: [
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: ColoredBox(
                                      color: Colors.black,
                                      child: video,
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(0, 10, 0, 0),
                                  child: Row(
                                    children: [
                                      const TvFullLiveBadge(compact: true),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          channelName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Pantalla completa',
                                        onPressed: onFullscreen,
                                        icon: const Icon(
                                          Icons.fullscreen_rounded,
                                          color: tvFullCyan,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(width: compact ? 200 : 255, child: channels),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );

  Widget _action(
    IconData icon,
    String text,
    VoidCallback onTap, {
    required bool compact,
    bool selected = false,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Tooltip(
          message: text,
          child: TextButton(
            onPressed: onTap,
            style: ButtonStyle(
              minimumSize: const WidgetStatePropertyAll(Size(48, 50)),
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 10),
              ),
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.focused)
                    ? tvFullBlue.withValues(alpha: .5)
                    : selected
                        ? tvFullCyan.withValues(alpha: .15)
                        : Colors.transparent,
              ),
              side: WidgetStateProperty.resolveWith(
                (states) => BorderSide(
                  color: states.contains(WidgetState.focused)
                      ? tvFullCyan
                      : Colors.transparent,
                  width: 2,
                ),
              ),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
              ),
              foregroundColor: WidgetStatePropertyAll(
                selected ? tvFullCyan : Colors.white70,
              ),
            ),
            child: Row(
              children: [
                Icon(icon, size: 22),
                if (!compact) ...[
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(text, style: const TextStyle(fontSize: 14))),
                ],
              ],
            ),
          ),
        ),
      );
}
