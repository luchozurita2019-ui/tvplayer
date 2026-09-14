from pathlib import Path

source = Path('.github/scripts/port_provider_resolver_v3.py').read_text()
exec(compile(source, '.github/scripts/port_provider_resolver_v3.py', 'exec'))
