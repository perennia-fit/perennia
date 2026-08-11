from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import shlex
import sqlite3
import subprocess
import sys
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta, timezone
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo

import requests
from dotenv import load_dotenv


DEFAULT_TIMEOUT_SECONDS = 60
DEFAULT_METRIC_BATCH_SIZE = 500


@dataclass(frozen=True)
class Config:
    base_url: str
    token: str
    timezone: str
    garmindb_config_path: Path | None
    garmindb_data_dir: Path
    state_path: Path
    dry_run: bool
    skip_garmindb_run: bool
    sync_activities: bool
    sync_metrics: bool
    metric_batch_size: int


def main() -> int:
    load_dotenv()
    args = parse_args()
    config = load_config(args)

    session = requests.Session()
    session.headers.update(
        {
            "authorization": f"Bearer {config.token}",
            "accept": "application/json",
        }
    )

    profile = get_import_profile(session, config)
    enabled = set(profile.get("enabledDataClasses", []))
    missing = required_enabled_data_classes(config) - enabled
    if config.sync_activities and (
        not profile.get("fitImportEnabled") or "activities" not in enabled
    ):
        print(
            "Garmin FIT activities are not enabled in Perennia. Enable Garmin "
            "Activities consent in the app before running this sync."
        )
        report_status(session, config, "temporary_failure", "manual", "unknown")
        return 2
    if missing:
        print(
            "GarminDB metric sync needs these Perennia consent classes enabled: "
            f"{', '.join(sorted(missing))}."
        )
        report_status(session, config, "temporary_failure", "manual", "unknown")
        return 2

    if not config.skip_garmindb_run:
        run_garmindb(config)

    state = load_state(config.state_path)
    uploaded = 0
    skipped = 0
    metric_readings = 0
    metric_batches = 0

    if config.sync_activities:
        fit_files = discover_activity_fit_files(config.garmindb_data_dir)
        for fit_file in fit_files:
            digest = sha256_file(fit_file)
            if digest in state["uploaded"]:
                skipped += 1
                continue

            idempotency_key = f"garmindb-fit:{digest}"
            if config.dry_run:
                print(f"DRY RUN would upload activity FIT {fit_file}")
                skipped += 1
                continue

            upload_fit_file(session, config, fit_file, idempotency_key)
            state["uploaded"][digest] = {
                "path": str(fit_file),
                "idempotencyKey": idempotency_key,
                "uploadedAt": datetime.now(timezone.utc).isoformat(),
            }
            save_state(config.state_path, state)
            uploaded += 1

    if config.sync_metrics:
        readings = collect_garmindb_metric_readings(config)
        metric_readings = len(readings)
        for batch in chunked(readings, config.metric_batch_size):
            digest = sha256_json(batch)
            if digest in state["metricBatches"]:
                skipped += len(batch)
                continue

            idempotency_key = f"garmindb-metrics:{digest}"
            if config.dry_run:
                print(f"DRY RUN would upload {len(batch)} metric readings")
                skipped += len(batch)
                continue

            upload_metric_batch(session, config, batch, idempotency_key)
            state["metricBatches"][digest] = {
                "readings": len(batch),
                "idempotencyKey": idempotency_key,
                "uploadedAt": datetime.now(timezone.utc).isoformat(),
            }
            save_state(config.state_path, state)
            metric_batches += 1

    report_status(session, config, "ok", "manual", None)
    print(
        "GarminDB Perennia sync complete: "
        f"activityFilesUploaded={uploaded}, "
        f"metricReadingsDiscovered={metric_readings}, "
        f"metricBatchesUploaded={metric_batches}, "
        f"skipped={skipped}"
    )
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Upload GarminDB FIT files to Perennia."
    )
    parser.add_argument(
        "--skip-garmindb-run",
        action="store_true",
        help="Only discover and upload existing FIT files.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Run preflight and discovery without uploading FIT files.",
    )
    parser.add_argument(
        "--metrics-only",
        action="store_true",
        help="Import GarminDB wellness metrics without uploading activity FIT files.",
    )
    parser.add_argument(
        "--activities-only",
        action="store_true",
        help="Upload activity FIT files without importing GarminDB wellness metrics.",
    )
    return parser.parse_args()


