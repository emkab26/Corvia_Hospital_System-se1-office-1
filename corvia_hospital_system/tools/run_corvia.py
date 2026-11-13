"""Prepare public Flutter defines from .env and optionally start Corvia.

Windows: python tools/run_corvia.py [--device chrome]
Android Studio: run once with --prepare, then select Corvia Hosted Testing.
"""
import argparse
import base64
import json
from pathlib import Path
import shutil
import subprocess
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / '.corvia-dev-defines.json'
PUBLIC_OPTIONS = {'MAPTILER_KEY', 'OAUTH_REDIRECT_URL', 'STUN_SERVER'}


def read_env(path: Path) -> dict[str, str]:
    values = {}
    for line in path.read_text(encoding='utf-8-sig').splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        if line.startswith('export '):
            line = line[7:]
        if '=' not in line:
            raise ValueError('Invalid .env syntax')
        name, value = line.split('=', 1)
        value = value.strip()
        if len(value) > 1 and value[0] == value[-1] and value[0] in ('"', "'"):
            value = value[1:-1]
        values[name.strip()] = value
    return values


def public_defines(values: dict[str, str]) -> dict[str, str]:
    url = values.get('SUPABASE_URL', '').strip()
    parsed = urlsplit(url)
    if (parsed.scheme != 'https' or not parsed.netloc or parsed.username or
            parsed.password or parsed.path not in ('', '/') or parsed.query or
            parsed.fragment or parsed.hostname in
            {'localhost', '127.0.0.1', '::1', '10.0.2.2'}):
        raise ValueError('Expected a hosted HTTPS Supabase origin in .env')
    origin = f'{parsed.scheme}://{parsed.netloc}'
    key = values.get('SUPABASE_ANON_KEY', '').strip()
    if key.startswith('sb_publishable_'):
        pass
    elif len(key.split('.')) == 3:
        try:
            payload = key.split('.')[1]
            claims = json.loads(base64.urlsafe_b64decode(payload + '=' * (-len(payload) % 4)))
        except (ValueError, UnicodeError) as error:
            raise ValueError('Invalid Supabase public client key') from error
        if claims.get('role') != 'anon':
            raise ValueError('Only an anonymous Supabase client key is allowed')
    else:
        raise ValueError('Only a public Supabase client key is allowed')
    if values.get('CORVIA_EXPECTED_BACKEND_ORIGIN', origin).strip() != origin:
        raise ValueError('Configured backend origin differs from SUPABASE_URL')
    result = {
        'CORVIA_ENV': 'testing',
        'SUPABASE_URL': origin,
        'CORVIA_EXPECTED_BACKEND_ORIGIN': origin,
        'SUPABASE_ANON_KEY': key,
    }
    result.update({name: values[name] for name in PUBLIC_OPTIONS if values.get(name)})
    return result


def prepare(env_path: Path = ROOT / '.env', output: Path = OUTPUT) -> Path:
    data = public_defines(read_env(env_path))
    output.write_text(json.dumps(data, indent=2) + '\n', encoding='utf-8')
    return output


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prepare', action='store_true',
                        help='Refresh the local Run configuration input only')
    parser.add_argument('--device', help='Flutter device ID, such as chrome')
    args = parser.parse_args()
    try:
        prepared = prepare()
    except (OSError, ValueError) as error:
        # Never print the value or an exception containing the public key.
        print(f'Corvia launch configuration failed: {type(error).__name__}. Check .env public settings.')
        return 2
    print('Corvia hosted testing configuration prepared.')
    if args.prepare:
        return 0
    flutter = shutil.which('flutter.bat') or shutil.which('flutter')
    if flutter is None:
        print('Flutter was not found on PATH.')
        return 2
    command = [flutter, 'run', '-t', 'lib/main.dart',
               f'--dart-define-from-file={prepared.name}']
    if args.device:
        command += ['-d', args.device]
    return subprocess.run(command, cwd=ROOT, check=False).returncode


if __name__ == '__main__':
    raise SystemExit(main())
