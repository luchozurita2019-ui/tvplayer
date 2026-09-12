from pathlib import Path

source_path = Path('.github/scripts/apply_dynamic_stream_resolver_v40.py')
text = source_path.read_text()
old_open = "  const config = '''\n{"
new_open = '  const config = """\n{'
old_close = "}\n''';\n\n  test("
new_close = '}\n""";\n\n  test('

if text.count(old_open) != 1:
    raise SystemExit(f'test config opening delimiter: expected 1 match, found {text.count(old_open)}')
if text.count(old_close) != 1:
    raise SystemExit(f'test config closing delimiter: expected 1 match, found {text.count(old_close)}')

fixed = text.replace(old_open, new_open, 1).replace(old_close, new_close, 1)

# The patch source is embedded in Python raw strings. Avoid a Dart raw
# single-quoted RegExp containing a literal single quote, which is invalid Dart.
lines = fixed.splitlines()
marker = "    return body.replaceAll(RegExp("
matches = [index for index, line in enumerate(lines) if line.startswith(marker)]
if len(matches) != 1:
    raise SystemExit(f'Dart quote cleanup line: expected 1 match, found {len(matches)}')
index = matches[0]
lines[index:index + 1] = [
    '    var cleaned = body.trim();',
    '    if (cleaned.length >= 2 &&',
    '        ((cleaned.startsWith(\'"\') && cleaned.endsWith(\'"\')) ||',
    '            (cleaned.startsWith("\'") && cleaned.endsWith("\'")))) {',
    '      cleaned = cleaned.substring(1, cleaned.length - 1).trim();',
    '    }',
    '    return cleaned;',
]
fixed = '\n'.join(lines) + '\n'

compile(fixed, str(source_path), 'exec')
exec(compile(fixed, str(source_path), 'exec'), {'__name__': '__main__'})