def load_config(args: argparse.Namespace) -> Config:
    base_url = required_env("PRN_BASE_URL").rstrip("/")
    token = required_env("PRN_INTEGRATION_TOKEN")
    data_dir = expand_path(required_env("GARMINDB_DATA_DIR"))
    config_path = optional_path(os.getenv("GARMINDB_CONFIG_PATH"))

    return Config(
        base_url=base_url,
        token=token,
        timezone=os.getenv("PRN_TIMEZONE", "UTC"),
        garmindb_config_path=config_path,
        garmindb_data_dir=data_dir,
        state_path=expand_path(
            os.getenv("PRN_STATE_PATH", ".garmindb-perennia-sync-state.json")
        ),
        dry_run=args.dry_run or env_bool("PRN_DRY_RUN"),
        skip_garmindb_run=args.skip_garmindb_run
        or env_bool("PRN_SKIP_GARMINDB_RUN"),
        sync_activities=not args.metrics_only and env_bool_default(
            "PRN_SYNC_ACTIVITIES", True
        ),
        sync_metrics=not args.activities_only and env_bool_default(
            "PRN_SYNC_METRICS", True
        ),
        metric_batch_size=max(
            1,
            min(
                int(os.getenv("PRN_METRIC_BATCH_SIZE", DEFAULT_METRIC_BATCH_SIZE)),
                2000,
            ),
        ),
    )


def required_enabled_data_classes(config: Config) -> set[str]:
    required: set[str] = set()
    if config.sync_activities:
        required.add("activities")
    if config.sync_metrics:
        required.update({"activities", "heartRate", "sleepWellness"})
    return required


def get_import_profile(session: requests.Session, config: Config) -> dict[str, Any]:
    response = session.get(
        f"{config.base_url}/integrations/import-profile",
        timeout=DEFAULT_TIMEOUT_SECONDS,
    )
    if response.status_code != 200:
        raise RuntimeError(
            "Import profile preflight failed "
            f"with HTTP {response.status_code}: {response.text}"
        )
    payload = response.json()
    if not isinstance(payload, dict):
        raise RuntimeError("Import profile response was not a JSON object.")
    return payload


def run_garmindb(config: Config) -> None:
    command = shlex.split(os.getenv("GARMINDB_COMMAND", "garmindb_cli.py"))
    command.extend(["--all", "--download", "--import", "--analyze", "--latest"])
    env = os.environ.copy()
    if config.garmindb_config_path is not None:
        env.setdefault("GARMINDB_CONFIG_PATH", str(config.garmindb_config_path))

    print("Running GarminDB download/import/analyze...")
    subprocess.run(command, check=True, env=env)


def discover_activity_fit_files(data_dir: Path) -> list[Path]:
    if not data_dir.exists():
        raise RuntimeError(f"GARMINDB_DATA_DIR does not exist: {data_dir}")
    activities_dir = data_dir / "FitFiles" / "Activities"
    if activities_dir.exists():
        return sorted(
            path
            for path in activities_dir.rglob("*")
            if path.is_file() and path.suffix.lower() == ".fit"
        )
    return sorted(
        path
        for path in data_dir.rglob("*")
        if path.is_file()
        and path.suffix.lower() == ".fit"
        and "ACTIVITY" in path.name.upper()
    )


def upload_fit_file(
    session: requests.Session,
    config: Config,
    fit_file: Path,
    idempotency_key: str,
) -> None:
    with fit_file.open("rb") as handle:
        file_base64 = base64.b64encode(handle.read()).decode("ascii")
    response = session.post(
        f"{config.base_url}/integrations/garmin/fit-import",
        json={
            "fileBase64": file_base64,
            "filename": fit_file.name,
            "timezone": config.timezone,
            "idempotencyKey": idempotency_key,
        },
        timeout=DEFAULT_TIMEOUT_SECONDS,
    )

    if response.status_code != 200:
        report_status(session, config, "temporary_failure", "manual", "server")
        raise RuntimeError(
            f"FIT upload failed for {fit_file} with HTTP "
            f"{response.status_code}: {response.text}"
        )

    body = response.json()
    print(
        "Uploaded "
        f"{fit_file.name}: duplicate={body.get('duplicate')} "
        f"activities={len(body.get('activities', []))} "
        f"seriesAccepted={body.get('seriesAccepted')}"
    )


