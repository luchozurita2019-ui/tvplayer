from pathlib import Path

path = Path('lib/screens/channel_list_screen.dart')
text = path.read_text()
old = '''                                _ChannelLogo(channel: channel),
'''
new = '''                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withValues(alpha: .16),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.live_tv_rounded),
                                ),
'''
if old not in text:
    raise SystemExit('No se encontro _ChannelLogo en layout TV V9')
path.write_text(text.replace(old, new, 1))
print('V9 compile fix aplicado: item de canal TV autosuficiente.')
