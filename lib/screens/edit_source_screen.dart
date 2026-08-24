import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/playlist.dart';
import '../models/playlist_source_type.dart';
import '../providers/iptv_provider.dart';

class EditSourceScreen extends StatefulWidget {
  final Playlist playlist;

  const EditSourceScreen({super.key, required this.playlist});

  @override
  State<EditSourceScreen> createState() => _EditSourceScreenState();
}

class _EditSourceScreenState extends State<EditSourceScreen> {
  final _nameController = TextEditingController();
  final _m3uUrlController = TextEditingController();
  final _serverController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    final playlist = widget.playlist;
    _nameController.text = playlist.name;

    if (playlist.sourceType == PlaylistSourceType.xtream) {
      final parsed = _parseXtreamSource(playlist.source);
      if (parsed != null) {
        _serverController.text = parsed.server;
        _usernameController.text = parsed.username;
        _passwordController.text = parsed.password;
      }
    } else if (playlist.sourceType == PlaylistSourceType.m3u &&
        playlist.isRemote) {
      _m3uUrlController.text = playlist.source;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _m3uUrlController.dispose();
    _serverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IptvProvider>();
    final playlist = widget.playlist;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'TV FULL · Editar servicio',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 50),
            children: [
              Text(
                'Editar ${playlist.sourceType.label}',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              const Text(
                'Los cambios conservan la lista existente y reemplazan su contenido cuando la nueva fuente valida correctamente.',
              ),
              const SizedBox(height: 22),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Nombre del servicio',
                          prefixIcon: Icon(Icons.label_outline),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _sourceFields(playlist),
                    ],
                  ),
                ),
              ),
              if (provider.error != null) ...[
                const SizedBox(height: 14),
                Container(
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
                          provider.error!,
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 22),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: provider.loading ? null : _save,
                  icon: provider.loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(
                    provider.loading ? 'Guardando…' : 'Guardar cambios',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sourceFields(Playlist playlist) {
    switch (playlist.sourceType) {
      case PlaylistSourceType.m3u:
        if (!playlist.isRemote) {
          return const Text(
            'Esta lista fue cargada desde un archivo local. Podés cambiar su nombre; para reemplazar el archivo cargá una nueva fuente.',
          );
        }
        return TextField(
          controller: _m3uUrlController,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'URL M3U/M3U8',
            prefixIcon: Icon(Icons.link_rounded),
          ),
        );
      case PlaylistSourceType.xtream:
        return Column(
          children: [
            TextField(
              controller: _serverController,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Servidor / Host',
                prefixIcon: Icon(Icons.dns_outlined),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _usernameController,
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
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        tooltip: _obscurePassword ? 'Mostrar' : 'Ocultar',
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
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
            const Text(
              'Al guardar, TV FULL vuelve a validar player_api.php y descarga el catálogo actualizado sin que tengas que borrar la lista.',
            ),
          ],
        );
      case PlaylistSourceType.stalker:
        return const Text(
          'Portal Stalker todavía no tiene conexión activa. Por ahora podés editar el nombre del servicio.',
        );
    }
  }

  Future<void> _save() async {
    final provider = context.read<IptvProvider>();
    final playlist = widget.playlist;
    FocusScope.of(context).unfocus();

    switch (playlist.sourceType) {
      case PlaylistSourceType.m3u:
        if (playlist.isRemote) {
          final url = _m3uUrlController.text.trim();
          final uri = Uri.tryParse(url);
          if (uri == null ||
              !(uri.scheme == 'http' || uri.scheme == 'https') ||
              uri.host.isEmpty) {
            _message('Ingresá una URL M3U/M3U8 http/https válida.');
            return;
          }
          await provider.updatePlaylistFromUrl(
            playlistId: playlist.id,
            name: _nameController.text.trim(),
            url: url,
          );
        } else {
          await provider.renamePlaylist(
            playlist.id,
            _nameController.text.trim(),
          );
        }
      case PlaylistSourceType.xtream:
        if (_serverController.text.trim().isEmpty ||
            _usernameController.text.trim().isEmpty ||
            _passwordController.text.isEmpty) {
          _message('Completá servidor, usuario y contraseña.');
          return;
        }
        await provider.updateXtreamSource(
          playlistId: playlist.id,
          name: _nameController.text.trim(),
          serverUrl: _serverController.text.trim(),
          username: _usernameController.text.trim(),
          password: _passwordController.text,
        );
      case PlaylistSourceType.stalker:
        await provider.renamePlaylist(playlist.id, _nameController.text.trim());
    }

    if (!mounted) return;
    if (provider.error == null) Navigator.of(context).pop();
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  _XtreamEditData? _parseXtreamSource(String source) {
    final uri = Uri.tryParse(source);
    if (uri == null || uri.host.isEmpty) return null;
    final username = uri.queryParameters['username'] ?? '';
    final password = uri.queryParameters['password'] ?? '';

    var path = uri.path;
    if (path.toLowerCase().endsWith('/get.php')) {
      path = path.substring(0, path.length - '/get.php'.length);
    } else if (path.toLowerCase().endsWith('get.php')) {
      path = path.substring(0, path.length - 'get.php'.length);
      if (path.endsWith('/')) path = path.substring(0, path.length - 1);
    }

    final base = uri.replace(
      path: path.isEmpty ? '/' : path,
      query: '',
      fragment: '',
    );
    return _XtreamEditData(
      server: base.toString().replaceAll(RegExp(r'/$'), ''),
      username: username,
      password: password,
    );
  }
}

class _XtreamEditData {
  final String server;
  final String username;
  final String password;

  const _XtreamEditData({
    required this.server,
    required this.username,
    required this.password,
  });
}
