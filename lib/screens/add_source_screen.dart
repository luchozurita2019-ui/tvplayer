import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/playlist_source_type.dart';
import '../providers/iptv_provider.dart';

const bool _androidTvBuild = bool.fromEnvironment('TV_FULL_ANDROID_TV');

class AddSourceScreen extends StatefulWidget {
  const AddSourceScreen({super.key});

  @override
  State<AddSourceScreen> createState() => _AddSourceScreenState();
}

class _AddSourceScreenState extends State<AddSourceScreen> {
  PlaylistSourceType _type = PlaylistSourceType.m3u;

  final _nameController = TextEditingController();
  final _m3uUrlController = TextEditingController();
  final _serverController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _portalController = TextEditingController();
  final _macController = TextEditingController();

  final _nameFocus = FocusNode();
  final _m3uUrlFocus = FocusNode();
  final _serverFocus = FocusNode();
  final _usernameFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _portalFocus = FocusNode();
  final _macFocus = FocusNode();
  final _connectFocus = FocusNode();

  bool _obscurePassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _m3uUrlController.dispose();
    _serverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _portalController.dispose();
    _macController.dispose();
    _nameFocus.dispose();
    _m3uUrlFocus.dispose();
    _serverFocus.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    _portalFocus.dispose();
    _macFocus.dispose();
    _connectFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IptvProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'TV FULL · Agregar servicio',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 50),
            children: [
              Text(
                'Conectá tu proveedor',
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text(
                'Pegá el enlace que te dio tu proveedor. En M3U/M3U8, TV FULL detecta automáticamente si el enlace pertenece a Xtream. También podés elegir el tipo manualmente.',
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(color: Colors.white70),
              ),
              const SizedBox(height: 24),
              _SourceSelector(
                selected: _type,
                onChanged: (value) => setState(() => _type = value),
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: KeyedSubtree(
                      key: ValueKey(_type),
                      child: _formForType(),
                    ),
                  ),
                ),
              ),
              if (provider.error != null) ...[
                const SizedBox(height: 14),
                _ErrorBanner(message: provider.error!),
              ],
              const SizedBox(height: 22),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  focusNode: _connectFocus,
                  autofocus: false,
                  onPressed: provider.loading ? null : _submit,
                  icon: provider.loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login_rounded),
                  label: Text(provider.loading ? 'Conectando…' : 'Conectar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _formForType() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TitleRow(type: _type),
        const SizedBox(height: 22),
        TextField(
          controller: _nameController,
          focusNode: _nameFocus,
          textInputAction:
              _androidTvBuild ? TextInputAction.next : TextInputAction.done,
          onSubmitted: (_) {
            if (_androidTvBuild) _focusFirstProviderField();
          },
          decoration: const InputDecoration(
            labelText: 'Nombre del servicio',
            hintText: 'Ej: Mi proveedor',
            prefixIcon: Icon(Icons.label_outline),
          ),
        ),
        const SizedBox(height: 14),
        switch (_type) {
          PlaylistSourceType.m3u => _m3uFields(),
          PlaylistSourceType.xtream => _xtreamFields(),
          PlaylistSourceType.stalker => _stalkerFields(),
        },
      ],
    );
  }

  Widget _m3uFields() {
    return Column(
      children: [
        TextField(
          controller: _m3uUrlController,
          focusNode: _m3uUrlFocus,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) {
            if (_androidTvBuild) _submitFromKeyboard();
          },
          decoration: const InputDecoration(
            labelText: 'URL del proveedor',
            hintText: 'https://servidor/get.php?username=... o lista.m3u',
            prefixIcon: Icon(Icons.link_rounded),
          ),
        ),
        const SizedBox(height: 14),
        const _InfoBox(
          text:
              'Detección automática: si el enlace get.php contiene usuario y contraseña y player_api.php valida, TV FULL lo guarda como Xtream nativo. Si no, lo carga como M3U/M3U8 normal.',
        ),
      ],
    );
  }

  Widget _xtreamFields() {
    return Column(
      children: [
        TextField(
          controller: _serverController,
          focusNode: _serverFocus,
          keyboardType: TextInputType.url,
          textInputAction:
              _androidTvBuild ? TextInputAction.next : TextInputAction.done,
          onSubmitted: (_) {
            if (_androidTvBuild) _usernameFocus.requestFocus();
          },
          decoration: const InputDecoration(
            labelText: 'Servidor / Host',
            hintText: 'http://servidor:puerto',
            prefixIcon: Icon(Icons.dns_outlined),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _usernameController,
                focusNode: _usernameFocus,
                textInputAction: _androidTvBuild
                    ? TextInputAction.next
                    : TextInputAction.done,
                onSubmitted: (_) {
                  if (_androidTvBuild) _passwordFocus.requestFocus();
                },
                decoration: const InputDecoration(
                  labelText: 'Usuario',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: TextField(
                controller: _passwordController,
                focusNode: _passwordFocus,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  if (_androidTvBuild) _submitFromKeyboard();
                },
                decoration: InputDecoration(
                  labelText: 'Contraseña',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    tooltip: _obscurePassword ? 'Mostrar' : 'Ocultar',
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        const _InfoBox(
          text:
              'TV FULL valida primero las credenciales con player_api.php y después carga el catálogo del proveedor.',
        ),
      ],
    );
  }

  Widget _stalkerFields() {
    return Column(
      children: [
        TextField(
          controller: _portalController,
          focusNode: _portalFocus,
          keyboardType: TextInputType.url,
          textInputAction:
              _androidTvBuild ? TextInputAction.next : TextInputAction.done,
          onSubmitted: (_) {
            if (_androidTvBuild) _macFocus.requestFocus();
          },
          decoration: const InputDecoration(
            labelText: 'URL del portal',
            hintText: 'http://portal.example.com/c/',
            prefixIcon: Icon(Icons.public_rounded),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _macController,
          focusNode: _macFocus,
          textCapitalization: TextCapitalization.characters,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) {
            if (_androidTvBuild) _connectFocus.requestFocus();
          },
          decoration: const InputDecoration(
            labelText: 'MAC Address',
            hintText: '00:1A:79:XX:XX:XX',
            prefixIcon: Icon(Icons.router_outlined),
          ),
        ),
        const SizedBox(height: 14),
        const _InfoBox(
          text:
              'La interfaz para Portal Stalker ya queda preparada. La conexión Stalker real se incorporará en la siguiente etapa para poder probar handshake, token y variantes de portal sin afectar M3U/Xtream.',
        ),
      ],
    );
  }

  void _focusFirstProviderField() {
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

  Future<void> _submit() async {
    final provider = context.read<IptvProvider>();
    FocusScope.of(context).unfocus();

    switch (_type) {
      case PlaylistSourceType.m3u:
        final url = _m3uUrlController.text.trim();
        final uri = Uri.tryParse(url);
        if (uri == null ||
            !(uri.scheme == 'http' || uri.scheme == 'https') ||
            uri.host.isEmpty) {
          _showMessage('Ingresá una URL M3U/M3U8 http/https válida.');
          return;
        }
        await provider.addPlaylistFromUrl(_nameController.text.trim(), url);
      case PlaylistSourceType.xtream:
        await provider.addXtreamSource(
          name: _nameController.text.trim(),
          serverUrl: _serverController.text.trim(),
          username: _usernameController.text.trim(),
          password: _passwordController.text,
        );
      case PlaylistSourceType.stalker:
        _showMessage(
          'Portal Stalker está preparado en la interfaz, pero todavía no activamos la conexión real en esta primera entrega.',
        );
        return;
    }

    if (!mounted) return;
    if (provider.error == null) Navigator.of(context).pop();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _SourceSelector extends StatelessWidget {
  final PlaylistSourceType selected;
  final ValueChanged<PlaylistSourceType> onChanged;

  const _SourceSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 700;
        final items = PlaylistSourceType.values;

        if (compact) {
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: items
                .map(
                  (type) => ChoiceChip(
                    selected: type == selected,
                    label: Text(type.label),
                    onSelected: (_) => onChanged(type),
                  ),
                )
                .toList(),
          );
        }

        return Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Row(
            children: items.map((type) {
              final active = type == selected;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () => onChanged(type),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(vertical: 17),
                      decoration: BoxDecoration(
                        color: active
                            ? Theme.of(context).colorScheme.primary
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Text(
                        type.label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: active ? Colors.white : Colors.white70,
                          fontSize: 16,
                          fontWeight:
                              active ? FontWeight.w800 : FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}

class _TitleRow extends StatelessWidget {
  final PlaylistSourceType type;

  const _TitleRow({required this.type});

  @override
  Widget build(BuildContext context) {
    final icon = switch (type) {
      PlaylistSourceType.m3u => Icons.playlist_play_rounded,
      PlaylistSourceType.xtream => Icons.key_rounded,
      PlaylistSourceType.stalker => Icons.router_rounded,
    };

    return Row(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary, size: 30),
        const SizedBox(width: 12),
        Text(
          type.label,
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
      ],
    );
  }
}

class _InfoBox extends StatelessWidget {
  final String text;

  const _InfoBox({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.22),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            color: Theme.of(context).colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