def upload_metric_batch(
    session: requests.Session,
    config: Config,
    readings: list[dict[str, Any]],
    idempotency_key: str,
) -> None:
    response = session.post(
        f"{config.base_url}/integrations/canonical-import",
        json={
            "idempotencyKey": idempotency_key,
            "activities": [],
            "metricReadings": readings,
            "series": [],
            "consentedDataClasses": [],
        },
        timeout=DEFAULT_TIMEOUT_SECONDS,
    )

    if response.status_code != 200:
        report_status(session, config, "temporary_failure", "manual", "server")
        raise RuntimeError(
            "Metric batch upload failed with HTTP "
            f"{response.status_code}: {response.text}"
        )

    body = response.json()
    print(
        "Uploaded metric batch: "
        f"duplicate={body.get('duplicate')} "
        f"metricReadings={len(body.get('metricReadings', []))} "
        f"reviewFlags={len(body.get('reviewFlags', []))}"
    )


def collect_garmindb_metric_readings(config: Config) -> list[dict[str, Any]]:
    db_path = config.garmindb_data_dir / "DBs" / "garmin.db"
    summary_db_path = config.garmindb_data_dir / "DBs" / "garmin_summary.db"
    readings: list[dict[str, Any]] = []

    if db_path.exists():
        with sqlite3.connect(db_path) as connection:
            connection.row_factory = sqlite3.Row
            readings.extend(read_daily_summary_metrics(connection, config))
            readings.extend(read_resting_heart_rate_metrics(connection, config))
            readings.extend(read_sleep_metrics(connection, config))
            readings.extend(read_hrv_metrics(connection, config))

    if summary_db_path.exists():
        with sqlite3.connect(summary_db_path) as connection:
            connection.row_factory = sqlite3.Row
            readings.extend(read_summary_heart_rate_metrics(connection, config))

    return sorted(
        dedupe_readings(readings),
        key=lambda reading: (
            reading["externalId"],
            reading["metricKey"],
        ),
    )


def read_daily_summary_metrics(
    connection: sqlite3.Connection,
    config: Config,
) -> list[dict[str, Any]]:
    if not table_exists(connection, "daily_summary"):
        return []
    readings: list[dict[str, Any]] = []
    columns = table_columns(connection, "daily_summary")
    wanted = [
        ("steps", "steps", "count"),
        ("calories_active", "activeKilocalories", "kilocalorie"),
        ("calories_total", "totalKilocalories", "kilocalorie"),
        ("calories_bmr", "basalKilocalories", "kilocalorie"),
        ("stress_avg", "stressAverage", "score"),
        ("bb_min", "bodyBatteryMinimum", "score"),
        ("bb_max", "bodyBatteryMaximum", "score"),
    ]
    if not table_exists(connection, "resting_hr"):
        wanted.insert(0, ("rhr", "restingHeartRate", "beatsPerMinute"))
    selected = [item for item in wanted if item[0] in columns]
    if not selected:
        return []

    select_columns = ", ".join(["day", *(item[0] for item in selected)])
    for row in connection.execute(f"select {select_columns} from daily_summary"):
        day = parse_day(row["day"])
        if day is None:
            continue
        anchor = day_window_anchor(day, config.timezone)
        for column, metric_key, unit in selected:
            readings.extend(
                metric_reading_from_value(
                    source_suffix=f"daily:{day.isoformat()}:{column}",
                    metric_key=metric_key,
                    value=row[column],
                    unit=unit,
                    anchor=anchor,
                )
            )
    return readings


def read_resting_heart_rate_metrics(
    connection: sqlite3.Connection,
    config: Config,
) -> list[dict[str, Any]]:
    if not table_exists(connection, "resting_hr"):
        return []
    readings: list[dict[str, Any]] = []
    for row in connection.execute("select day, resting_heart_rate from resting_hr"):
        day = parse_day(row["day"])
        if day is None:
            continue
        readings.extend(
            metric_reading_from_value(
                source_suffix=f"resting_hr:{day.isoformat()}",
                metric_key="restingHeartRate",
                value=row["resting_heart_rate"],
                unit="beatsPerMinute",
                anchor=day_window_anchor(day, config.timezone),
            )
        )
    return readings


