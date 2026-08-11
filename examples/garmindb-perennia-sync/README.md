# GarminDB to Perennia Sync

Example user-run automation for importing Garmin FIT files and GarminDB daily
wellness metrics into Perennia without putting Garmin credentials in the Perennia app or
hosted service.

## Setup

1. Configure GarminDB with your Garmin account on your own machine.
2. In Perennia Settings, create an import credential and enable Garmin `Activities`,
   `Heart rate`, and `Sleep/wellness` consent. `Activities` covers activity FIT
   files plus daily steps/calories; `Heart rate` covers resting/average/max HR
   and HRV; `Sleep/wellness` covers sleep duration, sleep score, stress, and
   related daily summaries. Enable `GPS` only if you want FIT location streams.
3. Copy `.env.example` to `.env` and fill in `PRN_BASE_URL`,
   `PRN_INTEGRATION_TOKEN`, `PRN_TIMEZONE`, and `GARMINDB_DATA_DIR`.
4. Install and run:

```bash
python -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
python sync.py
```

Use `python sync.py --skip-garmindb-run` when GarminDB is already scheduled by
cron, Task Scheduler, or launchd and this script should only upload local data
that is already present. Use `--metrics-only` for sleep, heart rate, steps, and
calories without FIT activity uploads, or `--activities-only` for FIT files
without wellness metrics.

## Behavior

- Calls `GET /integrations/import-profile` first and exits before running
  GarminDB unless the requested Perennia data classes are enabled.
- Runs `garmindb_cli.py --all --download --import --analyze --latest` by default.
- Discovers activity `.fit` files under `GARMINDB_DATA_DIR/FitFiles/Activities`
  and uploads each new file to `POST /integrations/garmin/fit-import`.
- Reads GarminDB SQLite summaries from `DBs/garmin.db` and
  `DBs/garmin_summary.db`, maps provider fields to Perennia Metrics, and uploads
  batches to `POST /integrations/canonical-import`.
- Stores local content hashes in `PRN_STATE_PATH` so retries are idempotent.
- Reports only sanitized status metadata to `/integrations/status`.

Garmin credentials stay in GarminDB's own local config. The only Perennia secret this
example needs is the revocable import token.
