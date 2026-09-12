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
compile(fixed, str(source_path), 'exec')
exec(compile(fixed, str(source_path), 'exec'), {'__name__': '__main__'})