def read_sleep_metrics(
    connection: sqlite3.Connection,
    config: Config,
) -> list[dict[str, Any]]:
    if not table_exists(connection, "sleep"):
        return []
    readings: list[dict[str, Any]] = []
    columns = table_columns(connection, "sleep")
    wanted = [
        ("total_sleep", "sleepDuration", "second"),
        ("deep_sleep", "deepSleepDuration", "second"),
        ("light_sleep", "lightSleepDuration", "second"),
        ("rem_sleep", "remSleepDuration", "second"),
        ("awake", "awakeDuration", "second"),
        ("score", "sleepScore", "score"),
        ("avg_stress", "stressAverage", "score"),
    ]
    selected = [item for item in wanted if item[0] in columns]
    select_columns = ", ".join(
        ["day", "start", "end", *(item[0] for item in selected)]
    )
    for row in connection.execute(f"select {select_columns} from sleep"):
        day = parse_day(row["day"])
        if day is None:
            continue
        anchor = sleep_anchor(row["start"], row["end"], config, day)
        for column, metric_key, unit in selected:
            readings.extend(
                metric_reading_from_value(
                    source_suffix=f"sleep:{day.isoformat()}:{column}",
                    metric_key=metric_key,
                    value=row[column],
                    unit=unit,
                    anchor=anchor,
                )
            )
    return readings


def read_hrv_metrics(
    connection: sqlite3.Connection,
    config: Config,
) -> list[dict[str, Any]]:
    if not table_exists(connection, "hrv"):
        return []
    readings: list[dict[str, Any]] = []
    columns = table_columns(connection, "hrv")
    value_column = (
        "last_night_avg"
        if "last_night_avg" in columns
        else "last_night_average"
        if "last_night_average" in columns
        else None
    )
    if value_column is None:
        return []
    for row in connection.execute(f"select day, {value_column} from hrv"):
        day = parse_day(row["day"])
        if day is None:
            continue
        readings.extend(
            metric_reading_from_value(
                source_suffix=f"hrv:{day.isoformat()}:{value_column}",
                metric_key="hrv",
                value=row[value_column],
                unit="millisecond",
                anchor=day_window_anchor(day, config.timezone),
            )
        )
    return readings


def read_summary_heart_rate_metrics(
    connection: sqlite3.Connection,
    config: Config,
) -> list[dict[str, Any]]:
    if not table_exists(connection, "days_summary"):
        return []
    readings: list[dict[str, Any]] = []
    columns = table_columns(connection, "days_summary")
    wanted = [
        ("hr_avg", "averageHeartRate", "beatsPerMinute"),
        ("hr_max", "maxHeartRate", "beatsPerMinute"),
    ]
    selected = [item for item in wanted if item[0] in columns]
    if not selected:
        return []
    select_columns = ", ".join(["day", *(item[0] for item in selected)])
    for row in connection.execute(f"select {select_columns} from days_summary"):
        day = parse_day(row["day"])
        if day is None:
            continue
        anchor = day_window_anchor(day, config.timezone)
        for column, metric_key, unit in selected:
            readings.extend(
                metric_reading_from_value(
                    source_suffix=f"summary:{day.isoformat()}:{column}",
                    metric_key=metric_key,
                    value=row[column],
                    unit=unit,
                    anchor=anchor,
                )
            )
    return readings


def metric_reading_from_value(
    *,
    source_suffix: str,
    metric_key: str,
    value: Any,
    unit: str,
    anchor: dict[str, Any],
) -> list[dict[str, Any]]:
    numeric = duration_seconds_value(value) if unit == "second" else numeric_value(value)
    if numeric is None:
        return []
    return [
        {
            "source": "garmin",
            "externalId": f"garmindb:{source_suffix}",
            "metricKey": metric_key,
            "value": {"value": numeric, "unit": unit},
            "at": anchor,
        }
    ]


def day_window_anchor(day: date, timezone_name: str) -> dict[str, Any]:
    zone = ZoneInfo(timezone_name)
    started = datetime.combine(day, time.min, tzinfo=zone)
    ended = started + timedelta(days=1)
    return {
        "kind": "window",
        "startedAt": utc_iso(started),
        "endedAt": utc_iso(ended),
        "timezone": timezone_name,
    }


def sleep_anchor(
    started_at: Any,
    ended_at: Any,
    config: Config,
    fallback_day: date,
) -> dict[str, Any]:
    started = parse_datetime(started_at, config.timezone)
    ended = parse_datetime(ended_at, config.timezone)
    if started is None or ended is None or ended <= started:
        return day_window_anchor(fallback_day, config.timezone)
    return {
        "kind": "window",
        "startedAt": utc_iso(started),
        "endedAt": utc_iso(ended),
        "timezone": config.timezone,
    }


def parse_day(value: Any) -> date | None:
    if isinstance(value, date) and not isinstance(value, datetime):
        return value
    if isinstance(value, datetime):
        return value.date()
    if value is None:
        return None
    text = str(value).strip()
    if not text:
        return None
    try:
        return date.fromisoformat(text[:10])
    except ValueError:
        return None


