import 'package:flutter/material.dart';

import '../services/app_version_service.dart';

class AppVersionBadge extends StatefulWidget {
  final bool compact;

  const AppVersionBadge({super.key, this.compact = false});

  @override
  State<AppVersionBadge> createState() => _AppVersionBadgeState();
}

class _AppVersionBadgeState extends State<AppVersionBadge> {
  late final Future<AppVersionInfo> _version =
      AppVersionService.instance.current;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppVersionInfo>(
      future: _version,
      builder: (context, snapshot) {
        final info = snapshot.data;
        if (info == null || info.versionCode <= 0) {
          return const SizedBox.shrink();
        }
        return Text(
          widget.compact ? info.compactLabel : info.label,
          maxLines: 1,
          style: const TextStyle(
            color: Colors.white30,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: .2,
          ),
        );
      },
    );
  }
}
