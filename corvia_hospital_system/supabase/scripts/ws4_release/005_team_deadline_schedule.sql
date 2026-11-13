-- Optional owner-run schedule on a backend with pg_cron already installed.
-- Inspect the exact target, 005 migration and existing cron jobs before use.
DO $$ BEGIN
  IF current_user<>'postgres' OR to_regprocedure(
    'public.corvia_ws4_team_deadline_scan()') IS NULL OR
    NOT EXISTS(SELECT 1 FROM pg_extension WHERE extname='pg_cron') THEN
    RAISE EXCEPTION 'Owner-reviewed WS4 005 and existing pg_cron are required';
  END IF;
END $$;
SELECT cron.schedule('corvia-ws4-team-ack-attention','* * * * *',
  'SELECT public.corvia_ws4_team_deadline_scan();');