def parse_datetime(value: Any, timezone_name: str) -> datetime | None:
    if isinstance(value, datetime):
        parsed = value
    elif value is None:
        return None
    else:
        text = str(value).strip()
        if not text:
            return None
        try:
            parsed = datetime.fromisoformat(text.replace("Z", "+00:00"))
        except ValueError:
            return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=ZoneInfo(timezone_name))
    return parsed


def utc_iso(value: datetime) -> str:
    return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def numeric_value(value: Any) -> float | int | None:
    if value is None:
        return None
    try:
        numeric = float(value)
    except (TypeError, ValueError):
        return None
    if numeric != numeric:
        return None
    return int(numeric) if numeric.is_integer() else numeric


def duration_seconds_value(value: Any) -> float | int | None:
    numeric = numeric_value(value)
    if numeric is not None:
        return numeric
    if value is None:
        return None
    text = str(value).strip()
    if not text:
        return None
    day_count = 0
    if "," in text and "day" in text.lower():
        day_part, text = text.split(",", 1)
        day_tokens = day_part.strip().split()
        if day_tokens:
            parsed_days = numeric_value(day_tokens[0])
            if parsed_days is not None:
                day_count = int(parsed_days)
        text = text.strip()
    parts = text.split(":")
    if len(parts) != 3:
        return None
    try:
        hours = int(parts[0])
        minutes = int(parts[1])
        seconds = float(parts[2])
    except ValueError:
        return None
    total = day_count * 86400 + hours * 3600 + minutes * 60 + seconds
    return int(total) if float(total).is_integer() else total


def table_exists(connection: sqlite3.Connection, table: str) -> bool:
    row = connection.execute(
        "select 1 from sqlite_master where type='table' and name = ?",
        (table,),
    ).fetchone()
    return row is not None


def table_columns(connection: sqlite3.Connection, table: str) -> set[str]:
    return {row[1] for row in connection.execute(f'pragma table_info("{table}")')}


def dedupe_readings(readings: list[dict[str, Any]]) -> list[dict[str, Any]]:
    by_external_id: dict[str, dict[str, Any]] = {}
    for reading in readings:
        by_external_id[reading["externalId"]] = reading
    return list(by_external_id.values())


def chunked(
    readings: list[dict[str, Any]],
    size: int,
) -> list[list[dict[str, Any]]]:
    return [readings[index : index + size] for index in range(0, len(readings), size)]


def sha256_json(payload: Any) -> str:
    encoded = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode(
        "utf-8"
    )
    return hashlib.sha256(encoded).hexdigest()


def report_status(
    session: requests.Session,
    config: Config,
    condition: str,
    trigger: str,
    failure_kind: str | None,
) -> None:
    payload: dict[str, Any] = {
        "source": "garmin",
        "condition": condition,
        "trigger": trigger,
        "occurredAt": datetime.now(timezone.utc).isoformat(),
    }
    if failure_kind is not None and condition != "ok":
        payload["failureKind"] = failure_kind

    try:
        session.post(
            f"{config.base_url}/integrations/status",
            json=payload,
            timeout=DEFAULT_TIMEOUT_SECONDS,
        )
    except requests.RequestException:
        pass


def load_state(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {"uploaded": {}, "metricBatches": {}}
    with path.open("r", encoding="utf-8") as handle:
        payload = json.load(handle)
    if not isinstance(payload, dict) or not isinstance(
        payload.get("uploaded"), dict
    ):
        raise RuntimeError(f"State file has unexpected shape: {path}")
    if not isinstance(payload.get("metricBatches"), dict):
        payload["metricBatches"] = {}
    return payload


def save_state(path: Path, state: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(state, handle, indent=2, sort_keys=True)
        handle.write("\n")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def required_env(name: str) -> str:
    value = os.getenv(name)
    if value is None or value.strip() == "":
        raise RuntimeError(f"{name} is required.")
    return value


def optional_path(value: str | None) -> Path | None:
    if value is None or value.strip() == "":
        return None
    return expand_path(value)


def expand_path(value: str) -> Path:
    return Path(value).expanduser().resolve()


def env_bool(name: str) -> bool:
    return os.getenv(name, "").strip().lower() in {"1", "true", "yes", "on"}


def env_bool_default(name: str, default: bool) -> bool:
    value = os.getenv(name)
    if value is None or value.strip() == "":
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"GarminDB Perennia sync failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
