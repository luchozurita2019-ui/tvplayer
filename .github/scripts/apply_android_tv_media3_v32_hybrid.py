from pathlib import Path

p = Path('lib/widgets/native_live_player_view.dart')
text = p.read_text()

if "package:flutter/foundation.dart" not in text:
    text = text.replace(
        "import 'package:flutter/material.dart';\n",
        "import 'package:flutter/foundation.dart';\n"
        "import 'package:flutter/gestures.dart';\n"
        "import 'package:flutter/material.dart';\n",
        1,
    )

old = r'''  @override
  Widget build(BuildContext context) {
    return AndroidView(
      viewType: 'tvfull/media3_live_surface',
      onPlatformViewCreated: (viewId) {
        final controller = NativeLivePlayerController(viewId);
        _controller = controller;
        widget.onCreated(controller);
      },
    );
  }
'''

new = r'''  @override
  Widget build(BuildContext context) {
    return PlatformViewLink(
      viewType: 'tvfull/media3_live_surface',
      surfaceFactory: (
        BuildContext context,
        PlatformViewController controller,
      ) {
        return AndroidViewSurface(
          controller: controller as AndroidViewController,
          gestureRecognizers:
              const <Factory<OneSequenceGestureRecognizer>>{},
          hitTestBehavior: PlatformViewHitTestBehavior.opaque,
        );
      },
      onCreatePlatformView: (PlatformViewCreationParams params) {
        final controller = PlatformViewsService.initExpensiveAndroidView(
          id: params.id,
          viewType: 'tvfull/media3_live_surface',
          layoutDirection: TextDirection.ltr,
          onFocus: () => params.onFocusChanged(true),
        );
        controller.addOnPlatformViewCreatedListener(
          params.onPlatformViewCreated,
        );
        controller.addOnPlatformViewCreatedListener((viewId) {
          final liveController = NativeLivePlayerController(viewId);
          _controller = liveController;
          widget.onCreated(liveController);
        });
        return controller;
      },
    );
  }
'''

if old not in text:
    if 'PlatformViewsService.initExpensiveAndroidView' in text:
        raise SystemExit(0)
    raise SystemExit('NativeLivePlayerSurface AndroidView block not found')

p.write_text(text.replace(old, new, 1))
