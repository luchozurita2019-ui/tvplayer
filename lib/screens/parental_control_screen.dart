import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/iptv_provider.dart';
import '../services/parental_control_service.dart';

class ParentalControlScreen extends StatefulWidget {
  const ParentalControlScreen({super.key});

  @override
  State<ParentalControlScreen> createState() => _ParentalControlScreenState();
}

class _ParentalControlScreenState extends State<ParentalControlScreen> {
  final ParentalControlService _parental = ParentalControlService.instance;
  String _groupQuery = '';

  @override
  void initState() {
    super.initState();
    unawaited(_parental.init());
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IptvProvider>();
    final allGroups = <String>{};
    for (final playlist in provider.playlists) {
      for (final channel in playlist.channels) {
        final group = channel.group?.trim();
        if (group != null && group.isNotEmpty) allGroups.add(group);
      }
    }
    final groups = allGroups.toList()..sort();

    return AnimatedBuilder(
      animation: _parental,
      builder: (context, _) {
        final normalizedQuery = _groupQuery.trim().toLowerCase();
        final filteredGroups = normalizedQuery.isEmpty
            ? groups
            : groups
                .where((group) => group.toLowerCase().contains(normalizedQuery))
                .toList(growable: false);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Control parental'),
          ),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _statusCard(context),
              const SizedBox(height: 16),
              if (!_parental.pinConfigured)
                _setupCard(context)
              else ...[
                _generalSettingsCard(context),
                const SizedBox(height: 16),
                _categorySettingsCard(context, filteredGroups),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _statusCard(BuildContext context) {
    final active = _parental.enabled;
    final unlocked = _parental.isUnlocked;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                !active
                    ? Icons.shield_outlined
                    : unlocked
                        ? Icons.lock_open_rounded
                        : Icons.lock_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    !active
                        ? 'Control parental desactivado'
                        : unlocked
                            ? 'Contenido protegido desbloqueado'
                            : 'Contenido protegido bloqueado',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    !_parental.pinConfigured
                        ? 'Creá un PIN de 4 dígitos para comenzar.'
                        : active
                            ? 'TV FULL protege categorías y resultados adultos con tu PIN.'
                            : 'Tu PIN está guardado y podés volver a activar la protección cuando quieras.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _setupCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Crear PIN parental',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            const Text(
              'El PIN se usa para abrir categorías protegidas y para cambiar la configuración parental.',
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _createPin,
              icon: const Icon(Icons.pin_rounded),
              label: const Text('Crear PIN de 4 dígitos'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _generalSettingsCard(BuildContext context) {
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.shield_rounded),
            title: const Text('Activar control parental'),
            subtitle: const Text('Bloquea categorías y contenido detectado como adulto.'),
            value: _parental.enabled,
            onChanged: (value) => unawaited(_parental.setEnabled(value)),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.visibility_off_rounded),
            title: const Text('Ocultamiento automático'),
            subtitle: const Text(
              'Con el candado cerrado, TV FULL oculta automáticamente las categorías protegidas. Al desbloquear, vuelven a aparecer.',
            ),
            trailing: const Icon(Icons.check_circle_rounded),
            enabled: _parental.enabled,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('Tiempo de desbloqueo'),
            subtitle: const Text('Después de ese tiempo, TV FULL vuelve a pedir el PIN.'),
            trailing: DropdownButton<int>(
              value: _parental.unlockMinutes,
              items: const [
                DropdownMenuItem(value: 5, child: Text('5 min')),
                DropdownMenuItem(value: 15, child: Text('15 min')),
                DropdownMenuItem(value: 30, child: Text('30 min')),
                DropdownMenuItem(value: 60, child: Text('60 min')),
              ],
              onChanged: _parental.enabled
                  ? (value) {
                      if (value != null) {
                        unawaited(_parental.setUnlockMinutes(value));
                      }
                    }
                  : null,
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (_parental.enabled && _parental.isLocked)
                  FilledButton.icon(
                    onPressed: _unlockTemporarily,
                    icon: const Icon(Icons.lock_open_rounded),
                    label: Text('Desbloquear ${_parental.unlockMinutes} min'),
                  ),
                if (_parental.enabled && _parental.isUnlocked)
                  FilledButton.tonalIcon(
                    onPressed: _parental.lockNow,
                    icon: const Icon(Icons.lock_rounded),
                    label: const Text('Bloquear ahora'),
                  ),
                OutlinedButton.icon(
                  onPressed: _changePin,
                  icon: const Icon(Icons.password_rounded),
                  label: const Text('Cambiar PIN'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _categorySettingsCard(BuildContext context, List<String> groups) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
            child: Text(
              'Categorías protegidas',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18),
            child: Text(
              'TV FULL detecta automáticamente categorías como Adultos, XXX, 18+, OnlyFans y similares. También podés proteger o permitir cualquier categoría manualmente.',
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Buscar categoría…',
                prefixIcon: Icon(Icons.search_rounded),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (value) => setState(() => _groupQuery = value),
            ),
          ),
          const Divider(height: 1),
          if (groups.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('No hay categorías que coincidan con la búsqueda.'),
            )
          else
            SizedBox(
              height: 420,
              child: ListView.builder(
                itemCount: groups.length,
                itemBuilder: (context, index) {
                  final group = groups[index];
                  final protected = _parental.isProtectedGroup(group);
                  return SwitchListTile(
                    dense: true,
                    secondary: Icon(
                      protected ? Icons.lock_rounded : Icons.folder_outlined,
                    ),
                    title: Text(group),
                    subtitle: protected
                        ? const Text('Protegida con PIN')
                        : const Text('Sin protección'),
                    value: protected,
                    onChanged: (value) => unawaited(
                      _parental.setGroupProtected(group, value),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _createPin() async {
    final first = await _askPin('Crear PIN', 'Ingresá 4 números');
    if (!mounted || first == null) return;
    if (!_validPin(first)) return;
    final second = await _askPin('Confirmar PIN', 'Repetí los mismos 4 números');
    if (!mounted || second == null) return;
    if (first != second) {
      _message('Los PIN no coinciden.');
      return;
    }
    await _parental.setPin(first);
    if (mounted) _message('Control parental activado.');
  }

  Future<void> _changePin() async {
    final current = await _askPin('PIN actual', 'Ingresá tu PIN actual');
    if (!mounted || current == null) return;
    if (!_parental.verifyPin(current)) {
      _message('PIN incorrecto.');
      return;
    }
    final next = await _askPin('Nuevo PIN', 'Ingresá 4 números');
    if (!mounted || next == null) return;
    if (!_validPin(next)) return;
    final confirmation = await _askPin('Confirmar nuevo PIN', 'Repetí el nuevo PIN');
    if (!mounted || confirmation == null) return;
    if (next != confirmation) {
      _message('Los PIN no coinciden.');
      return;
    }
    await _parental.setPin(next);
    if (mounted) _message('PIN actualizado.');
  }

  Future<void> _unlockTemporarily() async {
    final pin = await _askPin('Desbloquear contenido', 'Ingresá tu PIN parental');
    if (!mounted || pin == null) return;
    final ok = await _parental.unlock(pin);
    if (!mounted) return;
    _message(ok
        ? 'Contenido desbloqueado por ${_parental.unlockMinutes} minutos.'
        : 'PIN incorrecto.');
  }

  bool _validPin(String value) {
    if (RegExp(r'^\d{4}$').hasMatch(value)) return true;
    _message('El PIN debe tener exactamente 4 números.');
    return false;
  }

  Future<String?> _askPin(String title, String hint) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 4,
          decoration: InputDecoration(
            hintText: hint,
            counterText: '',
          ),
          onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  void _message(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
