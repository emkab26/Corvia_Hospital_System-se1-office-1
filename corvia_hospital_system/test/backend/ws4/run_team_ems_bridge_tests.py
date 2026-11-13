"""Exercise the WS4/team EMS bridge on a fresh, isolated PostgreSQL cluster."""
import argparse
from datetime import datetime, timedelta, timezone
import importlib.util
import json
from pathlib import Path
import uuid

from run_tests import Database, ROOT, uid
from run_patient_intake_tests import REPO, A, request, operation, require


spec = importlib.util.spec_from_file_location(
    'build_shared', REPO/'tools/build_ws4_shared_upgrade.py')
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)

HOSPITAL = 'aaaaaaaa-1111-4111-8111-111111111111'


def run(db, results):
    def check(name, sql, *, actor=None, expected='t', error=None):
        if actor is None:
            response = db.sql(sql)
        else:
            # Supabase uses an authenticator session, not postgres as session_user.
            # This also prevents the team's service-owner shortcut from making
            # every synthetic user a hospital administrator.
            prefix = ("SET SESSION AUTHORIZATION ws4_test_api; SET ROLE authenticated; "
                      f"SET request.jwt.claim.sub='{uid(actor)}'; ")
            response = db.sql(prefix + sql)
        ok = (response.returncode != 0 and error in response.stderr) if error else (
            response.returncode == 0 and
            (expected is None or response.stdout.strip() == expected))
        results.append(dict(name=name, passed=ok, stdout=response.stdout.strip(),
                            stderr=response.stderr.strip()))
        print(('PASS ' if ok else 'FAIL ') + name, flush=True)
        if not ok:
            raise AssertionError(name + ': ' + response.stdout + response.stderr)
        return response.stdout.strip()

    def team_command(name, actor, session_token, action, payload, number):
        body = json.dumps(payload, separators=(',', ':')).replace("'", "''")
        raw = check(name,
            f"SELECT public.corvia_ems_command('{HOSPITAL}','{session_token}',"
            f"'{operation(number)}','{action}','{body}'::jsonb);",
            actor=actor, expected=None)
        return json.loads(raw)

    def team_action(name, actor, session_token, incident_id, action, payload, number):
        revision = int(check(name + ' revision',
            f'SELECT revision FROM public.corvia_ws6_incidents_actual WHERE incident_id={incident_id};',
            expected=None))
        return team_command(name, actor, session_token, action,
            {'incident_id': incident_id, 'revision': revision, **payload}, number)

    require(db.sql((ROOT/'baseline/catalog.sql').read_text(encoding='utf-8')))
    require(db.sql((ROOT/'baseline/fixtures.sql').read_text(encoding='utf-8')))
    require(db.sql(f"""
      UPDATE public.incidents SET status='pending' WHERE id IN (105,106);
      ALTER TABLE auth.users ADD COLUMN email text;
      UPDATE auth.users SET email='synthetic-'||right(id::text,1)||'@example.test';
      CREATE TABLE public.hospitals(id uuid PRIMARY KEY,name text,is_active boolean NOT NULL);
      CREATE TABLE public.hospital_admins(hospital_id uuid,profile_id uuid);
      INSERT INTO public.hospitals VALUES('{HOSPITAL}','Synthetic hospital',true);
      CREATE ROLE ws4_test_api LOGIN;
      GRANT authenticated TO ws4_test_api;
    """))
    require(db.sql("SET corvia.ws4_shared_review='approved';\n" + builder.build()))
    require(db.sql((REPO/'supabase/scripts/workstreams/11_install_fleet_paramedic.sql').read_text(encoding='utf-8')))
    require(db.sql((REPO/'supabase/scripts/workstreams/13_dispatch_fleet_upgrade.sql').read_text(encoding='utf-8')))
    require(db.sql((REPO/'supabase/scripts/ws4_release/002_team_ems_handoff.sql').read_text(encoding='utf-8')))
    require(db.sql((REPO/'supabase/scripts/ws4_release/003_team_ems_completion.sql').read_text(encoding='utf-8')))
    require(db.sql((REPO/'supabase/scripts/ws4_release/004_team_backup_receiver.sql').read_text(encoding='utf-8')))
    require(db.sql((REPO/'supabase/scripts/ws4_release/005_team_operational_completion.sql').read_text(encoding='utf-8')))
    results.append(dict(name='combined owner-reviewed contracts install', passed=True))

    require(db.sql(f"""
      INSERT INTO ws4_private.organisations VALUES('{A}','Synthetic region');
      INSERT INTO ws4_private.patient_routes VALUES('{uid(1)}','{A}');
      INSERT INTO ws4_private.patient_routes VALUES('{uid(2)}','{A}');
      INSERT INTO ws4_private.memberships VALUES('{uid(3)}','{A}','dispatcher',true);
    """))
    incident = json.loads(check('patient request stays in WS4',
        f'SELECT {request(801)};', actor=1, expected=None))['incident_id']
    check('unrouted incident stays unlinked',
          f"SELECT public.corvia_ws4_ems_handoff_status({incident})->>'mode'='unconfigured';",
          actor=3)
    check('unrouted handoff denied',
          f"SELECT public.corvia_ws4_handoff_to_ems({incident},'{HOSPITAL}',"
          f"'{operation(802)}','{operation(803)}','High','ALS');",
          actor=3,error='42501')
    require(db.sql(f"INSERT INTO ws4_private.ems_handoff_routes VALUES('{A}','{HOSPITAL}',true,now());"))
    check('separate EMS membership required',
          f"SELECT public.corvia_ws4_ems_handoff_status({incident})->>'team_access'='false';",
          actor=3)
    require(db.sql(f"INSERT INTO public.corvia_ops_memberships(hospital_id,user_id,role,granted_by) VALUES('{HOSPITAL}','{uid(3)}','dispatcher','{uid(5)}');"))
    check('claim WS4 patient incident',
          f"SELECT public.corvia_dispatch_accept_incident({incident})->>'status'='in_progress';",
          actor=3)
    check('claimed dispatcher can hand off',
          f"SELECT public.corvia_ws4_ems_handoff_status({incident})->>'can_handoff'='true';",
          actor=3)
    check('legacy response assignment blocked in team route',
          f"INSERT INTO ws4_private.response_assignments(incident_id,unit_id,crew_id,purpose,acknowledgement_deadline) VALUES({incident},'{operation(810)}','{operation(811)}','primary',now()+interval '2 minutes');",
          error='Team EMS routing is active')
    check('patient cannot read team handoff',
          f'SELECT public.corvia_ws4_ems_handoff_status({incident});', actor=1,error='42501')
    session = check('team dispatcher opens own EMS session',
        f"SELECT public.corvia_ems_open('{HOSPITAL}','bridge-test');",
        actor=3, expected=None)
    uuid.UUID(session)
    prefix = ("SET SESSION AUTHORIZATION ws4_test_api; SET ROLE authenticated; "
              f"SET request.jwt.claim.sub='{uid(3)}'; ")
    op = operation(804)
    call = (f"SELECT public.corvia_ws4_handoff_to_ems({incident},'{HOSPITAL}',"
            f"'{session}','{op}','High','ALS');")
    first = json.loads(check('handoff creates linked team incident',call,
        actor=3,expected=None))
    assert first['linked'] is True and first['ems_status']=='Dispatched'
    second = json.loads(check('identical handoff retry is stable',call,
        actor=3,expected=None))
    assert first == second
    check('retry creates no duplicate EMS incident',
          f"SELECT count(*)=1 FROM ws4_private.ems_handoff_links WHERE ws4_incident_id={incident};")
    check('team row and WS4 row use explicit distinct IDs',
          f"SELECT count(*)=1 FROM ws4_private.ems_handoff_links l JOIN public.corvia_ws6_incidents_actual e ON e.incident_id=l.ems_incident_id AND e.hospital_id=l.hospital_id WHERE l.ws4_incident_id={incident};")
    check('changed operation cannot create a second case',
          f"SELECT public.corvia_ws4_handoff_to_ems({incident},'{HOSPITAL}',"
          f"'{session}','{operation(805)}','High','ALS');",actor=3,error='already linked')
    require(db.sql('UPDATE ws4_private.operations_settings SET provider_demo_enabled=true;'))
    check('linked team response blocks contradictory provider demo',
          f"SELECT public.corvia_dispatch_command({incident},'{operation(812)}',2,"
          "'simulate_provider','{\"scenario\":\"accepted\"}');",
          actor=3,error='Linked team EMS response')
    check('linked WS4 case cannot close early',
          f"SELECT public.corvia_dispatch_command({incident},'{operation(806)}',2,'close','{{\"text\":\"Synthetic completed\"}}');",
          actor=3,error='Linked EMS incident must reach')
    check('linked route cannot be deactivated',
          f"UPDATE ws4_private.ems_handoff_routes SET active=false WHERE organisation_id='{A}';",
          error='route cannot change')
    require(db.sql(f"INSERT INTO public.hospital_admins(hospital_id,profile_id) SELECT '{HOSPITAL}',id FROM public.profiles WHERE user_id='{uid(3)}';"))
    unit = team_command('team provisions vehicle', 3, session, 'unit',
        {'unit_number': 'SYNTH-EMS-1', 'vehicle_type': 'Ambulance',
         'response_capability': 'ALS', 'compliance_expiry_date': '2099-01-01'}, 830)
    member = team_command('team provisions verified synthetic medic', 3, session, 'member',
        {'employee_number': 'SYNTH-MEDIC-1', 'first_name': 'Synthetic',
         'last_name': 'Medic', 'email': 'synthetic-4@example.test',
         'qualification': 'ALS', 'clinical_category': 'ALS',
         'verification_status': 'verified', 'verification_expiry_date': '2099-01-01',
         'credential_evidence': 'Synthetic administrator review only'}, 831)
    now = datetime.now(timezone.utc)
    shift = team_command('team provisions active shift and crew', 3, session, 'shift',
        {'unit_id': unit['id'], 'member_id': member['id'],
         'start_datetime': (now - timedelta(minutes=1)).isoformat(),
         'end_datetime': (now + timedelta(hours=2)).isoformat()}, 832)
    team_command('team records vehicle readiness', 3, session, 'readiness',
        {'unit_id': unit['id'], 'vehicle_ok': True, 'equipment_ok': True,
         'oxygen_ok': True, 'fuel_ok': True, 'communications_ok': True,
         'cleaning_ok': True, 'notes': 'Synthetic inspection checks'}, 833)
    ems_id = int(first['ems_incident_id'])
    team_action('team dispatcher claims linked incident', 3, session,
        ems_id, 'claim', {}, 834)
    team_action('team assigns eligible crew', 3, session,
        ems_id, 'assign', {'crew_id': shift['crew_id']}, 835)
    require(db.sql(f"UPDATE public.corvia_ws6_incidents_actual SET acknowledgement_due_at=now()-interval '1 minute' WHERE incident_id={ems_id};"))
    check('owner worker records overdue primary once',
        'SELECT public.corvia_ws4_team_deadline_scan()=1;')
    check('worker restart does not duplicate primary alert',
        'SELECT public.corvia_ws4_team_deadline_scan()=0;')
    medic_session = check('assigned medic opens EMS session',
        f"SELECT public.corvia_ems_open('{HOSPITAL}','bridge-medic-test');",
        actor=4, expected=None)
    uuid.UUID(medic_session)
    revision=check('team revision before late primary denial',
        f'SELECT revision FROM public.corvia_ws6_incidents_actual WHERE incident_id={ems_id};',expected=None)
    check('late primary acknowledgement is rejected',
        f"SELECT public.corvia_ems_command('{HOSPITAL}','{medic_session}',"
        f"'{operation(869)}','status','{{\"incident_id\":{ems_id},\"revision\":{revision},\"status\":\"Accepted\"}}');",
        actor=4,error='Primary crew acknowledgement overdue')
    require(db.sql(f"UPDATE public.corvia_ws6_incidents_actual SET acknowledgement_due_at=now()+interval '2 minutes' WHERE incident_id={ems_id};"))
    team_action('medic acknowledges assignment', 4, medic_session,
        ems_id, 'status', {'status': 'Accepted'}, 836)
    backup_unit = team_command('team provisions backup vehicle', 3, session, 'unit',
        {'unit_number': 'SYNTH-EMS-2', 'vehicle_type': 'Ambulance',
         'response_capability': 'ALS', 'compliance_expiry_date': '2099-01-01'}, 850)
    backup_member = team_command('team provisions verified backup medic', 3, session, 'member',
        {'employee_number': 'SYNTH-MEDIC-2', 'first_name': 'Backup',
         'last_name': 'Medic', 'email': 'synthetic-5@example.test',
         'qualification': 'ALS', 'clinical_category': 'ALS',
         'verification_status': 'verified', 'verification_expiry_date': '2099-01-01',
         'credential_evidence': 'Independent synthetic credential review'}, 851)
    backup_shift = team_command('team provisions backup shift and crew', 3, session, 'shift',
        {'unit_id': backup_unit['id'], 'member_id': backup_member['id'],
         'start_datetime': (now - timedelta(minutes=1)).isoformat(),
         'end_datetime': (now + timedelta(hours=2)).isoformat()}, 852)
    team_command('team records backup vehicle readiness', 3, session, 'readiness',
        {'unit_id': backup_unit['id'], 'vehicle_ok': True, 'equipment_ok': True,
         'oxygen_ok': True, 'fuel_ok': True, 'communications_ok': True,
         'cleaning_ok': True, 'notes': 'Synthetic backup inspection'}, 853)
    patient = team_action('medic records synthetic patient', 4, medic_session,
        ems_id, 'patient', {'first_name': 'Synthetic', 'last_name': 'Patient'}, 837)
    for number, state in enumerate(['En Route', 'On Scene'], 838):
        team_action('medic progresses ' + state, 4, medic_session,
            ems_id, 'status', {'status': state}, number)
    team_action('primary crew requests backup', 4, medic_session, ems_id,
        'exception', {'kind': 'backup_required', 'reason': 'Additional crew required on scene'}, 854)
    revision = check('team revision before backup offer',
        f'SELECT revision FROM public.corvia_ws6_incidents_actual WHERE incident_id={ems_id};', expected=None)
    backup = json.loads(check('dispatcher reserves independent backup crew',
        f"SELECT public.corvia_ws4_backup_dispatch({incident},'{operation(855)}',"
        f"{revision},'offer',{backup_shift['crew_id']},'Additional crew requested on scene');",
        actor=3, expected=None))
    check('primary and backup remain concurrently assigned',
        f"SELECT (SELECT count(*) FROM public.corvia_ws6_incident_assignments_actual WHERE incident_id={ems_id} AND is_active)=1 AND (SELECT count(*) FROM ws4_private.ems_backups WHERE ems_incident_id={ems_id} AND state='offered')=1;")
    check('team cannot free a reserved backup unit',
        f"UPDATE public.corvia_ws6_units_actual SET status='Available' WHERE unit_id={backup_unit['id']};",
        error='Release the active backup')
    check('backup cannot be offered twice',
        f"SELECT public.corvia_ws4_backup_dispatch({incident},'{operation(856)}',"
        f"{int(revision)+1},'offer',{backup_shift['crew_id']},'Another backup attempt');",
        actor=3, error='not currently eligible')
    backup_status = json.loads(check('assigned backup sees own incident',
        'SELECT public.corvia_ws4_backup_overview();', actor=5, expected=None))
    assert backup_status['items'][0]['backup_id'] == backup['backup_id']
    require(db.sql(f"INSERT INTO public.corvia_ops_memberships(hospital_id,user_id,role,granted_by) VALUES('{HOSPITAL}','{uid(5)}','dispatcher','{uid(3)}');"))
    check('backup remains backup even with separate team controller role',
        f"SELECT public.corvia_ws4_team_snapshot({incident})->>'role'='backup';",
        actor=5)
    revision=check('team revision before backup command denial',
        f'SELECT revision FROM public.corvia_ws6_incidents_actual WHERE incident_id={ems_id};',expected=None)
    check('backup cannot issue primary linked command through controller role',
        f"SELECT public.corvia_ws4_team_completion_command({incident},'{operation(890)}',"
        f"{revision},'exception','{{\"kind\":\"multiple_patients\",\"reason\":\"Backup cannot act as primary\"}}');",
        actor=5,error='42501')
    check('unrelated account cannot answer backup',
        f"SELECT public.corvia_ws4_backup_crew({backup['backup_id']},'{operation(857)}',1,'acknowledge');",
        actor=7,error='42501')
    require(db.sql(f"UPDATE ws4_private.ems_backups SET acknowledgement_due_at=now()-interval '1 minute' WHERE id={backup['backup_id']};"))
    check('owner worker records overdue backup once',
        'SELECT public.corvia_ws4_team_deadline_scan()=1;')
    check('worker restart does not duplicate backup alert',
        'SELECT public.corvia_ws4_team_deadline_scan()=0;')
    check('backup acknowledgement after deadline is denied',
        f"SELECT public.corvia_ws4_backup_crew({backup['backup_id']},'{operation(870)}',1,'acknowledge');",
        actor=5,error='Backup offer overdue')
    require(db.sql(f"UPDATE ws4_private.ems_backups SET acknowledgement_due_at=now()+interval '2 minutes' WHERE id={backup['backup_id']};"))
    ack = (f"SELECT public.corvia_ws4_backup_crew({backup['backup_id']},"
           f"'{operation(858)}',1,'acknowledge');")
    check('backup medic acknowledges own offer', ack,actor=5,expected=None)
    check('backup acknowledgement retry is stable',ack,actor=5,expected=None)
    check('backup medic records en route',
        f"SELECT public.corvia_ws4_backup_crew({backup['backup_id']},'{operation(862)}',2,'en_route')->>'state'='en_route';",
        actor=5)
    check('backup medic records on scene',
        f"SELECT public.corvia_ws4_backup_crew({backup['backup_id']},'{operation(863)}',3,'on_scene')->>'state'='on_scene';",
        actor=5)
    backup_message=(f"SELECT public.corvia_ws4_backup_message({backup['backup_id']},"
        f"'{operation(864)}','Backup on scene, requesting scene update');")
    check('backup medic sends audited dispatch message',backup_message,actor=5,expected=None)
    check('backup message retry is stable',backup_message,actor=5,expected=None)
    conversation=json.loads(check('dispatcher sees scoped backup message',
        f"SELECT public.corvia_ws4_backup_conversation({backup['backup_id']});",
        actor=3,expected=None))
    assert conversation['messages'][0]['body']=='Backup on scene, requesting scene update'
    check('unrelated patient cannot read backup conversation',
        f"SELECT public.corvia_ws4_backup_conversation({backup['backup_id']});",
        actor=1,error='42501')
    check('dispatcher records backup read receipt',
        f"SELECT public.corvia_ws4_backup_mark_read({conversation['messages'][0]['id']},"
        f"'{operation(865)}')->>'read'='true';",actor=3)
    check('primary team cannot close with active backup',
        f"UPDATE public.corvia_ws6_incidents_actual SET status='Closed' WHERE incident_id={ems_id};",
        error='Resolve linked safety exceptions')
    revision = check('team revision before backup release',
        f'SELECT revision FROM public.corvia_ws6_incidents_actual WHERE incident_id={ems_id};', expected=None)
    check('dispatcher releases backup with reason',
        f"SELECT public.corvia_ws4_backup_dispatch({incident},'{operation(859)}',"
        f"{revision},'release',NULL,'Backup assistance no longer required');",
        actor=3,expected=None)
    check('released backup vehicle needs a new readiness review',
        f"SELECT public.corvia_ops_eligibility('{HOSPITAL}',{backup_unit['id']},'ALS')='A current readiness inspection is required';")
    check('unresolved backup request blocks transport',
        f"UPDATE public.corvia_ws6_incidents_actual SET status='Transporting' WHERE incident_id={ems_id};",
        error='Resolve linked safety exceptions')
    exception_id=check('recorded backup exception ID',
        f"SELECT id FROM ws4_private.ems_team_exceptions WHERE ems_incident_id={ems_id} AND kind='backup_required' AND active;",
        expected=None)
    revision=check('team revision before independent exception review',
        f'SELECT revision FROM public.corvia_ws6_incidents_actual WHERE incident_id={ems_id};',expected=None)
    check('independent supervisor resolves backup request',
        f"SELECT public.corvia_ws4_team_completion_command({incident},'{operation(866)}',"
        f"{revision},'resolve_exception','{{\"exception_id\":\"{exception_id}\",\"reason\":\"Backup assistance safely stood down\"}}');",
        actor=3,expected=None)
    check('transport rejects unconfirmed patient',
        f"UPDATE public.corvia_ws6_incidents_actual SET status='Transporting' WHERE incident_id={ems_id};",
        error='Confirm every assigned patient')
    patient_number=check('synthetic patient match identifier',
        f"SELECT patient_number FROM public.corvia_ws6_patients_actual WHERE patient_id={patient['id']};",
        expected=None)
    team_action('medic confirms assigned patient match',4,medic_session,ems_id,
        'qr',{'patient_id':patient['id'],'code':patient_number},867)
    check('transport rejects missing destination',
        f"UPDATE public.corvia_ws6_incidents_actual SET status='Transporting' WHERE incident_id={ems_id};",
        error='Select an active receiving destination')
    facility = team_command('team provisions receiving facility', 3, session,
        'facility', {'facility_code': 'SYNTH-ED-1',
                     'facility_name': 'Synthetic receiving ED'}, 842)
    revision=check('team revision before destination selection',
        f'SELECT revision FROM public.corvia_ws6_incidents_actual WHERE incident_id={ems_id};',expected=None)
    check('dispatcher selects real team receiving facility',
        f"SELECT public.corvia_ws4_team_completion_command({incident},'{operation(868)}',"
        f"{revision},'destination','{{\"facility_id\":\"{facility['id']}\",\"reason\":\"Synthetic receiving ED selected\"}}');",
        actor=3,expected=None)
    for number, state in enumerate(['Transporting', 'At Hospital'], 840):
        team_action('medic progresses ' + state, 4, medic_session,
            ems_id, 'status', {'status': state}, number)
    failed_handover=team_action('medic records unconfirmed first handover',4,
        medic_session,ems_id,'handover',{'patient_id':patient['id'],
        'facility_id':facility['id'],'receiver_name':'Synthetic First Receiver',
        'receiver_role':'Nurse','handover_summary':'First facility could not receive'},871)
    revision=check('team revision before failed handover exception',
        f'SELECT revision FROM public.corvia_ws6_incidents_actual WHERE incident_id={ems_id};',expected=None)
    check('primary medic records failed receiving attempt',
        f"SELECT public.corvia_ws4_team_completion_command({incident},'{operation(872)}',"
        f"{revision},'exception','{{\"kind\":\"handover_failed\",\"reason\":\"First receiving facility unable to accept patient\"}}');",
        actor=4,expected=None)
    alternate=team_command('team provisions alternate receiving facility',3,session,
        'facility',{'facility_code':'SYNTH-ED-2',
                    'facility_name':'Synthetic alternate ED'},873)
    revision=check('team revision before alternate destination',
        f'SELECT revision FROM public.corvia_ws6_incidents_actual WHERE incident_id={ems_id};',expected=None)
    check('dispatcher reroutes after failed handover',
        f"SELECT public.corvia_ws4_team_completion_command({incident},'{operation(874)}',"
        f"{revision},'destination','{{\"facility_id\":\"{alternate['id']}\",\"reason\":\"Alternate ED confirmed for synthetic patient\"}}');",
        actor=3,expected=None)
    require(db.sql(f"INSERT INTO ws4_private.ems_receivers(hospital_id,facility_id,user_id,active,granted_by) VALUES('{HOSPITAL}',{facility['id']},'{uid(7)}',true,'{uid(3)}');"))
    check('first receiving user cannot confirm failed handover',
        f"SELECT public.corvia_ws4_receiver_ack({failed_handover['id']},'{operation(876)}','Attempt failed at first facility');",
        actor=7,error='Receiving confirmation must match')
    failure_id=check('failed handover exception ID',
        f"SELECT id FROM ws4_private.ems_team_exceptions WHERE ems_incident_id={ems_id} AND kind='handover_failed' AND active;",
        expected=None)
    revision=check('team revision before failed handover resolution',
        f'SELECT revision FROM public.corvia_ws6_incidents_actual WHERE incident_id={ems_id};',expected=None)
    check('independent supervisor resolves failed handover after reroute',
        f"SELECT public.corvia_ws4_team_completion_command({incident},'{operation(875)}',"
        f"{revision},'resolve_exception','{{\"exception_id\":\"{failure_id}\",\"reason\":\"Alternate ED selected and pending first attempt marked failed\"}}');",
        actor=3,expected=None)
    facility=alternate
    handover = team_action('medic records receiving handover', 4, medic_session,
        ems_id, 'handover', {'patient_id': patient['id'],
        'facility_id': facility['id'], 'receiver_name': 'Synthetic Receiver',
        'receiver_role': 'Nurse', 'handover_summary': 'Synthetic handover completed'}, 843)
    require(db.sql(f"INSERT INTO ws4_private.ems_receivers(hospital_id,facility_id,user_id,active,granted_by) VALUES('{HOSPITAL}',{facility['id']},'{uid(7)}',true,'{uid(3)}');"))
    revision = check('team revision before rejected medic acknowledgement',
        f'SELECT revision FROM public.corvia_ws6_incidents_actual WHERE incident_id={ems_id};', expected=None)
    check('medic cannot self-confirm receiving handover',
        f"SELECT public.corvia_ems_command('{HOSPITAL}','{medic_session}',"
        f"'{operation(844)}','handover_acknowledge','{{\"incident_id\":{ems_id},\"revision\":{revision},\"patient_id\":{patient['id']},\"id\":{handover['id']},\"reason\":\"Medic self confirmation\"}}');",
        actor=4,error='42501')
    check('unrelated account cannot confirm receiving handover',
        f"SELECT public.corvia_ws4_receiver_ack({handover['id']},'{operation(860)}','Received patient safely');",
        actor=1,error='42501')
    inbox = json.loads(check('receiver sees scoped handover inbox',
        'SELECT public.corvia_ws4_receiver_inbox();',actor=7,expected=None))
    assert inbox['items'][0]['handover_id'] == str(handover['id'])
    receipt = (f"SELECT public.corvia_ws4_receiver_ack({handover['id']},"
               f"'{operation(861)}','Received patient at synthetic facility');")
    check('separate receiving account confirms handover',receipt,actor=7,expected=None)
    check('receiving confirmation retry is stable',receipt,actor=7,expected=None)
    require(db.sql(f"UPDATE ws4_private.ems_receivers SET active=false WHERE hospital_id='{HOSPITAL}' AND facility_id={facility['id']} AND user_id='{uid(7)}';"))
    check('revoked receiving user cannot replay confirmation',
        receipt,actor=7,error='42501')
    team_action('team records handed over', 4, medic_session,
        ems_id, 'status', {'status': 'Handed Over'}, 845)
    team_action('team closes linked EMS incident', 4, medic_session,
        ems_id, 'status', {'status': 'Closed'}, 846)
    callback=(f"SELECT public.corvia_ws4_callback_outcome({incident},'{operation(877)}',"
        "2,'callback_outcome','{\"outcome\":\"no_answer\",\"text\":\"no_answer: synthetic callback reached no one\"}');")
    check('dispatcher records observed callback outcome',callback,actor=3,expected=None)
    check('callback lost-response retry is stable',callback,actor=3,expected=None)
    check('patient cannot record dispatcher callback result',
        f"SELECT public.corvia_ws4_callback_outcome({incident},'{operation(878)}',3,"
        "'callback_outcome','{\"outcome\":\"connected\",\"text\":\"connected: patient answered\"}');",
        actor=1,error='42501')
    check('WS4 may close after team confirms closed',
          f"SELECT public.corvia_ws4_close_incident({incident},'{operation(807)}',3,'close','{{\"text\":\"Synthetic completed\"}}')->>'version'='4';",
          actor=3)
    cancelled = json.loads(check('second patient request for cancellation path',
        f'SELECT {request(820)};', actor=2, expected=None))['incident_id']
    check('dispatcher claims second case',
          f"SELECT public.corvia_dispatch_accept_incident({cancelled})->>'status'='in_progress';",
          actor=3)
    cancelled_handoff = json.loads(check('second case links to team EMS',
        f"SELECT public.corvia_ws4_handoff_to_ems({cancelled},'{HOSPITAL}',"
        f"'{session}','a0000000-0000-4000-8000-000000000821','High','ALS');",
        actor=3, expected=None))
    require(db.sql(f"UPDATE public.corvia_ops_memberships SET role='supervisor' WHERE hospital_id='{HOSPITAL}' AND user_id='{uid(3)}';"))
    revision = check('team revision before supervisor cancellation',
        f"SELECT revision FROM public.corvia_ws6_incidents_actual WHERE incident_id={cancelled_handoff['ems_incident_id']};",
        expected=None)
    check('team supervisor cancels through command',
          f"SELECT public.corvia_ems_command('{HOSPITAL}','{session}',"
          f"'{operation(822)}','exception','{{\"incident_id\":\"{cancelled_handoff['ems_incident_id']}\",\"revision\":{revision},\"kind\":\"cancelled\",\"reason\":\"Synthetic patient request withdrawn\"}}')->>'exception'='cancelled';",
          actor=3)
    close_cancelled = (f"SELECT public.corvia_ws4_close_incident({cancelled},"
                       f"'{operation(823)}',2,'close','{{\"text\":\"Team confirmed cancellation\"}}');")
    first_close = json.loads(check('WS4 closure records matching cancellation',
        close_cancelled, actor=3, expected=None))
    same_close = json.loads(check('same closure retry returns its durable receipt',
        close_cancelled, actor=3, expected=None))
    assert same_close == first_close
    check('patient sees cancelled rather than resolved',
          f"SELECT status='cancelled' FROM public.incidents WHERE id={cancelled};")
    require(db.sql(f"INSERT INTO ws4_private.memberships VALUES('{uid(7)}','{A}','dispatch_supervisor',true);"))
    require(db.sql(f"INSERT INTO public.corvia_ops_memberships(hospital_id,user_id,role,granted_by) VALUES('{HOSPITAL}','{uid(7)}','supervisor','{uid(3)}');"))
    third=json.loads(check('third patient request for safety exception path',
        f'SELECT {request(879)};',actor=2,expected=None))['incident_id']
    check('dispatcher claims third patient request',
        f"SELECT public.corvia_dispatch_accept_incident({third})->>'status'='in_progress';",
        actor=3)
    third_handoff=json.loads(check('third request links to team EMS',
        f"SELECT public.corvia_ws4_handoff_to_ems({third},'{HOSPITAL}',"
        f"'{session}','b0000000-0000-4000-8000-000000000880','High','ALS');",
        actor=3,expected=None))
    third_ems=third_handoff['ems_incident_id']
    revision=check('team revision before no-resource exception',
        f'SELECT revision FROM public.corvia_ws6_incidents_actual WHERE incident_id={third_ems};',
        expected=None)
    no_resource=json.loads(check('dispatcher records no eligible resource',
        f"SELECT public.corvia_ws4_team_completion_command({third},'{operation(881)}',"
        f"{revision},'exception','{{\"kind\":\"no_resource\",\"reason\":\"No ready crew available at this time\"}}');",
        actor=3,expected=None))
    revision=check('team revision before invalid no-resource resolution',
        f'SELECT revision FROM public.corvia_ws6_incidents_actual WHERE incident_id={third_ems};',
        expected=None)
    check('supervisor cannot falsely resolve missing resource',
        f"SELECT public.corvia_ws4_team_completion_command({third},'{operation(882)}',"
        f"{revision},'resolve_exception','{{\"exception_id\":\"{no_resource['exception_id']}\",\"reason\":\"Resource now available for dispatch\"}}');",
        actor=7,error='Assign an eligible crew')
    team_action('team dispatcher claims third EMS case',3,session,int(third_ems),
        'claim',{},883)
    team_command('team renews primary vehicle readiness',3,session,'readiness',
        {'unit_id':unit['id'],'vehicle_ok':True,'equipment_ok':True,
         'oxygen_ok':True,'fuel_ok':True,'communications_ok':True,
         'cleaning_ok':True,'notes':'Synthetic inspection after prior case'},884)
    team_action('team assigns eligible primary crew to third case',3,session,
        int(third_ems),'assign',{'crew_id':shift['crew_id']},885)
    revision=check('team revision before no-resource resolution',
        f'SELECT revision FROM public.corvia_ws6_incidents_actual WHERE incident_id={third_ems};',
        expected=None)
    check('independent supervisor resolves no-resource after assignment',
        f"SELECT public.corvia_ws4_team_completion_command({third},'{operation(886)}',"
        f"{revision},'resolve_exception','{{\"exception_id\":\"{no_resource['exception_id']}\",\"reason\":\"Verified primary crew and vehicle now assigned\"}}');",
        actor=7,expected=None)
    team_action('medic reports no patient found for third case',4,medic_session,
        int(third_ems),'exception',{'kind':'no_patient',
        'reason':'No patient at scene after search'},887)
    no_patient=check('recorded no-patient exception ID',
        f"SELECT id FROM ws4_private.ems_team_exceptions WHERE ems_incident_id={third_ems} AND kind='no_patient' AND active;",
        expected=None)
    revision=check('team revision before independent no-patient outcome',
        f'SELECT revision FROM public.corvia_ws6_incidents_actual WHERE incident_id={third_ems};',
        expected=None)
    check('same reporting medic cannot close third case',
        f"SELECT public.corvia_ws4_team_completion_command({third},'{operation(888)}',"
        f"{revision},'terminal_exception','{{\"exception_id\":\"{no_patient}\",\"reason\":\"Patient absent and dispatch confirmed no transport\"}}');",
        actor=4,error='Supervisor review required')
    check('independent supervisor closes no-patient case without invented handover',
        f"SELECT public.corvia_ws4_team_completion_command({third},'{operation(889)}',"
        f"{revision},'terminal_exception','{{\"exception_id\":\"{no_patient}\",\"reason\":\"Patient absent and dispatch confirmed no transport\"}}')->>'status'='Closed';",
        actor=7)
    check('third patient sees cancelled safety outcome',
        f"SELECT public.corvia_ws4_close_incident({third},'{operation(890)}',2,'close',"
        "'{\"text\":\"No patient found after independent supervisor review\"}')->>'version'='3';",
        actor=3)
    check('released primary needs independent readiness review',
        f"SELECT public.corvia_ops_eligibility('{HOSPITAL}',{unit['id']},'ALS')='A current readiness inspection is required';")


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pg-bin',type=Path,required=True)
    args=parser.parse_args()
    work=REPO/'build/ws4-ems-bridge-rehearsal'/uuid.uuid4().hex
    work.mkdir(parents=True)
    db=Database(args.pg_bin.resolve(),work)
    report={'results':[]}
    try:
        db.start(); run(db,report['results']); report['passed']=True
    except Exception as error:
        report.update(passed=False,error=str(error)); raise
    finally:
        db.stop(); report['server_stopped']=not db.started
        (work/'result.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
        print('Report: '+str(work/'result.json'),flush=True)


if __name__=='__main__': main()
