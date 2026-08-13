from pathlib import Path

path = Path('lib/screens/add_source_screen.dart')
text = path.read_text()


def replace_once(old: str, new: str) -> None:
    global text
    if old not in text:
        raise SystemExit(f'Pattern not found: {old[:140]!r}')
    text = text.replace(old, new, 1)


replace_once(
    "import '../providers/iptv_provider.dart';\n\nclass AddSourceScreen",
    "import '../providers/iptv_provider.dart';\n\nconst bool _androidTvBuild = bool.fromEnvironment('TV_FULL_ANDROID_TV');\n\nclass AddSourceScreen",
)

replace_once(
    "  final _macController = TextEditingController();\n\n  bool _obscurePassword = true;",
    "  final _macController = TextEditingController();\n\n"
    "  final _nameFocus = FocusNode();\n"
    "  final _m3uUrlFocus = FocusNode();\n"
    "  final _serverFocus = FocusNode();\n"
    "  final _usernameFocus = FocusNode();\n"
    "  final _passwordFocus = FocusNode();\n"
    "  final _portalFocus = FocusNode();\n"
    "  final _macFocus = FocusNode();\n"
    "  final _connectFocus = FocusNode();\n\n"
    "  bool _obscurePassword = true;",
)

replace_once(
    "    _macController.dispose();\n    super.dispose();",
    "    _macController.dispose();\n"
    "    _nameFocus.dispose();\n"
    "    _m3uUrlFocus.dispose();\n"
    "    _serverFocus.dispose();\n"
    "    _usernameFocus.dispose();\n"
    "    _passwordFocus.dispose();\n"
    "    _portalFocus.dispose();\n"
    "    _macFocus.dispose();\n"
    "    _connectFocus.dispose();\n"
    "    super.dispose();",
)

replace_once(
    "                child: FilledButton.icon(\n                  onPressed: provider.loading ? null : _submit,",
    "                child: FilledButton.icon(\n                  focusNode: _connectFocus,\n                  autofocus: false,\n                  onPressed: provider.loading ? null : _submit,",
)

replace_once(
    "        TextField(\n          controller: _nameController,\n          decoration:",
    "        TextField(\n          controller: _nameController,\n          focusNode: _nameFocus,\n          textInputAction: _androidTvBuild ? TextInputAction.next : TextInputAction.done,\n          onSubmitted: (_) {\n            if (_androidTvBuild) _focusFirstProviderField();\n          },\n          decoration:",
)

replace_once(
    "        TextField(\n          controller: _m3uUrlController,\n          keyboardType: TextInputType.url,",
    "        TextField(\n          controller: _m3uUrlController,\n          focusNode: _m3uUrlFocus,\n          keyboardType: TextInputType.url,\n          textInputAction: TextInputAction.done,\n          onSubmitted: (_) {\n            if (_androidTvBuild) _submitFromKeyboard();\n          },",
)

replace_once(
    "        TextField(\n          controller: _serverController,\n          keyboardType: TextInputType.url,",
    "        TextField(\n          controller: _serverController,\n          focusNode: _serverFocus,\n          keyboardType: TextInputType.url,\n          textInputAction: _androidTvBuild ? TextInputAction.next : TextInputAction.done,\n          onSubmitted: (_) {\n            if (_androidTvBuild) _usernameFocus.requestFocus();\n          },",
)

replace_once(
    "              child: TextField(\n                controller: _usernameController,\n                decoration:",
    "              child: TextField(\n                controller: _usernameController,\n                focusNode: _usernameFocus,\n                textInputAction: _androidTvBuild ? TextInputAction.next : TextInputAction.done,\n                onSubmitted: (_) {\n                  if (_androidTvBuild) _passwordFocus.requestFocus();\n                },\n                decoration:",
)

replace_once(
    "              child: TextField(\n                controller: _passwordController,\n                obscureText: _obscurePassword,",
    "              child: TextField(\n                controller: _passwordController,\n                focusNode: _passwordFocus,\n                obscureText: _obscurePassword,\n                textInputAction: TextInputAction.done,\n                onSubmitted: (_) {\n                  if (_androidTvBuild) _submitFromKeyboard();\n                },",
)

replace_once(
    "        TextField(\n          controller: _portalController,\n          keyboardType: TextInputType.url,",
    "        TextField(\n          controller: _portalController,\n          focusNode: _portalFocus,\n          keyboardType: TextInputType.url,\n          textInputAction: _androidTvBuild ? TextInputAction.next : TextInputAction.done,\n          onSubmitted: (_) {\n            if (_androidTvBuild) _macFocus.requestFocus();\n          },",
)

replace_once(
    "        TextField(\n          controller: _macController,\n          textCapitalization: TextCapitalization.characters,",
    "        TextField(\n          controller: _macController,\n          focusNode: _macFocus,\n          textCapitalization: TextCapitalization.characters,\n          textInputAction: TextInputAction.done,\n          onSubmitted: (_) {\n            if (_androidTvBuild) _connectFocus.requestFocus();\n          },",
)

marker = "  Future<void> _submit() async {\n"
helpers = """  void _focusFirstProviderField() {
    switch (_type) {
      case PlaylistSourceType.m3u:
        _m3uUrlFocus.requestFocus();
      case PlaylistSourceType.xtream:
        _serverFocus.requestFocus();
      case PlaylistSourceType.stalker:
        _portalFocus.requestFocus();
    }
  }

  void _submitFromKeyboard() {
    _connectFocus.requestFocus();
    _submit();
  }

"""
if marker not in text:
    raise SystemExit('Submit marker not found')
text = text.replace(marker, helpers + marker, 1)

path.write_text(text)
print('Android TV form navigation V3 applied successfully')
