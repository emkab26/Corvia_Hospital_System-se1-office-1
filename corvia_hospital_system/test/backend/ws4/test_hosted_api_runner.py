"""Offline safety checks. No Supabase requests or credentials used."""
import base64
import io
import json
import unittest
import urllib.error
import uuid
from unittest.mock import Mock, patch

import run_hosted_api_tests as runner


PUBLIC = 'sb_publishable_' + 'synthetic_test_key'
ADMIN = 'sb_secret_' + 'synthetic_test_key'


def legacy(claims):
    payload = base64.urlsafe_b64encode(json.dumps(claims).encode()).decode().rstrip('=')
    return 'header.' + payload + '.signature'


class RunnerSafetyTests(unittest.TestCase):
    def test_keys_reject_wrong_role_project_and_malformed_claims(self):
        for key in (ADMIN, legacy([]), legacy({'role': 'anon', 'ref': 'other'}),
                    legacy({'role': 'service_role', 'ref': runner.PROJECT}), 'garbage'):
            with self.subTest(key_type=key.split('.')[0]):
                with self.assertRaises(runner.SafeFailure):
                    runner.validate_key(key)
        self.assertEqual(runner.validate_key(PUBLIC), PUBLIC)
        self.assertEqual(runner.validate_key(ADMIN, True), ADMIN)
        self.assertTrue(runner.validate_key(legacy({'role': 'anon', 'ref': runner.PROJECT})))

    def test_admin_key_cannot_be_used_for_patient_data(self):
        with patch.object(runner.urllib.request, 'build_opener') as opener:
            for path, admin in (('/rest/v1/incidents', False), ('/rest/v1/incidents', True),
                                ('/auth/v1/admin/users', False)):
                with self.assertRaises(runner.SafeFailure):
                    runner.request('GET', path, ADMIN, admin=admin)
            opener.assert_not_called()

    def test_no_redirect_or_foreign_target(self):
        self.assertIsNone(runner.NoRedirect().redirect_request(None, None, 302, '', {}, 'https://other'))
        with patch.object(runner.urllib.request, 'build_opener') as opener:
            for path in ('https://other', '//other', '/rest/v1/https://other', '/rest/v1/\\other'):
                with self.assertRaises(runner.SafeFailure):
                    runner.request('GET', path, PUBLIC)
            opener.assert_not_called()

    def test_response_errors_do_not_disclose_content(self):
        body = {'code': '42501', 'message': 'private patient details', 'hint': ADMIN}
        error = urllib.error.HTTPError(runner.ORIGIN, 403, 'secret', {},
                                      io.BytesIO(json.dumps(body).encode()))
        opener = Mock()
        opener.open.side_effect = error
        with patch.object(runner.urllib.request, 'build_opener', return_value=opener):
            self.assertEqual(runner.request('GET', '/rest/v1/incidents', PUBLIC),
                             (403, {'code': '42501'}))

    def test_network_failure_is_redacted_and_not_retried(self):
        opener = Mock()
        opener.open.side_effect = urllib.error.URLError(ADMIN)
        with patch.object(runner.urllib.request, 'build_opener', return_value=opener):
            with self.assertRaises(runner.SafeFailure) as caught:
                runner.request('POST', '/auth/v1/admin/users', ADMIN, admin=True)
        self.assertNotIn(ADMIN, str(caught.exception))
        self.assertIn('unknown', str(caught.exception))
        self.assertEqual(opener.open.call_count, 1)

    def test_noninteractive_credential_entry_fails_closed(self):
        with patch.dict(runner.os.environ, {}, clear=True), patch.object(runner.sys.stdin, 'isatty', return_value=False):
            with self.assertRaises(runner.SafeFailure):
                runner.read_key('NO_KEY', 'hidden')

    def test_provisioning_requires_exact_distinct_synthetic_identities(self):
        run_id = 'a' * 12
        accounts = {label: {'id': str(uuid.uuid4()), 'email': f'ws4-{run_id}-{label}@example.invalid'}
                    for label in runner.LABELS}
        organisations = [str(uuid.uuid4()), str(uuid.uuid4())]
        sql = runner.provision_sql(accounts, organisations, run_id)
        self.assertIn("raw_app_meta_data->>'ws4_test_run'", sql)
        self.assertIn('synthetic_only', sql)
        with self.assertRaises(runner.SafeFailure):
            runner.provision_sql(accounts, [organisations[0]] * 2, run_id)
        with self.assertRaises(runner.SafeFailure):
            runner.provision_sql(accounts, organisations, "';select 1;--")
        accounts['patient_a']['email'] = 'real@example.com'
        with self.assertRaises(runner.SafeFailure):
            runner.provision_sql(accounts, organisations, run_id)


if __name__ == '__main__':
    unittest.main()
