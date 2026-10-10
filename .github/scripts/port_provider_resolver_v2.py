from pathlib import Path

source_path = Path('.github/scripts/port_provider_resolver.py')
source = source_path.read_text()
marker = 'Path("test/provider_json_dynamic_resolver_test.dart").write_text('
start = source.find(marker)
if start < 0:
    raise SystemExit('Provider resolver test marker not found')

prefix = source[:start]
segment = source[start:]
old_open = "    r'''import 'dart:convert';"
if old_open not in segment:
    raise SystemExit('Nested Python raw-string opener not found')
segment = segment.replace(old_open, '    r"""import \'dart:convert\';', 1)

old_close = "\n'''\n)"
close_at = segment.rfind(old_close)
if close_at < 0:
    raise SystemExit('Nested Python raw-string closer not found')
segment = segment[:close_at] + '\n"""\n)' + segment[close_at + len(old_close):]

fixed = prefix + segment
exec(compile(fixed, str(source_path), 'exec'))
