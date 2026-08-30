from pathlib import Path

ROOT = Path('.')


def replace(path, old, new, count=1):
    p = ROOT / path
    text = p.read_text(encoding='utf-8')
    if old not in text:
        raise SystemExit(f'Pattern not found in {path}: {old[:120]!r}')
    text = text.replace(old, new, count)
    p.write_text(text, encoding='utf-8')

# 1) LIVE error navigation: DOWN opens channel list directly, and once the
# drawer is open it gets priority over the error-card key handler.
path = 'lib/screens/android_media3_texture_player_screen.dart'
replace(
    path,
    "  final FocusNode _retryFocus = FocusNode(debugLabel: 'tvfull-pro-live-retry');\n  final FocusNode _errorChannelListFocus =\n      FocusNode(debugLabel: 'tvfull-pro-live-error-channel-list');\n",
    "  final FocusNode _retryFocus = FocusNode(debugLabel: 'tvfull-pro-live-retry');\n",
)
old_block = """    if (_friendlyError != null) {
      if (isBack) return KeyEventResult.ignored;
      if (key == LogicalKeyboardKey.arrowLeft ||
          key == LogicalKeyboardKey.arrowUp) {
        _retryFocus.requestFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight ||
          key == LogicalKeyboardKey.arrowDown) {
        _errorChannelListFocus.requestFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.select ||
          key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.numpadEnter) {
        if (_errorChannelListFocus.hasFocus) {
          _openChannelList();
        } else {
          unawaited(_prepareCurrent());
        }
        return KeyEventResult.handled;
      }
    }

    if (_channelListVisible) {
      if (isBack) {
        _closeChannelList();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
"""
new_block = """    // La lista abierta tiene prioridad total, incluso si el canal anterior
    // dejó un error visible. Así el D-pad vuelve a navegar los canales normal.
    if (_channelListVisible) {
      if (isBack) {
        _closeChannelList();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (_friendlyError != null) {
      if (isBack) return KeyEventResult.ignored;
      if (key == LogicalKeyboardKey.arrowDown) {
        _openChannelList();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.select ||
          key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.numpadEnter) {
        unawaited(_prepareCurrent());
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowLeft ||
          key == LogicalKeyboardKey.arrowRight ||
          key == LogicalKeyboardKey.arrowUp) {
        _retryFocus.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.handled;
    }
"""
replace(path, old_block, new_block)
replace(path, "    _retryFocus.dispose();\n    _errorChannelListFocus.dispose();\n", "    _retryFocus.dispose();\n")
old_actions = """              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _LiveErrorButton(
                    focusNode: _retryFocus,
                    autofocus: true,
                    filled: true,
                    label: 'Reintentar',
                    icon: Icons.refresh_rounded,
                    onTap: () => unawaited(_prepareCurrent()),
                  ),
                  const SizedBox(width: 12),
                  _LiveErrorButton(
                    focusNode: _errorChannelListFocus,
                    label: 'Lista de canales',
                    icon: Icons.list_rounded,
                    onTap: _openChannelList,
                  ),
                ],
              ),
"""
new_actions = """              _LiveErrorButton(
                focusNode: _retryFocus,
                autofocus: true,
                filled: true,
                label: 'Reintentar',
                icon: Icons.refresh_rounded,
                onTap: () => unawaited(_prepareCurrent()),
              ),
              const SizedBox(height: 14),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.keyboard_arrow_down_rounded,
                      size: 20, color: Colors.white54),
                  SizedBox(width: 5),
                  Text(
                    'Flecha abajo: lista de canales',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
"""
replace(path, old_actions, new_actions)

# 2) Update UI: poll for updates, recheck on resume, and stop sending an
# aftv.news URL into Downloader. We show/copy the short code instead.
path = 'lib/screens/source_content_screen.dart'
replace(
    path,
    "import 'package:flutter/material.dart';\n",
    "import 'package:flutter/material.dart';\nimport 'package:flutter/services.dart';\n",
)
replace(
    path,
    "class _SourceContentScreenState extends State<SourceContentScreen> {\n",
    "class _SourceContentScreenState extends State<SourceContentScreen>\n    with WidgetsBindingObserver {\n",
)
replace(
    path,
    "  final AppUpdateService _updates = AppUpdateService.instance;\n",
    "  final AppUpdateService _updates = AppUpdateService.instance;\n  Timer? _updatePollTimer;\n",
)
old_init = """  @override
  void initState() {
    super.initState();
    _parental.addListener(_refresh);
    _updates.addListener(_refresh);
    unawaited(_parental.init());
    unawaited(_updates.checkOnce());
  }

  @override
  void dispose() {
    _parental.removeListener(_refresh);
    _updates.removeListener(_refresh);
    super.dispose();
  }
"""
new_init = """  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _parental.addListener(_refresh);
    _updates.addListener(_refresh);
    unawaited(_parental.init());
    unawaited(_updates.checkOnce(force: true));
    _updatePollTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      unawaited(_updates.checkOnce(force: true));
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_updates.checkOnce(force: true));
    }
  }

  @override
  void dispose() {
    _updatePollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _parental.removeListener(_refresh);
    _updates.removeListener(_refresh);
    super.dispose();
  }
"""
replace(path, old_init, new_init)
old_open = """  Future<void> _openUpdate() async {
    final opened = await _updates.openUpdate();
    if (!mounted || opened) return;
    final code = _updates.availableUpdate?.downloaderCode ?? '';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            code.isEmpty
                ? 'No se pudo abrir el enlace de actualización.'
                : 'No se pudo abrir Downloader. Código: $code',
          ),
        ),
      );
  }
"""
new_open = """  Future<void> _openUpdate() async {
    final update = _updates.availableUpdate;
    final code = update?.downloaderCode ?? '';
    if (code.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('No hay un código de actualización válido.')),
        );
      return;
    }

    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF0C141E),
        title: const Row(
          children: [
            Icon(Icons.system_update_alt_rounded, color: Color(0xFF58B9FF)),
            SizedBox(width: 10),
            Text('Actualizar TV FULL PRO'),
          ],
        ),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Nueva versión ${update?.versionName ?? ''}',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              const Text(
                'Código para Downloader',
                style: TextStyle(fontSize: 13, color: Colors.white54),
              ),
              const SizedBox(height: 6),
              SelectableText(
                code,
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3,
                  color: Color(0xFF58B9FF),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'El código ya quedó copiado. Abrí Downloader e ingresalo. '
                'TV FULL PRO ya no envía el enlace directamente a Downloader, '
                'evitando que la aplicación se abra y se cierre sola.',
                style: TextStyle(color: Colors.white60, height: 1.35),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code));
              if (dialogContext.mounted) {
                ScaffoldMessenger.of(dialogContext)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(const SnackBar(content: Text('Código copiado.')));
              }
            },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copiar código'),
          ),
          FilledButton(
            autofocus: true,
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }
"""
replace(path, old_open, new_open)

# 3) Version bump.
replace('pubspec.yaml', 'version: 1.2.6+18', 'version: 1.2.7+19')
replace(
    'pubspec.yaml',
    '# TV FULL PRO 1.2.6+18 remote-focus-update-scroll fixpack marker.',
    '# TV FULL PRO 1.2.7+19 live-error-navigation and updater reliability marker.',
) if '# TV FULL PRO 1.2.6+18 remote-focus-update-scroll fixpack marker.' in (ROOT / 'pubspec.yaml').read_text(encoding='utf-8') else None

print('TV FULL PRO 1.2.7+19 patches applied.')
