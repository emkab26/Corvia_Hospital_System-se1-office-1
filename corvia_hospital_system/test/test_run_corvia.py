import base64
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import run_corvia


class LauncherTest(unittest.TestCase):
    def test_hosted_public_configuration(self):
        claims = base64.urlsafe_b64encode(json.dumps({'role': 'anon'}).encode()).decode().rstrip('=')
        config = run_corvia.public_defines({
            'SUPABASE_URL': 'https://example.supabase.co',
            'SUPABASE_ANON_KEY': f'header.{claims}.signature',
            'SERVICE_ROLE_KEY': 'should-not-be-copied',
        })
        self.assertEqual(config['CORVIA_ENV'], 'testing')
        self.assertEqual(config['CORVIA_EXPECTED_BACKEND_ORIGIN'], config['SUPABASE_URL'])
        self.assertNotIn('SERVICE_ROLE_KEY', config)

    def test_rejects_local_secret_and_mismatched_backend(self):
        for overrides in (
            {'SUPABASE_URL': 'http://localhost:54321'},
            {'SUPABASE_ANON_KEY': 'sb_secret_no'},
            {'CORVIA_EXPECTED_BACKEND_ORIGIN': 'https://other.example'},
        ):
            with self.subTest(overrides=tuple(overrides)):
                with self.assertRaises(ValueError):
                    run_corvia.public_defines({
                        'SUPABASE_URL': 'https://example.supabase.co',
                        'SUPABASE_ANON_KEY': 'sb_publishable_test',
                        **overrides,
                    })


if __name__ == '__main__':
    unittest.main()
