from pathlib import Path

path = Path('lib/screens/channel_list_screen.dart')
text = path.read_text()
old = '''                                _ChannelLogo(channel: channel),
'''
new = '''                                Container(
                                  width: 46,
                                  height: 46,
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withValues(alpha: .14),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.live_tv_rounded, size: 24),
                                ),
'''
if old not in text:
    raise SystemExit('No se encontro _ChannelLogo en catalogo V10')
path.write_text(text.replace(old, new, 1))
print('V10 compile fix aplicado: catalogo TV compacto autosuficiente.')
