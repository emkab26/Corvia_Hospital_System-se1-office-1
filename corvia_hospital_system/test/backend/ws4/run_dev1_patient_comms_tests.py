"""Test Dev 1 progress and voice contracts on a fresh, isolated PostgreSQL 15."""
import argparse
import json
from pathlib import Path
import uuid

from run_tests import Database, uid
from run_patient_intake_tests import REPO, operation, request, require
from run_team_ems_bridge_tests import run as run_bridge, HOSPITAL


def run(db, results):
    # Rebuild the existing reviewed synthetic WS4/team stack first.
    run_bridge(db, results)
    for file in ('006_patient_progress.sql', '007_incident_voice.sql',
                 '008_scoped_requester_identity.sql',
                 '009_patient_callback.sql',
                 '010_contact_alert_outbox.sql',
                 '011_patient_push_outbox.sql'):
        require(db.sql((REPO/'supabase/scripts/ws4_release'/file)
                       .read_text(encoding='utf-8')))
        results.append({'name': file + ' installed', 'passed': True})

    def check(name, sql, *, actor=None, expected='t', error=None):
        prefix = '' if actor is None else (
            "SET SESSION AUTHORIZATION ws4_test_api; SET ROLE authenticated; "
            f"SET request.jwt.claim.sub='{uid(actor)}'; ")
        response = db.sql(prefix + sql)
        ok = (response.returncode != 0 and error in response.stderr) if error else (
            response.returncode == 0 and
            (expected is None or response.stdout.strip() == expected))
        results.append({'name': name, 'passed': ok,
                        'stdout': response.stdout.strip(),
                        'stderr': response.stderr.strip()})
        print(('PASS ' if ok else 'FAIL ') + name, flush=True)
        if not ok:
            raise AssertionError(name + ': ' + response.stdout + response.stderr)
        return response.stdout.strip()

    incident = json.loads(check('new synthetic patient request',
        f'SELECT {request(901)};', actor=1, expected=None))['incident_id']
    require(db.sql(f"UPDATE public.profiles SET first_name='Asha',surname='Example' "
                   f"WHERE user_id='{uid(1)}';"))
    check('scoped dispatcher sees requester name before claim',
          f"SELECT public.corvia_ws4_requester_identity({incident})->>'requester_name'='Asha Example';",
          actor=3)
    check('patient cannot read dispatcher requester projection',
          f'SELECT public.corvia_ws4_requester_identity({incident});',
          actor=1, error='42501')
    check('different patient cannot read requester name',
          f'SELECT public.corvia_ws4_requester_identity({incident});',
          actor=2, error='42501')
    check('patient sees waiting stage',
          f"SELECT public.corvia_ws4_patient_progress({incident})->>'stage'='waiting_for_dispatch';",
          actor=1)
    check('different patient cannot read progress',
          f'SELECT public.corvia_ws4_patient_progress({incident});',
          actor=2, error='42501')
    check('patient cannot read team internals',
          f'SELECT public.corvia_ws4_team_snapshot({incident});',
          actor=1, error='42501')
    check('dispatch claim',
          f"SELECT public.corvia_dispatch_accept_incident({incident})->>'status'='in_progress';",
          actor=3)
    check('patient sees accepted stage',
          f"SELECT public.corvia_ws4_patient_progress({incident})->>'stage'='dispatch_accepted';",
          actor=1)
    check('patient cannot read private signalling table',
          'SELECT count(*) FROM ws4_private.voice_sessions;',
          actor=1, error='42501')

    callback_request = (
        f"public.corvia_patient_request_emergency('{operation(906)}',"
        "NULL,NULL,NULL,NULL,'Synthetic entrance','Synthetic test',"
        "'+27 82 123 4567')")
    callback_incident = json.loads(check('callback request is captured',
        f'SELECT {callback_request};', actor=1, expected=None))['incident_id']
    check('patient retry retains original callback',
          f"SELECT {callback_request}->>'callback_number'='+27821234567';",
          actor=1)
    check('changed callback on same operation denied',
          f"SELECT public.corvia_patient_request_emergency('{operation(906)}',"
          "NULL,NULL,NULL,NULL,'Synthetic entrance','Synthetic test',"
          "'+27829999999');", actor=1, error='22023')
    check('unclaimed dispatcher cannot read callback',
          f'SELECT public.corvia_ws4_callback_number({callback_incident});',
          actor=3, error='42501')
    check('dispatcher claims callback incident',
          f"SELECT public.corvia_dispatch_accept_incident({callback_incident})->>'status'='in_progress';",
          actor=3)
    check('claimant reads only explicit callback number',
          f"SELECT public.corvia_ws4_callback_number({callback_incident})->>'callback_number'='+27821234567';",
          actor=3)
    check('other patient cannot read callback number',
          f'SELECT public.corvia_ws4_callback_number({callback_incident});',
          actor=2, error='42501')

    contacts = json.dumps([{
        'id': operation(907), 'name': 'Synthetic Contact',
        'relationship': 'Family', 'phone_number': '+27 82 123 4567',
        'is_primary': True, 'notify_on_emergency': True,
    }])
    check('patient saves one opted-in server contact',
          f"SELECT jsonb_array_length(public.corvia_ws4_contacts_replace('{contacts}'::jsonb))=1;",
          actor=1)
    check('other patient sees no contacts',
          'SELECT public.corvia_ws4_contacts_get()=\'[]\'::jsonb;', actor=2)
    check('patient cannot read private contact table',
          'SELECT count(*) FROM ws4_private.emergency_contacts;',
          actor=1, error='42501')
    alert_request = request(908)
    alert_incident = json.loads(check('patient request queues contact alert',
          f'SELECT {alert_request};', actor=1, expected=None))['incident_id']
    check('same patient request does not queue duplicate alert',
          f'SELECT {alert_request};', actor=1, expected=None)
    check('one durable alert exists',
          f'SELECT count(*)=1 FROM ws4_private.contact_alert_outbox WHERE incident_id={alert_incident};')
    check('patient sees queued but not delivered',
          f"SELECT (public.corvia_ws4_contact_alert_status({alert_incident})->'counts'->>'queued')::int=1;",
          actor=1)
    check('other patient cannot read alert status',
          f'SELECT public.corvia_ws4_contact_alert_status({alert_incident});',
          actor=2, error='42501')
    check('patient cannot claim provider queue',
          'SELECT public.corvia_ws4_contact_alert_claim(1);',
          actor=1, error='42501')
    claimed = json.loads(check('service worker claims generic alert',
          "SET ROLE service_role; SET request.jwt.claim.role='service_role'; "
          'SELECT public.corvia_ws4_contact_alert_claim(1);', expected=None))
    alert_id = claimed[0]['alert_id']
    check('service acknowledges provider acceptance, not delivery',
          "SET ROLE service_role; SET request.jwt.claim.role='service_role'; "
          f"SELECT public.corvia_ws4_contact_alert_ack({alert_id},'provider_accepted','synthetic-ref');")
    check('patient sees provider accepted separately from delivered',
          f"SELECT (public.corvia_ws4_contact_alert_status({alert_incident})->'counts'->>'provider_accepted')::int=1;",
          actor=1)
    check('service receipt marks matching provider delivery',
          "SET ROLE service_role; SET request.jwt.claim.role='service_role'; "
          f"SELECT public.corvia_ws4_contact_alert_receipt({alert_id},'synthetic-ref');")
    check('patient sees reported delivery',
          f"SELECT (public.corvia_ws4_contact_alert_status({alert_incident})->'counts'->>'delivered')::int=1;",
          actor=1)
    check('revoking a contact does not erase prior audit row',
          "SELECT jsonb_array_length(public.corvia_ws4_contacts_replace('[]'::jsonb))=0;",
          actor=1)
    check('prior alert audit remains after contact revocation',
          f'SELECT count(*)=1 FROM ws4_private.contact_alert_outbox WHERE incident_id={alert_incident};')

    device_id = operation(909)
    token = 'synthetic-fcm-token-' + 'x'*40
    check('patient registers own synthetic push token',
          f"SELECT public.corvia_ws4_push_register('{device_id}','fcm','{token}');",
          actor=1)
    check('another patient cannot revoke the device',
          f"SELECT public.corvia_ws4_push_revoke('{device_id}')=false;",
          actor=2)
    push_incident = json.loads(check('new incident queues generic push',
          f'SELECT {request(910)};',actor=1,expected=None))['incident_id']
    check('one push is queued for one device',
          f'SELECT count(*)=1 FROM ws4_private.push_outbox WHERE incident_id={push_incident};')
    rotated_token = 'synthetic-rotated-token-' + 'y'*40
    check('rotating a device token succeeds',
          f"SELECT public.corvia_ws4_push_register('{device_id}','fcm','{rotated_token}');",
          actor=1)
    check('rotation invalidates the old pending token',
          f"SELECT count(*)=1 FROM ws4_private.push_outbox WHERE incident_id={push_incident} AND status='failed';")
    push_incident = json.loads(check('next incident uses the rotated token',
          f'SELECT {request(911)};',actor=1,expected=None))['incident_id']
    check('rotated token is queued once',
          f"SELECT count(*)=1 FROM ws4_private.push_outbox WHERE incident_id={push_incident} AND token='{rotated_token}';")
    check('patient cannot read private push tokens',
          'SELECT count(*) FROM ws4_private.push_subscriptions;',
          actor=1,error='42501')
    check('patient cannot claim push queue',
          'SELECT public.corvia_ws4_push_claim(1);',actor=1,error='42501')
    push_claimed = json.loads(check('service claims generic push',
          "SET ROLE service_role; SET request.jwt.claim.role='service_role'; "
          'SELECT public.corvia_ws4_push_claim(1);',expected=None))
    push_id = push_claimed[0]['alert_id']
    check('service records provider acceptance, not delivery',
          "SET ROLE service_role; SET request.jwt.claim.role='service_role'; "
          f"SELECT public.corvia_ws4_push_ack({push_id},'provider_accepted','push-ref');")
    check('patient revokes own device token',
          f"SELECT public.corvia_ws4_push_revoke('{device_id}');",actor=1)
    check('revoke removes token from active subscriptions',
          f"SELECT count(*)=0 FROM ws4_private.push_subscriptions WHERE installation_id='{device_id}';")
    check('revoked device receives no later claim update',
          f"SELECT public.corvia_dispatch_accept_incident({push_incident})->>'status'='in_progress';",
          actor=3)
    check('no second push queued after device revocation',
          f'SELECT count(*)=1 FROM ws4_private.push_outbox WHERE incident_id={push_incident};')

    start = json.loads(check('patient starts incident-linked voice',
        f"SELECT public.corvia_ws4_voice_start({incident},'{operation(902)}','synthetic-offer');",
        actor=1, expected=None))
    call_id = start['session_id']
    check('same start operation returns same call',
          f"SELECT public.corvia_ws4_voice_start({incident},'{operation(902)}','synthetic-offer')->>'session_id'='{call_id}';",
          actor=1)
    check('changed offer with same operation denied',
          f"SELECT public.corvia_ws4_voice_start({incident},'{operation(902)}','different-offer');",
          actor=1, error='22023')
    check('second patient cannot read voice session',
          f"SELECT public.corvia_ws4_voice_exchange({incident},'{call_id}',0);",
          actor=2, error='42501')
    check('claimed dispatcher discovers only own call',
          f"SELECT public.corvia_ws4_voice_incoming() @> '[{{\"session_id\":\"{call_id}\"}}]'::jsonb;",
          actor=3)
    check('unrelated account has no incoming call',
          "SELECT public.corvia_ws4_voice_incoming()='[]'::jsonb;",
          actor=2)
    check('dispatcher reads caller offer',
          f"SELECT public.corvia_ws4_voice_exchange({incident},'{call_id}',0)->>'offer_sdp'='synthetic-offer';",
          actor=3)
    check('patient cannot answer own call',
          f"SELECT public.corvia_ws4_voice_answer({incident},'{call_id}','synthetic-answer');",
          actor=1, error='42501')
    check('dispatcher answers',
          f"SELECT public.corvia_ws4_voice_answer({incident},'{call_id}','synthetic-answer')->>'status'='answered';",
          actor=3)
    check('patient reads answer',
          f"SELECT public.corvia_ws4_voice_exchange({incident},'{call_id}',0)->>'answer_sdp'='synthetic-answer';",
          actor=1)
    check('patient sends one ICE candidate',
          f"SELECT (public.corvia_ws4_voice_candidate({incident},'{call_id}',"
          f"'{operation(903)}','{{\"candidate\":\"synthetic\"}}'::jsonb)->>'id')::bigint>0;",
          actor=1)
    check('dispatcher receives patient ICE only',
          f"SELECT jsonb_array_length(public.corvia_ws4_voice_exchange({incident},'{call_id}',0)->'candidates')=1;",
          actor=3)
    check('same ICE operation can be retried',
          f"SELECT (public.corvia_ws4_voice_candidate({incident},'{call_id}',"
          f"'{operation(903)}','{{\"candidate\":\"synthetic\"}}'::jsonb)->>'id')::bigint>0;",
          actor=1)
    check('candidate retry is idempotent',
          f"SELECT count(*)=1 FROM ws4_private.voice_candidates WHERE session_id='{call_id}';")
    check('changed ICE with same operation denied',
          f"SELECT public.corvia_ws4_voice_candidate({incident},'{call_id}',"
          f"'{operation(903)}','{{\"candidate\":\"different\"}}'::jsonb);",
          actor=1, error='22023')
    check('unrelated account cannot end voice',
          f"SELECT public.corvia_ws4_voice_end({incident},'{call_id}');",
          actor=2, error='42501')
    check('patient ends voice',
          f"SELECT public.corvia_ws4_voice_end({incident},'{call_id}')->>'status'='ended';",
          actor=1)
    check('ending voice leaves incident open',
          f"SELECT status='in_progress' FROM public.incidents WHERE id={incident};")
    next_call = json.loads(check('new call can start after prior end',
          f"SELECT public.corvia_ws4_voice_start({incident},'{operation(904)}','new-offer');",
          actor=1, expected=None))['session_id']
    require(db.sql(f"UPDATE ws4_private.voice_sessions SET created_at=now()-interval '61 seconds' WHERE id='{next_call}';"))
    check('old unanswered call is not shown as active',
          f"SELECT public.corvia_ws4_voice_exchange({incident},'{next_call}',0)->>'status'='timed_out';",
          actor=1)
    check('timed-out offer cannot be answered',
          f"SELECT public.corvia_ws4_voice_answer({incident},'{next_call}','late-answer');",
          actor=3, error='P0001')
    check('new start expires the stale ringing session',
          f"SELECT public.corvia_ws4_voice_start({incident},'{operation(905)}','third-offer')->>'status'='ringing';",
          actor=1)
    check('voice cleanup cannot be called by a patient',
          'SELECT public.corvia_ws4_voice_purge();', actor=1, error='42501')
    require(db.sql(f"UPDATE ws4_private.voice_sessions SET created_at=now()-interval '25 hours' WHERE incident_id={incident};"))
    check('service-authorized retention worker removes old signalling',
          "SET request.jwt.claim.role='service_role'; "
          "SELECT public.corvia_ws4_voice_purge()>=1; "
          "SELECT count(*)=0 FROM ws4_private.voice_sessions; "
          "SELECT count(*)=0 FROM ws4_private.voice_candidates;",
          expected='t\nt\nt')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pg-bin', type=Path, required=True)
    args = parser.parse_args()
    work = REPO/'build/ws4-dev1-rehearsal'/uuid.uuid4().hex
    work.mkdir(parents=True)
    db = Database(args.pg_bin.resolve(), work)
    report = {'results': []}
    try:
        db.start()
        run(db, report['results'])
        report['passed'] = True
    except Exception as error:
        report.update(passed=False, error=str(error))
        raise
    finally:
        db.stop()
        report['server_stopped'] = not db.started
        (work/'result.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
        print('Report: ' + str(work/'result.json'), flush=True)


if __name__ == '__main__':
    main()
