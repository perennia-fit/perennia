from __future__ import annotations

import argparse
import dataclasses
import json
import logging
import os
import subprocess
import sys
import time as time_module
import urllib.error
import urllib.request
from datetime import date, datetime, time, timedelta, timezone as datetime_timezone
from pathlib import Path
from typing import Any, Callable, Mapping, Protocol, Sequence
from zoneinfo import ZoneInfo


CANONICAL_IMPORT_PATH = "/integrations/canonical-import"
INTEGRATION_STATUS_PATH = "/integrations/status"
DEFAULT_CONSENTED_DATA_CLASSES = ("activities",)
DAILY_MONITORING_DATA_CLASSES = ("activities", "heartRate", "sleepWellness")
DEFAULT_BACKFILL_ACTIVITY_CHUNK_SIZE = 50
DEFAULT_BACKFILL_MONITORING_CHUNK_DAYS = 7
DEFAULT_STATE_PATH = ".garmin-sidecar-state.json"
DEFAULT_POLL_INTERVAL_SECONDS = 15 * 60
LOGGER = logging.getLogger(__name__)


@dataclasses.dataclass(frozen=True)
class GarminSidecarConfig:
    garmin_email: str
    garmin_password: str
    prn_base_url: str
    prn_integration_token: str
    timezone: str = "UTC"
    consented_data_classes: tuple[str, ...] = DEFAULT_CONSENTED_DATA_CLASSES
    monitoring_date: str | None = None
    backfill_enabled: bool = True
    backfill_force: bool = False
    backfill_start_date: str | None = None
    backfill_end_date: str | None = None
    backfill_activity_chunk_size: int = DEFAULT_BACKFILL_ACTIVITY_CHUNK_SIZE
    backfill_monitoring_chunk_days: int = DEFAULT_BACKFILL_MONITORING_CHUNK_DAYS
    poll_interval_seconds: int = DEFAULT_POLL_INTERVAL_SECONDS
    state_path: str | None = DEFAULT_STATE_PATH

    @classmethod
    def from_env(cls, env: Mapping[str, str] | None = None) -> "GarminSidecarConfig":
        source = os.environ if env is None else env
        return cls(
            garmin_email=_required(source, "GARMIN_EMAIL"),
            garmin_password=_required(source, "GARMIN_PASSWORD"),
            prn_base_url=_required(source, "PRN_BASE_URL"),
            prn_integration_token=_required(source, "PRN_INTEGRATION_TOKEN"),
            timezone=source.get("PRN_TIMEZONE", "UTC"),
            consented_data_classes=_csv_tuple(
                source.get("PRN_CONSENTED_DATA_CLASSES"),
                DEFAULT_CONSENTED_DATA_CLASSES,
            ),
            monitoring_date=source.get("PRN_MONITORING_DATE"),
            backfill_enabled=_bool_value(source.get("PRN_BACKFILL_ENABLED"), True),
            backfill_force=_bool_value(source.get("PRN_BACKFILL_FORCE"), False),
            backfill_start_date=source.get("PRN_BACKFILL_START_DATE"),
            backfill_end_date=source.get("PRN_BACKFILL_END_DATE"),
            backfill_activity_chunk_size=_positive_int(
                source.get("PRN_BACKFILL_ACTIVITY_CHUNK_SIZE"),
                DEFAULT_BACKFILL_ACTIVITY_CHUNK_SIZE,
            ),
            backfill_monitoring_chunk_days=_positive_int(
                source.get("PRN_BACKFILL_MONITORING_CHUNK_DAYS"),
                DEFAULT_BACKFILL_MONITORING_CHUNK_DAYS,
            ),
            poll_interval_seconds=_positive_int(
                source.get("PRN_POLL_INTERVAL_SECONDS"),
                DEFAULT_POLL_INTERVAL_SECONDS,
            ),
            state_path=source.get("PRN_STATE_PATH", DEFAULT_STATE_PATH),
        )

    @classmethod
    def from_file(cls, path: str | Path) -> "GarminSidecarConfig":
        with Path(path).open("r", encoding="utf-8") as handle:
            raw = json.load(handle)
        if not isinstance(raw, dict):
            raise ValueError("Garmin sidecar config must be a JSON object.")

        return cls(
            garmin_email=_required(raw, "garmin_email"),
            garmin_password=_required(raw, "garmin_password"),
            prn_base_url=_required(raw, "prn_base_url"),
            prn_integration_token=_required(raw, "prn_integration_token"),
            timezone=str(raw.get("timezone", "UTC")),
            consented_data_classes=tuple(
                raw.get("consented_data_classes", DEFAULT_CONSENTED_DATA_CLASSES)
            ),
            monitoring_date=(
                None
                if raw.get("monitoring_date") is None
                else str(raw.get("monitoring_date"))
            ),
            backfill_enabled=_bool_value(raw.get("backfill_enabled"), True),
            backfill_force=_bool_value(raw.get("backfill_force"), False),
            backfill_start_date=(
                None
                if raw.get("backfill_start_date") is None
                else str(raw.get("backfill_start_date"))
            ),
            backfill_end_date=(
                None
                if raw.get("backfill_end_date") is None
                else str(raw.get("backfill_end_date"))
            ),
            backfill_activity_chunk_size=_positive_int(
                raw.get("backfill_activity_chunk_size"),
                DEFAULT_BACKFILL_ACTIVITY_CHUNK_SIZE,
            ),
            backfill_monitoring_chunk_days=_positive_int(
                raw.get("backfill_monitoring_chunk_days"),
                DEFAULT_BACKFILL_MONITORING_CHUNK_DAYS,
            ),
            poll_interval_seconds=_positive_int(
                raw.get("poll_interval_seconds"),
                DEFAULT_POLL_INTERVAL_SECONDS,
            ),
            state_path=(
                None if raw.get("state_path") is None else str(raw.get("state_path"))
            ),
        )

    def safe_summary(self) -> dict[str, Any]:
        return {
            "garmin_email": _redact_email(self.garmin_email),
            "garmin_password": "<redacted>",
            "prn_base_url": self.prn_base_url,
            "prn_integration_token": "<redacted>",
            "timezone": self.timezone,
            "consented_data_classes": list(self.consented_data_classes),
            "monitoring_date": self.monitoring_date,
            "backfill_enabled": self.backfill_enabled,
            "backfill_force": self.backfill_force,
            "backfill_start_date": self.backfill_start_date,
            "backfill_end_date": self.backfill_end_date,
            "backfill_activity_chunk_size": self.backfill_activity_chunk_size,
            "backfill_monitoring_chunk_days": self.backfill_monitoring_chunk_days,
            "poll_interval_seconds": self.poll_interval_seconds,
            "state_path": self.state_path,
        }


@dataclasses.dataclass(frozen=True)
class GarminActivity:
    activity_id: str
    summary: Mapping[str, Any]
    fit_bytes: bytes


@dataclasses.dataclass(frozen=True)
class GarminDailyMonitoring:
    calendar_date: str
    daily_summary: Mapping[str, Any]
    heart_rates: Mapping[str, Any]
    sleep: Mapping[str, Any]
    hrv: Mapping[str, Any]
    stress: Mapping[str, Any]
    body_battery: Sequence[Mapping[str, Any]]
    steps: Sequence[Mapping[str, Any]]


@dataclasses.dataclass(frozen=True)
class GarminSidecarResult:
    activity_external_id: str | None
    idempotency_key: str
    response: Mapping[str, Any]


@dataclasses.dataclass(frozen=True)
class GarminSyncResult:
    mode: str
    batches: tuple[GarminSidecarResult, ...]
    state: Mapping[str, Any]

    @property
    def batch_keys(self) -> list[str]:
        return [batch.idempotency_key for batch in self.batches]

    @property
    def responses(self) -> list[Mapping[str, Any]]:
        return [batch.response for batch in self.batches]


@dataclasses.dataclass(frozen=True)
class GarminCadenceTickResult:
    trigger: str
    sync: Any | None = None
    error: str | None = None
    retry_after_seconds: int | None = None


@dataclasses.dataclass(frozen=True)
class GarminCadenceResult:
    ticks: tuple[GarminCadenceTickResult, ...]

    @property
    def tick_count(self) -> int:
        return len(self.ticks)


class GarminClient(Protocol):
    def login(self) -> None:
        ...

    def pull_latest_activity(self) -> GarminActivity:
        ...

    def pull_activities(
        self,
        *,
        start_date: str | None,
        end_date: str | None,
        page_size: int,
    ) -> Sequence[GarminActivity]:
        ...

    def pull_daily_monitoring(
        self, *, calendar_date: str, consented_data_classes: Sequence[str]
    ) -> GarminDailyMonitoring:
        ...

    def pull_activity_streams(
        self, *, activity_id: str, consented_data_classes: Sequence[str]
    ) -> Mapping[str, Any]:
        ...


class FitMapper(Protocol):
    def map_fit(self, fit_bytes: bytes, *, timezone: str) -> dict[str, Any]:
        ...


class ImportClient(Protocol):
    def post_canonical_import(
        self, *, idempotency_key: str, canonical: Mapping[str, Any]
    ) -> Mapping[str, Any]:
        ...


class IntegrationStatusClient(Protocol):
    def post_integration_status(self, report: Mapping[str, Any]) -> Mapping[str, Any]:
        ...


class PerenniaHttpError(RuntimeError):
    def __init__(
        self,
        *,
        status_code: int,
        retry_after_seconds: int | None = None,
    ) -> None:
        super().__init__(f"Perennia request failed with HTTP {status_code}.")
        self.status_code = status_code
        self.retry_after_seconds = retry_after_seconds


class GarminLoginError(RuntimeError):
    def __init__(self) -> None:
        super().__init__("Garmin login failed; re-supply credentials in the self-host config.")


class GarminConnectClient:
    def __init__(self, *, email: str, password: str) -> None:
        self._email = email
        self._password = password
        self._client: Any | None = None

    def login(self) -> None:
        try:
            from garminconnect import Garmin  # type: ignore
        except ImportError as error:
            raise RuntimeError(
                "python-garminconnect is required for live Garmin acquisition. "
                "Install it in the self-host sidecar environment."
            ) from error

        client = Garmin(self._email, self._password)
        client.login()
        self._client = client

    def pull_latest_activity(self) -> GarminActivity:
        if self._client is None:
            raise RuntimeError("Garmin client must be logged in before pulling.")

        activities = self._client.get_activities(0, 1)
        if not activities:
            raise RuntimeError("Garmin account returned no activities.")

        summary = activities[0]
        activity_id = _summary_activity_id(summary)
        if activity_id is None:
            raise RuntimeError("Garmin activity summary did not include an activity id.")
        fit_bytes = _download_fit_bytes(self._client, activity_id)
        return GarminActivity(
            activity_id=activity_id,
            summary=summary,
            fit_bytes=fit_bytes,
        )

    def pull_activities(
        self,
        *,
        start_date: str | None,
        end_date: str | None,
        page_size: int,
    ) -> Sequence[GarminActivity]:
        if self._client is None:
            raise RuntimeError("Garmin client must be logged in before pulling.")

        start_day = _parse_optional_day(start_date)
        end_day = _parse_optional_day(end_date)
        offset = 0
        limit = max(1, page_size)
        activities: list[GarminActivity] = []

        while True:
            summaries = self._client.get_activities(offset, limit)
            if not summaries:
                break

            dated_page: list[date] = []
            for summary in summaries:
                if not isinstance(summary, Mapping):
                    continue
                started_at = _summary_started_at(summary, "UTC")
                started_day = started_at.date() if started_at is not None else None
                if started_day is not None:
                    dated_page.append(started_day)
                if end_day is not None and started_day is not None and started_day > end_day:
                    continue
                if start_day is not None and started_day is not None and started_day < start_day:
                    continue

                activity_id = _summary_activity_id(summary)
                if activity_id is None:
                    continue
                activities.append(
                    GarminActivity(
                        activity_id=activity_id,
                        summary=summary,
                        fit_bytes=_download_fit_bytes(self._client, activity_id),
                    )
                )

            offset += len(summaries)
            if len(summaries) < limit:
                break
            if start_day is not None and dated_page and max(dated_page) < start_day:
                break

        return tuple(activities)

    def pull_daily_monitoring(
        self, *, calendar_date: str, consented_data_classes: Sequence[str]
    ) -> GarminDailyMonitoring:
        if self._client is None:
            raise RuntimeError("Garmin client must be logged in before pulling.")

        consented = set(consented_data_classes)
        daily_summary = (
            _call_optional_garmin_method(self._client, "get_stats", calendar_date, default={})
            if "activities" in consented
            else {}
        )
        steps = (
            _call_optional_garmin_method(
                self._client,
                "get_steps_data",
                calendar_date,
                default=[],
            )
            if "activities" in consented
            else []
        )
        heart_rates = (
            _call_optional_garmin_method(
                self._client,
                "get_heart_rates",
                calendar_date,
                default={},
            )
            if "heartRate" in consented
            else {}
        )
        hrv = (
            _call_optional_garmin_method(
                self._client,
                "get_hrv_data",
                calendar_date,
                default={},
            )
            if "heartRate" in consented
            else {}
        )
        sleep = (
            _call_optional_garmin_method(
                self._client,
                "get_sleep_data",
                calendar_date,
                default={},
            )
            if "sleepWellness" in consented
            else {}
        )
        stress = (
            _call_optional_garmin_method(
                self._client,
                "get_stress_data",
                calendar_date,
                default={},
            )
            if "sleepWellness" in consented
            else {}
        )
        body_battery = (
            _call_optional_garmin_method(
                self._client,
                "get_body_battery",
                calendar_date,
                calendar_date,
                default=[],
            )
            if "sleepWellness" in consented
            else []
        )

        return GarminDailyMonitoring(
            calendar_date=calendar_date,
            daily_summary=_as_mapping(daily_summary),
            heart_rates=_as_mapping(heart_rates),
            sleep=_as_mapping(sleep),
            hrv=_as_mapping(hrv),
            stress=_as_mapping(stress),
            body_battery=_as_mapping_sequence(body_battery),
            steps=_as_mapping_sequence(steps),
        )

    def pull_activity_streams(
        self, *, activity_id: str, consented_data_classes: Sequence[str]
    ) -> Mapping[str, Any]:
        if self._client is None:
            raise RuntimeError("Garmin client must be logged in before pulling.")

        # FIT parsing already carries HR/cadence streams for the selected activity.
        # The extra Garmin details endpoint can include GPS, so only call it for an
        # explicit GPS opt-in.
        if "gps" not in set(consented_data_classes):
            return {}

        return _as_mapping(
            _call_optional_garmin_method(
                self._client,
                "get_activity_details",
                activity_id,
                default={},
            )
        )


class NodeFitMapper:
    def __init__(
        self,
        *,
        command: Sequence[str] | None = None,
        cwd: str | Path | None = None,
        runner: Callable[..., subprocess.CompletedProcess[bytes]] = subprocess.run,
    ) -> None:
        self._repo_root = _repo_root()
        self._command = tuple(command) if command is not None else self._default_command()
        self._cwd = Path(cwd) if cwd is not None else self._repo_root
        self._runner = runner

    def map_fit(self, fit_bytes: bytes, *, timezone: str) -> dict[str, Any]:
        completed = self._runner(
            [*self._command, "--timezone", timezone],
            input=fit_bytes,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            cwd=str(self._cwd),
            check=False,
        )
        if completed.returncode != 0:
            stderr = completed.stderr.decode("utf-8", errors="replace").strip()
            raise RuntimeError(f"FIT mapper failed: {stderr}")

        parsed = json.loads(completed.stdout.decode("utf-8"))
        if not isinstance(parsed, dict):
            raise RuntimeError("FIT mapper returned a non-object canonical batch.")
        return parsed

    def _default_command(self) -> tuple[str, ...]:
        bridge = self._repo_root / "sidecars" / "garmin" / "fit_mapper_bridge.mjs"
        configured = os.environ.get("PRN_FIT_MAPPER_COMMAND")
        if configured:
            return (*configured.split(), str(bridge))

        return (
            "corepack",
            "pnpm",
            "--filter",
            "@perennia/server",
            "exec",
            "node",
            "--import",
            "tsx",
            str(bridge),
        )


class PerenniaImportClient:
    def __init__(self, *, base_url: str, integration_token: str) -> None:
        self._base_url = base_url.rstrip("/")
        self._integration_token = integration_token

    def post_canonical_import(
        self, *, idempotency_key: str, canonical: Mapping[str, Any]
    ) -> Mapping[str, Any]:
        body = json.dumps(
            {
                "idempotencyKey": idempotency_key,
                "activities": canonical.get("activities", []),
                "metricReadings": canonical.get("metricReadings", []),
                "series": canonical.get("series", []),
                "consentedDataClasses": canonical.get(
                    "consentedDataClasses", DEFAULT_CONSENTED_DATA_CLASSES
                ),
            }
        ).encode("utf-8")
        request = urllib.request.Request(
            f"{self._base_url}{CANONICAL_IMPORT_PATH}",
            data=body,
            method="POST",
            headers={
                "Authorization": f"Bearer {self._integration_token}",
                "Content-Type": "application/json",
                "Accept": "application/json",
            },
        )

        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                payload = response.read()
        except urllib.error.HTTPError as error:
            raise PerenniaHttpError(
                status_code=error.code,
                retry_after_seconds=_retry_after_header(error.headers),
            ) from error

        decoded = json.loads(payload.decode("utf-8"))
        if not isinstance(decoded, dict):
            raise RuntimeError("Perennia canonical import returned a non-object response.")
        return decoded


class PerenniaIntegrationStatusClient:
    def __init__(self, *, base_url: str, integration_token: str) -> None:
        self._base_url = base_url.rstrip("/")
        self._integration_token = integration_token

    def post_integration_status(self, report: Mapping[str, Any]) -> Mapping[str, Any]:
        body = json.dumps(report).encode("utf-8")
        request = urllib.request.Request(
            f"{self._base_url}{INTEGRATION_STATUS_PATH}",
            data=body,
            method="POST",
            headers={
                "Authorization": f"Bearer {self._integration_token}",
                "Content-Type": "application/json",
                "Accept": "application/json",
            },
        )

        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                payload = response.read()
        except urllib.error.HTTPError as error:
            raise PerenniaHttpError(
                status_code=error.code,
                retry_after_seconds=_retry_after_header(error.headers),
            ) from error

        decoded = json.loads(payload.decode("utf-8"))
        if not isinstance(decoded, dict):
            raise RuntimeError("Perennia integration status returned a non-object response.")
        return decoded


def run_once(
    config: GarminSidecarConfig,
    *,
    garmin_client: GarminClient | None = None,
    fit_mapper: FitMapper | None = None,
    import_client: ImportClient | None = None,
) -> GarminSidecarResult:
    garmin = garmin_client or GarminConnectClient(
        email=config.garmin_email,
        password=config.garmin_password,
    )
    mapper = fit_mapper or NodeFitMapper()
    perennia = import_client or PerenniaImportClient(
        base_url=config.prn_base_url,
        integration_token=config.prn_integration_token,
    )

    garmin.login()
    consented = tuple(config.consented_data_classes)
    calendar_date = config.monitoring_date or date.today().isoformat()
    canonical: dict[str, Any] = {
        "activities": [],
        "metricReadings": [],
        "series": [],
        "consentedDataClasses": list(consented),
    }
    external_id: str | None = None

    if "activities" in set(consented):
        pulled = garmin.pull_latest_activity()
        mapped = _canonical_batch_for_garmin_activity(
            pulled,
            garmin=garmin,
            mapper=mapper,
            timezone=config.timezone,
            consented_data_classes=consented,
        )
        canonical = mapped.canonical
        external_id = mapped.external_id

    daily_monitoring = _pull_daily_monitoring_if_supported(
        garmin,
        calendar_date=calendar_date,
        consented_data_classes=consented,
    )
    canonical = canonical_batch_with_garmin_daily_monitoring(
        canonical,
        monitoring=daily_monitoring,
        timezone=config.timezone,
        consented_data_classes=consented,
    )
    canonical = filter_canonical_batch_by_consent(canonical, consented)
    idempotency_key = (
        f"garmin-sidecar:{external_id}"
        if external_id is not None
        else f"garmin-sidecar:daily:{calendar_date}"
    )
    response = perennia.post_canonical_import(
        idempotency_key=idempotency_key,
        canonical=canonical,
    )

    return GarminSidecarResult(
        activity_external_id=external_id,
        idempotency_key=idempotency_key,
        response=response,
    )


def run_sync(
    config: GarminSidecarConfig,
    *,
    garmin_client: GarminClient | None = None,
    fit_mapper: FitMapper | None = None,
    import_client: ImportClient | None = None,
    status_client: IntegrationStatusClient | None = None,
    trigger: str = "manual",
) -> GarminSyncResult:
    garmin = garmin_client or GarminConnectClient(
        email=config.garmin_email,
        password=config.garmin_password,
    )
    mapper = fit_mapper or NodeFitMapper()
    perennia = import_client or PerenniaImportClient(
        base_url=config.prn_base_url,
        integration_token=config.prn_integration_token,
    )
    status = status_client
    if status is None and import_client is None:
        status = PerenniaIntegrationStatusClient(
            base_url=config.prn_base_url,
            integration_token=config.prn_integration_token,
        )

    try:
        try:
            garmin.login()
        except Exception as error:
            raise GarminLoginError() from error

        state_path = _state_path(config)
        state = _read_sync_state(state_path)
        if (
            config.backfill_enabled
            and (config.backfill_force or state.get("backfillCompleted") is not True)
        ):
            result = _run_backfill(
                config,
                garmin=garmin,
                mapper=mapper,
                perennia=perennia,
                state=state,
                state_path=state_path,
            )
        else:
            result = _run_incremental_sync(
                config,
                garmin=garmin,
                mapper=mapper,
                perennia=perennia,
                state=state,
                state_path=state_path,
            )
    except Exception as error:
        _report_integration_status_safely(
            status,
            _integration_failure_report(error, trigger=trigger),
        )
        raise

    _report_integration_status_safely(
        status,
        {"source": "garmin", "condition": "ok", "trigger": trigger},
    )
    return result


def run_manual_trigger(
    config: GarminSidecarConfig,
    *,
    runner: Callable[[GarminSidecarConfig], Any] | None = None,
) -> GarminCadenceTickResult:
    sync = runner(config) if runner is not None else run_sync(config, trigger="manual")
    return GarminCadenceTickResult(trigger="manual", sync=sync)


def run_scheduled(
    config: GarminSidecarConfig,
    *,
    runner: Callable[[GarminSidecarConfig], Any] | None = None,
    sleeper: Callable[[int], None] = time_module.sleep,
    max_ticks: int | None = None,
) -> GarminCadenceResult:
    ticks: list[GarminCadenceTickResult] = []
    while max_ticks is None or len(ticks) < max_ticks:
        try:
            sync = (
                runner(config)
                if runner is not None
                else run_sync(config, trigger="scheduled")
            )
            ticks.append(
                GarminCadenceTickResult(trigger="scheduled", sync=sync)
            )
        except Exception as error:
            error_type = type(error).__name__
            retry_after = _retry_after_seconds(error)
            LOGGER.warning(
                "Garmin scheduled sync tick failed with %s; continuing after %s seconds.",
                error_type,
                max(config.poll_interval_seconds, retry_after or 0),
            )
            ticks.append(
                GarminCadenceTickResult(
                    trigger="scheduled",
                    error=error_type,
                    retry_after_seconds=retry_after,
                )
            )
        if max_ticks is not None and len(ticks) >= max_ticks:
            break
        sleeper(_sleep_seconds_for_tick(config, ticks[-1]))

    return GarminCadenceResult(ticks=tuple(ticks))


@dataclasses.dataclass(frozen=True)
class _MappedGarminActivity:
    canonical: dict[str, Any]
    external_id: str
    started_at: str


def _run_backfill(
    config: GarminSidecarConfig,
    *,
    garmin: GarminClient,
    mapper: FitMapper,
    perennia: ImportClient,
    state: Mapping[str, Any],
    state_path: Path | None,
) -> GarminSyncResult:
    consented = tuple(config.consented_data_classes)
    backfill_end = _backfill_end_date(config)
    raw_activities = (
        garmin.pull_activities(
            start_date=config.backfill_start_date,
            end_date=backfill_end,
            page_size=config.backfill_activity_chunk_size,
        )
        if "activities" in set(consented)
        else ()
    )
    mapped_activities = [
        _canonical_batch_for_garmin_activity(
            activity,
            garmin=garmin,
            mapper=mapper,
            timezone=config.timezone,
            consented_data_classes=consented,
        )
        for activity in raw_activities
    ]
    backfill_start = _backfill_start_date(config, mapped_activities, backfill_end)
    batches: list[GarminSidecarResult] = []

    for index, activity_chunk in enumerate(
        _chunked(mapped_activities, config.backfill_activity_chunk_size),
        start=1,
    ):
        canonical = _merge_canonical_batches(
            [activity.canonical for activity in activity_chunk],
            consented_data_classes=consented,
        )
        canonical = filter_canonical_batch_by_consent(canonical, consented)
        idempotency_key = (
            "garmin-sidecar:backfill:"
            f"activities:{backfill_start}:{backfill_end}:{index:04d}"
        )
        response = perennia.post_canonical_import(
            idempotency_key=idempotency_key,
            canonical=canonical,
        )
        batches.append(
            GarminSidecarResult(
                activity_external_id=None,
                idempotency_key=idempotency_key,
                response=response,
            )
        )

    if _should_pull_daily_monitoring(consented):
        for start_day, end_day in _date_windows(
            backfill_start,
            backfill_end,
            config.backfill_monitoring_chunk_days,
        ):
            canonical = _daily_monitoring_window_batch(
                garmin,
                start_day=start_day,
                end_day=end_day,
                timezone=config.timezone,
                consented_data_classes=consented,
            )
            canonical = filter_canonical_batch_by_consent(canonical, consented)
            idempotency_key = f"garmin-sidecar:backfill:daily:{start_day}:{end_day}"
            response = perennia.post_canonical_import(
                idempotency_key=idempotency_key,
                canonical=canonical,
            )
            batches.append(
                GarminSidecarResult(
                    activity_external_id=None,
                    idempotency_key=idempotency_key,
                    response=response,
                )
            )

    next_state = {
        **dict(state),
        "backfillCompleted": True,
        "backfillCompletedAt": _iso_utc(datetime.now(datetime_timezone.utc)),
        "backfillStartDate": backfill_start,
        "backfillEndDate": backfill_end,
        "lastMonitoringDate": backfill_end
        if _should_pull_daily_monitoring(consented)
        else state.get("lastMonitoringDate"),
    }
    latest_activity = _latest_mapped_activity(mapped_activities)
    if latest_activity is not None:
        next_state["lastActivityExternalId"] = latest_activity.external_id
        next_state["lastActivityStartedAt"] = latest_activity.started_at

    _write_sync_state(state_path, next_state)
    return GarminSyncResult(
        mode="backfill",
        batches=tuple(batches),
        state=next_state,
    )


def _run_incremental_sync(
    config: GarminSidecarConfig,
    *,
    garmin: GarminClient,
    mapper: FitMapper,
    perennia: ImportClient,
    state: Mapping[str, Any],
    state_path: Path | None,
) -> GarminSyncResult:
    consented = tuple(config.consented_data_classes)
    end_day = _sync_end_date(config)
    last_activity_started_at = _state_string(state, "lastActivityStartedAt")
    parsed_last_activity = (
        _parse_garmin_timestamp(last_activity_started_at, "UTC")
        if last_activity_started_at is not None
        else None
    )
    activity_start_day = (
        parsed_last_activity.date().isoformat()
        if parsed_last_activity is not None
        else end_day
    )
    batches: list[GarminSidecarResult] = []
    imported_activities: list[_MappedGarminActivity] = []

    if "activities" in set(consented):
        for pulled in garmin.pull_activities(
            start_date=activity_start_day,
            end_date=end_day,
            page_size=config.backfill_activity_chunk_size,
        ):
            mapped = _canonical_batch_for_garmin_activity(
                pulled,
                garmin=garmin,
                mapper=mapper,
                timezone=config.timezone,
                consented_data_classes=consented,
            )
            if not _is_after_high_watermark(
                mapped.started_at,
                last_activity_started_at,
            ):
                continue
            canonical = filter_canonical_batch_by_consent(mapped.canonical, consented)
            idempotency_key = f"garmin-sidecar:{mapped.external_id}"
            response = perennia.post_canonical_import(
                idempotency_key=idempotency_key,
                canonical=canonical,
            )
            imported_activities.append(mapped)
            batches.append(
                GarminSidecarResult(
                    activity_external_id=mapped.external_id,
                    idempotency_key=idempotency_key,
                    response=response,
                )
            )

    last_monitoring_date = _state_string(state, "lastMonitoringDate")
    monitoring_start = _next_day(last_monitoring_date) if last_monitoring_date else end_day
    if _should_pull_daily_monitoring(consented) and monitoring_start <= end_day:
        for start_day, chunk_end_day in _date_windows(
            monitoring_start,
            end_day,
            config.backfill_monitoring_chunk_days,
        ):
            canonical = _daily_monitoring_window_batch(
                garmin,
                start_day=start_day,
                end_day=chunk_end_day,
                timezone=config.timezone,
                consented_data_classes=consented,
            )
            canonical = filter_canonical_batch_by_consent(canonical, consented)
            idempotency_key = _daily_incremental_idempotency_key(
                start_day,
                chunk_end_day,
            )
            response = perennia.post_canonical_import(
                idempotency_key=idempotency_key,
                canonical=canonical,
            )
            batches.append(
                GarminSidecarResult(
                    activity_external_id=None,
                    idempotency_key=idempotency_key,
                    response=response,
                )
            )

    next_state = dict(state)
    latest_activity = _latest_mapped_activity(imported_activities)
    if latest_activity is not None:
        next_state["lastActivityExternalId"] = latest_activity.external_id
        next_state["lastActivityStartedAt"] = latest_activity.started_at
    if _should_pull_daily_monitoring(consented) and monitoring_start <= end_day:
        next_state["lastMonitoringDate"] = end_day

    _write_sync_state(state_path, next_state)
    return GarminSyncResult(
        mode="incremental",
        batches=tuple(batches),
        state=next_state,
    )


def _canonical_batch_for_garmin_activity(
    pulled: GarminActivity,
    *,
    garmin: GarminClient,
    mapper: FitMapper,
    timezone: str,
    consented_data_classes: Sequence[str],
) -> _MappedGarminActivity:
    canonical = mapper.map_fit(pulled.fit_bytes, timezone=timezone)
    canonical = canonical_batch_with_garmin_summary(
        canonical,
        summary=pulled.summary,
        fallback_activity_id=pulled.activity_id,
        consented_data_classes=consented_data_classes,
    )
    activity = _first_activity(canonical)
    external_id = str(activity["externalId"])
    activity_streams = _pull_activity_streams_if_supported(
        garmin,
        activity_id=pulled.activity_id,
        consented_data_classes=consented_data_classes,
    )
    canonical = canonical_batch_with_garmin_activity_streams(
        canonical,
        activity_external_id=external_id,
        activity_streams=activity_streams,
        timezone=timezone,
        consented_data_classes=consented_data_classes,
    )
    activity = _first_activity(canonical)
    summary_started_at = _summary_started_at(pulled.summary, timezone)
    return _MappedGarminActivity(
        canonical=canonical,
        external_id=external_id,
        started_at=_iso_utc(summary_started_at)
        if summary_started_at is not None
        else str(activity["startedAt"]),
    )


def canonical_batch_with_garmin_summary(
    canonical: Mapping[str, Any],
    *,
    summary: Mapping[str, Any],
    fallback_activity_id: str,
    consented_data_classes: Sequence[str],
) -> dict[str, Any]:
    batch = json.loads(json.dumps(canonical))
    activity = _first_activity(batch)
    old_external_id = str(activity["externalId"])
    new_external_id = str(_summary_activity_id(summary) or fallback_activity_id)
    started_at = str(activity["startedAt"])
    ended_at = str(activity["endedAt"])
    timezone = str(activity["timezone"])
    source = str(activity.get("source", "garmin"))

    activity["externalId"] = new_external_id
    activity_type = _summary_activity_type(summary)
    if activity_type is not None:
        activity["activityType"] = activity_type
    activity["summary"] = {
        **activity.get("summary", {}),
        **_summary_dimensions(summary),
    }
    activity["summaryMetrics"] = _merge_summary_metrics(
        existing=activity.get("summaryMetrics", []),
        summary=summary,
        source=source,
        external_id=new_external_id,
        started_at=started_at,
        ended_at=ended_at,
        timezone=timezone,
    )

    for index, item in enumerate(activity.get("sets", []), start=1):
        item["source"] = source
        item["externalId"] = _replace_external_id(
            str(item.get("externalId", f"{old_external_id}:set:{index}")),
            old_external_id,
            new_external_id,
            f":set:{index}",
        )

    for series in batch.get("series", []):
        if series.get("anchor", {}).get("kind") == "activity":
            series["anchor"]["source"] = source
            series["anchor"]["externalId"] = new_external_id
        series["source"] = source
        series["externalId"] = _replace_external_id(
            str(series["externalId"]),
            old_external_id,
            new_external_id,
            f":series:{series['type']}",
        )

    batch["consentedDataClasses"] = list(consented_data_classes)
    return batch


def canonical_batch_with_garmin_daily_monitoring(
    canonical: Mapping[str, Any],
    *,
    monitoring: GarminDailyMonitoring | None,
    timezone: str,
    consented_data_classes: Sequence[str],
) -> dict[str, Any]:
    batch = json.loads(json.dumps(canonical))
    if monitoring is None:
        batch["consentedDataClasses"] = list(consented_data_classes)
        return batch

    readings = list(batch.get("metricReadings", []))
    series = list(batch.get("series", []))
    mapped = garmin_daily_monitoring_to_canonical(
        monitoring,
        timezone=timezone,
        consented_data_classes=consented_data_classes,
    )
    readings.extend(mapped["metricReadings"])
    series.extend(mapped["series"])
    batch["metricReadings"] = readings
    batch["series"] = _dedupe_series(series)
    batch["consentedDataClasses"] = list(consented_data_classes)
    return batch


def canonical_batch_with_garmin_activity_streams(
    canonical: Mapping[str, Any],
    *,
    activity_external_id: str,
    activity_streams: Mapping[str, Any],
    timezone: str,
    consented_data_classes: Sequence[str],
) -> dict[str, Any]:
    batch = json.loads(json.dumps(canonical))
    if not activity_streams:
        batch["consentedDataClasses"] = list(consented_data_classes)
        return batch

    source = _first_activity(batch).get("source", "garmin")
    series = list(batch.get("series", []))
    series.extend(
        garmin_activity_streams_to_canonical_series(
            activity_streams,
            activity_external_id=activity_external_id,
            source=str(source),
            timezone=timezone,
            consented_data_classes=consented_data_classes,
        )
    )
    batch["series"] = _dedupe_series(series)
    batch["consentedDataClasses"] = list(consented_data_classes)
    return batch


def garmin_daily_monitoring_to_canonical(
    monitoring: GarminDailyMonitoring,
    *,
    timezone: str,
    consented_data_classes: Sequence[str],
) -> dict[str, list[dict[str, Any]]]:
    consented = set(consented_data_classes)
    readings: list[dict[str, Any]] = []
    series: list[dict[str, Any]] = []
    day = monitoring.calendar_date
    day_anchor = _day_window_anchor(day, timezone)
    day_prefix = f"daily-{day}"

    if "activities" in consented:
        steps = _first_number_across(
            (
                monitoring.daily_summary,
                _first_mapping(monitoring.steps),
            ),
            ("totalSteps", "steps", "stepCount", "totalStepCount"),
        )
        _append_scalar_reading(
            readings,
            source="garmin",
            external_id=f"{day_prefix}:steps",
            metric_key="steps",
            value=steps,
            unit="count",
            at=day_anchor,
        )
        active_kilocalories = _first_number_across(
            (monitoring.daily_summary,),
            (
                "activeKilocalories",
                "activeCalories",
                "activeKiloCalories",
                "activeKilocaloriesConsumed",
            ),
        )
        _append_scalar_reading(
            readings,
            source="garmin",
            external_id=f"{day_prefix}:active-kilocalories",
            metric_key="activeKilocalories",
            value=active_kilocalories,
            unit="kilocalorie",
            at=day_anchor,
        )
        total_kilocalories = _first_number_across(
            (monitoring.daily_summary,),
            ("totalKilocalories", "totalCalories", "totalKiloCalories"),
        )
        _append_scalar_reading(
            readings,
            source="garmin",
            external_id=f"{day_prefix}:total-kilocalories",
            metric_key="totalKilocalories",
            value=total_kilocalories,
            unit="kilocalorie",
            at=day_anchor,
        )

    if "heartRate" in consented:
        resting_hr = _first_number_across(
            (monitoring.daily_summary, monitoring.heart_rates),
            (
                "restingHeartRate",
                "restingHR",
                "restingHeartRateInBeatsPerMinute",
                "minHeartRate",
            ),
        )
        _append_scalar_reading(
            readings,
            source="garmin",
            external_id=f"{day_prefix}:resting-heart-rate",
            metric_key="restingHeartRate",
            value=resting_hr,
            unit="beatsPerMinute",
            at=day_anchor,
        )
        hrv = _first_number_across(
            (
                monitoring.hrv,
                _as_mapping(monitoring.hrv.get("hrvSummary")),
            ),
            ("lastNightAvg", "weeklyAvg", "hrvValue", "average", "avg"),
        )
        _append_scalar_reading(
            readings,
            source="garmin",
            external_id=f"{day_prefix}:hrv",
            metric_key="hrv",
            value=hrv,
            unit="millisecond",
            at=day_anchor,
        )
        heart_rate_series = _timestamped_values_to_series(
            monitoring.heart_rates,
            external_id=f"{day_prefix}:series:heartRate",
            series_type="heartRate",
            source="garmin",
            timezone=timezone,
            anchor={
                "kind": "timeWindow",
                "startedAt": day_anchor["startedAt"],
                "endedAt": day_anchor["endedAt"],
                "timezone": timezone,
            },
            value_keys=("heartRate", "heartRateValue", "value", "bpm"),
            value_unit="beatsPerMinute",
            container_keys=("heartRateValues", "heartRateValuesArray", "values"),
        )
        if heart_rate_series is not None:
            series.append(heart_rate_series)

    if "sleepWellness" in consented:
        sleep_anchor = _sleep_window_anchor(monitoring.sleep, timezone) or day_anchor
        sleep_duration = _first_number_across(
            (monitoring.sleep, _as_mapping(monitoring.sleep.get("dailySleepDTO"))),
            (
                "sleepTimeSeconds",
                "sleepDurationSeconds",
                "durationInSeconds",
                "sleepSeconds",
            ),
        )
        if sleep_duration is None and sleep_anchor["kind"] == "window":
            sleep_duration = _window_duration_seconds(sleep_anchor)
        _append_scalar_reading(
            readings,
            source="garmin",
            external_id=f"{day_prefix}:sleep-duration",
            metric_key="sleepDuration",
            value=sleep_duration,
            unit="second",
            at=sleep_anchor,
        )
        stress = _first_number_across(
            (monitoring.stress, monitoring.daily_summary),
            ("avgStressLevel", "averageStressLevel", "stressLevel", "stress"),
        )
        _append_scalar_reading(
            readings,
            source="garmin",
            external_id=f"{day_prefix}:average-stress",
            metric_key="averageStress",
            value=stress,
            unit="score",
            at=day_anchor,
        )
        body_battery = _body_battery_value(monitoring.body_battery)
        _append_scalar_reading(
            readings,
            source="garmin",
            external_id=f"{day_prefix}:body-battery",
            metric_key="bodyBattery",
            value=body_battery,
            unit="score",
            at=day_anchor,
        )

    return {
        "metricReadings": readings,
        "series": _dedupe_series(series),
    }


def garmin_activity_streams_to_canonical_series(
    activity_streams: Mapping[str, Any],
    *,
    activity_external_id: str,
    source: str,
    timezone: str,
    consented_data_classes: Sequence[str],
) -> list[dict[str, Any]]:
    consented = set(consented_data_classes)
    samples = _activity_detail_samples(activity_streams)
    if not samples:
        return []

    series: list[dict[str, Any]] = []
    anchor = {
        "kind": "activity",
        "source": source,
        "externalId": activity_external_id,
    }
    if "heartRate" in consented:
        heart_rate = _samples_to_series(
            samples,
            external_id=f"{activity_external_id}:details:series:heartRate",
            series_type="heartRate",
            source=source,
            timezone=timezone,
            anchor=anchor,
            value_keys=("heartRate", "heartRateInBeatsPerMinute", "heart_rate"),
            value_unit="beatsPerMinute",
        )
        if heart_rate is not None:
            series.append(heart_rate)

    if "gps" in consented:
        location = _samples_to_location_series(
            samples,
            external_id=f"{activity_external_id}:details:series:location",
            source=source,
            timezone=timezone,
            anchor=anchor,
        )
        if location is not None:
            series.append(location)

    return _dedupe_series(series)


def filter_canonical_batch_by_consent(
    canonical: Mapping[str, Any],
    consented_data_classes: Sequence[str],
) -> dict[str, Any]:
    consented = set(consented_data_classes)
    batch = json.loads(json.dumps(canonical))
    activities = []
    if "activities" in consented:
        for activity in batch.get("activities", []):
            if isinstance(activity, dict):
                activity = {
                    **activity,
                    "summaryMetrics": [
                        reading
                        for reading in activity.get("summaryMetrics", [])
                        if _metric_reading_data_class(reading) in consented
                    ],
                }
            activities.append(activity)

    batch["activities"] = activities
    batch["metricReadings"] = [
        reading
        for reading in batch.get("metricReadings", [])
        if _metric_reading_data_class(reading) in consented
    ]
    batch["series"] = [
        series
        for series in batch.get("series", [])
        if _series_data_class(series) in consented
    ]
    batch["consentedDataClasses"] = list(consented_data_classes)
    return batch


def _daily_monitoring_window_batch(
    garmin: GarminClient,
    *,
    start_day: str,
    end_day: str,
    timezone: str,
    consented_data_classes: Sequence[str],
) -> dict[str, Any]:
    batches: list[Mapping[str, Any]] = []
    for calendar_date in _date_range(start_day, end_day):
        monitoring = _pull_daily_monitoring_if_supported(
            garmin,
            calendar_date=calendar_date,
            consented_data_classes=consented_data_classes,
        )
        batches.append(
            canonical_batch_with_garmin_daily_monitoring(
                _empty_canonical_batch(consented_data_classes),
                monitoring=monitoring,
                timezone=timezone,
                consented_data_classes=consented_data_classes,
            )
        )

    return _merge_canonical_batches(
        batches,
        consented_data_classes=consented_data_classes,
    )


def _empty_canonical_batch(
    consented_data_classes: Sequence[str],
) -> dict[str, Any]:
    return {
        "activities": [],
        "metricReadings": [],
        "series": [],
        "consentedDataClasses": list(consented_data_classes),
    }


def _merge_canonical_batches(
    batches: Sequence[Mapping[str, Any]],
    *,
    consented_data_classes: Sequence[str],
) -> dict[str, Any]:
    merged = _empty_canonical_batch(consented_data_classes)
    for batch in batches:
        merged["activities"].extend(batch.get("activities", []))
        merged["metricReadings"].extend(batch.get("metricReadings", []))
        merged["series"].extend(batch.get("series", []))
    merged["series"] = _dedupe_series(merged["series"])
    return merged


def _should_pull_daily_monitoring(consented_data_classes: Sequence[str]) -> bool:
    consented = set(consented_data_classes)
    return any(item in consented for item in DAILY_MONITORING_DATA_CLASSES)


def _backfill_end_date(config: GarminSidecarConfig) -> str:
    return config.backfill_end_date or config.monitoring_date or date.today().isoformat()


def _sync_end_date(config: GarminSidecarConfig) -> str:
    return config.monitoring_date or date.today().isoformat()


def _backfill_start_date(
    config: GarminSidecarConfig,
    activities: Sequence[_MappedGarminActivity],
    fallback_end_date: str,
) -> str:
    if config.backfill_start_date:
        return config.backfill_start_date
    started_days = [
        parsed.date().isoformat()
        for parsed in (
            _parse_garmin_timestamp(activity.started_at, "UTC")
            for activity in activities
        )
        if parsed is not None
    ]
    return min(started_days) if started_days else fallback_end_date


def _latest_mapped_activity(
    activities: Sequence[_MappedGarminActivity],
) -> _MappedGarminActivity | None:
    dated: list[tuple[datetime, _MappedGarminActivity]] = []
    for activity in activities:
        parsed = _parse_garmin_timestamp(activity.started_at, "UTC")
        if parsed is not None:
            dated.append((parsed, activity))
    if not dated:
        return None
    return max(dated, key=lambda item: item[0])[1]


def _date_windows(
    start_day: str,
    end_day: str,
    chunk_days: int,
) -> list[tuple[str, str]]:
    start = _parse_day(start_day)
    end = _parse_day(end_day)
    if start > end:
        return []
    windows: list[tuple[str, str]] = []
    current = start
    size = max(1, chunk_days)
    while current <= end:
        window_end = min(current + timedelta(days=size - 1), end)
        windows.append((current.isoformat(), window_end.isoformat()))
        current = window_end + timedelta(days=1)
    return windows


def _date_range(start_day: str, end_day: str) -> list[str]:
    start = _parse_day(start_day)
    end = _parse_day(end_day)
    if start > end:
        return []
    days = []
    current = start
    while current <= end:
        days.append(current.isoformat())
        current += timedelta(days=1)
    return days


def _chunked(items: Sequence[Any], size: int) -> list[Sequence[Any]]:
    chunk_size = max(1, size)
    return [items[index : index + chunk_size] for index in range(0, len(items), chunk_size)]


def _state_path(config: GarminSidecarConfig) -> Path | None:
    return None if config.state_path is None else Path(config.state_path)


def _read_sync_state(path: Path | None) -> dict[str, Any]:
    if path is None or not path.exists():
        return {}
    with path.open("r", encoding="utf-8") as handle:
        raw = json.load(handle)
    if not isinstance(raw, dict):
        raise ValueError("Garmin sidecar state must be a JSON object.")
    return raw


def _write_sync_state(path: Path | None, state: Mapping[str, Any]) -> None:
    if path is None:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(f"{path.suffix}.tmp")
    temporary.write_text(
        json.dumps(dict(state), indent=2, sort_keys=True),
        encoding="utf-8",
    )
    temporary.replace(path)


def _state_string(state: Mapping[str, Any], key: str) -> str | None:
    value = state.get(key)
    return str(value) if value is not None and str(value) else None


def _next_day(day: str) -> str:
    return (_parse_day(day) + timedelta(days=1)).isoformat()


def _daily_incremental_idempotency_key(start_day: str, end_day: str) -> str:
    if start_day == end_day:
        return f"garmin-sidecar:daily:{start_day}"
    return f"garmin-sidecar:daily:{start_day}:{end_day}"


def _is_after_high_watermark(started_at: str, high_watermark: str | None) -> bool:
    if high_watermark is None:
        return True
    started = _parse_garmin_timestamp(started_at, "UTC")
    previous = _parse_garmin_timestamp(high_watermark, "UTC")
    if started is None or previous is None:
        return started_at > high_watermark
    return started > previous


def _pull_daily_monitoring_if_supported(
    garmin: GarminClient,
    *,
    calendar_date: str,
    consented_data_classes: Sequence[str],
) -> GarminDailyMonitoring | None:
    if not any(item in set(consented_data_classes) for item in DAILY_MONITORING_DATA_CLASSES):
        return None
    method = getattr(garmin, "pull_daily_monitoring", None)
    if method is None:
        return None
    return method(
        calendar_date=calendar_date,
        consented_data_classes=consented_data_classes,
    )


def _pull_activity_streams_if_supported(
    garmin: GarminClient,
    *,
    activity_id: str,
    consented_data_classes: Sequence[str],
) -> Mapping[str, Any]:
    if "gps" not in set(consented_data_classes):
        return {}
    method = getattr(garmin, "pull_activity_streams", None)
    if method is None:
        return {}
    return _as_mapping(
        method(
            activity_id=activity_id,
            consented_data_classes=consented_data_classes,
        )
    )


def _append_scalar_reading(
    readings: list[dict[str, Any]],
    *,
    source: str,
    external_id: str,
    metric_key: str,
    value: int | float | None,
    unit: str,
    at: Mapping[str, Any],
) -> None:
    if value is None:
        return
    readings.append(
        {
            "source": source,
            "externalId": external_id,
            "metricKey": metric_key,
            "value": {"value": value, "unit": unit},
            "at": dict(at),
        }
    )


def _timestamped_values_to_series(
    payload: Mapping[str, Any],
    *,
    external_id: str,
    series_type: str,
    source: str,
    timezone: str,
    anchor: Mapping[str, Any],
    value_keys: Sequence[str],
    value_unit: str,
    container_keys: Sequence[str],
) -> dict[str, Any] | None:
    values = _first_sequence(payload, container_keys)
    if values is None:
        return None
    return _samples_to_series(
        values,
        external_id=external_id,
        series_type=series_type,
        source=source,
        timezone=timezone,
        anchor=anchor,
        value_keys=value_keys,
        value_unit=value_unit,
    )


def _samples_to_series(
    samples: Sequence[Any],
    *,
    external_id: str,
    series_type: str,
    source: str,
    timezone: str,
    anchor: Mapping[str, Any],
    value_keys: Sequence[str],
    value_unit: str,
) -> dict[str, Any] | None:
    parsed: list[tuple[datetime, int | float]] = []
    for sample in samples:
        instant = _sample_timestamp(sample, timezone)
        value = _sample_number(sample, value_keys)
        if instant is None or value is None:
            continue
        parsed.append((instant, value))

    if not parsed:
        return None

    parsed.sort(key=lambda item: item[0])
    base = parsed[0][0]
    return {
        "source": source,
        "externalId": external_id,
        "type": series_type,
        "anchor": dict(anchor),
        "baseTime": _iso_utc(base),
        "timezone": timezone,
        "samples": [
            {
                "offsetSeconds": (instant - base).total_seconds(),
                "value": {"value": value, "unit": value_unit},
            }
            for instant, value in parsed
        ],
    }


def _samples_to_location_series(
    samples: Sequence[Any],
    *,
    external_id: str,
    source: str,
    timezone: str,
    anchor: Mapping[str, Any],
) -> dict[str, Any] | None:
    parsed: list[tuple[datetime, int | float, int | float]] = []
    for sample in samples:
        instant = _sample_timestamp(sample, timezone)
        latitude = _sample_number(
            sample,
            ("latitude", "lat", "directLatitude", "startLatitude"),
        )
        longitude = _sample_number(
            sample,
            ("longitude", "lon", "lng", "directLongitude", "startLongitude"),
        )
        if instant is None or latitude is None or longitude is None:
            continue
        parsed.append((instant, latitude, longitude))

    if not parsed:
        return None

    parsed.sort(key=lambda item: item[0])
    base = parsed[0][0]
    return {
        "source": source,
        "externalId": external_id,
        "type": "location",
        "anchor": dict(anchor),
        "baseTime": _iso_utc(base),
        "timezone": timezone,
        "samples": [
            {
                "offsetSeconds": (instant - base).total_seconds(),
                "value": {
                    "latitude": {"value": latitude, "unit": "degree"},
                    "longitude": {"value": longitude, "unit": "degree"},
                },
            }
            for instant, latitude, longitude in parsed
        ],
    }


def _activity_detail_samples(activity_streams: Mapping[str, Any]) -> Sequence[Any]:
    for key in ("activityDetailMetrics", "metrics", "samples"):
        value = activity_streams.get(key)
        if isinstance(value, Sequence) and not isinstance(value, (str, bytes, bytearray)):
            return value
    return []


def _sample_timestamp(sample: Any, timezone_name: str) -> datetime | None:
    if isinstance(sample, Mapping):
        for key in (
            "timestamp",
            "startTimeGMT",
            "startTimeGmt",
            "startTime",
            "dateTime",
            "calendarDateTime",
        ):
            parsed = _parse_garmin_timestamp(sample.get(key), timezone_name)
            if parsed is not None:
                return parsed
        return None

    if isinstance(sample, Sequence) and not isinstance(sample, (str, bytes, bytearray)):
        if not sample:
            return None
        return _parse_garmin_timestamp(sample[0], timezone_name)

    return None


def _sample_number(sample: Any, keys: Sequence[str]) -> int | float | None:
    if isinstance(sample, Mapping):
        return _first_number(sample, keys)

    if isinstance(sample, Sequence) and not isinstance(sample, (str, bytes, bytearray)):
        if len(sample) < 2:
            return None
        value = sample[1]
        if isinstance(value, bool):
            return None
        if isinstance(value, (int, float)):
            return value

    return None


def _parse_garmin_timestamp(value: Any, timezone_name: str) -> datetime | None:
    if isinstance(value, bool) or value is None:
        return None
    if isinstance(value, (int, float)):
        seconds = value / 1000 if value > 10_000_000_000 else value
        return datetime.fromtimestamp(seconds, tz=datetime_timezone.utc)
    if not isinstance(value, str) or value.strip() == "":
        return None

    raw = value.strip()
    normalized = raw.replace("Z", "+00:00")
    try:
        parsed = datetime.fromisoformat(normalized)
    except ValueError:
        return None

    if parsed.tzinfo is None:
        zone = ZoneInfo(timezone_name)
        if "GMT" in raw.upper() or raw.endswith("+00:00"):
            parsed = parsed.replace(tzinfo=datetime_timezone.utc)
        else:
            parsed = parsed.replace(tzinfo=zone)
    return parsed.astimezone(datetime_timezone.utc)


def _summary_started_at(
    summary: Mapping[str, Any],
    timezone_name: str,
) -> datetime | None:
    for key in (
        "startTimeGMT",
        "startTimeGmt",
        "startTimeUTC",
        "startTimeUtc",
        "startTimeLocal",
        "startTime",
        "beginTimestamp",
    ):
        parsed = _parse_garmin_timestamp(summary.get(key), timezone_name)
        if parsed is not None:
            return parsed
    return None


def _parse_day(value: str) -> date:
    return datetime.strptime(value, "%Y-%m-%d").date()


def _parse_optional_day(value: str | None) -> date | None:
    return None if value is None else _parse_day(value)


def _day_window_anchor(calendar_date: str, timezone_name: str) -> dict[str, Any]:
    day = datetime.strptime(calendar_date, "%Y-%m-%d").date()
    zone = ZoneInfo(timezone_name)
    started = datetime.combine(day, time.min, tzinfo=zone)
    ended = started + timedelta(days=1)
    return {
        "kind": "window",
        "startedAt": _iso_utc(started),
        "endedAt": _iso_utc(ended),
        "timezone": timezone_name,
    }


def _sleep_window_anchor(
    sleep: Mapping[str, Any],
    timezone_name: str,
) -> dict[str, Any] | None:
    candidates = (
        ("sleepStartTimestampGMT", "sleepEndTimestampGMT"),
        ("sleepStartTimestampGmt", "sleepEndTimestampGmt"),
        ("sleepStartTimestampLocal", "sleepEndTimestampLocal"),
        ("startTimeGMT", "endTimeGMT"),
        ("startTime", "endTime"),
    )
    dto = _as_mapping(sleep.get("dailySleepDTO"))
    for source in (sleep, dto):
        for start_key, end_key in candidates:
            started = _parse_garmin_timestamp(source.get(start_key), timezone_name)
            ended = _parse_garmin_timestamp(source.get(end_key), timezone_name)
            if started is not None and ended is not None and ended >= started:
                return {
                    "kind": "window",
                    "startedAt": _iso_utc(started),
                    "endedAt": _iso_utc(ended),
                    "timezone": timezone_name,
                }
    return None


def _window_duration_seconds(anchor: Mapping[str, Any]) -> int | None:
    if anchor.get("kind") != "window":
        return None
    started = _parse_garmin_timestamp(anchor.get("startedAt"), "UTC")
    ended = _parse_garmin_timestamp(anchor.get("endedAt"), "UTC")
    if started is None or ended is None:
        return None
    return int((ended - started).total_seconds())


def _iso_utc(value: datetime) -> str:
    return (
        value.astimezone(datetime_timezone.utc)
        .isoformat(timespec="milliseconds")
        .replace("+00:00", "Z")
    )


def _first_number_across(
    sources: Sequence[Mapping[str, Any]],
    keys: Sequence[str],
) -> int | float | None:
    for source in sources:
        value = _first_number(source, keys)
        if value is not None:
            return value
    return None


def _first_sequence(
    source: Mapping[str, Any],
    keys: Sequence[str],
) -> Sequence[Any] | None:
    for key in keys:
        value = source.get(key)
        if isinstance(value, Sequence) and not isinstance(value, (str, bytes, bytearray)):
            return value
    return None


def _first_mapping(items: Sequence[Mapping[str, Any]]) -> Mapping[str, Any]:
    return items[0] if items else {}


def _body_battery_value(
    body_battery: Sequence[Mapping[str, Any]],
) -> int | float | None:
    for item in body_battery:
        value = _first_number(item, ("bodyBattery", "bodyBatteryLevel", "value"))
        if value is not None:
            return value
        values = _first_sequence(
            item,
            ("bodyBatteryValuesArray", "bodyBatteryValues", "values"),
        )
        if values is None:
            continue
        for sample in reversed(list(values)):
            sample_value = _sample_number(
                sample,
                ("bodyBattery", "bodyBatteryLevel", "value"),
            )
            if sample_value is not None:
                return sample_value
    return None


def _dedupe_series(series: Sequence[Mapping[str, Any]]) -> list[dict[str, Any]]:
    by_key: dict[tuple[str, str], dict[str, Any]] = {}
    for item in series:
        source = str(item.get("source", ""))
        external_id = str(item.get("externalId", ""))
        by_key[(source, external_id)] = dict(item)
    return list(by_key.values())


def _metric_reading_data_class(reading: Mapping[str, Any]) -> str:
    key = str(reading.get("metricKey", "")).lower()
    units = _metric_value_units(reading.get("value"))
    if "heart" in key or key == "hrv" or "beatsperminute" in units:
        return "heartRate"
    if (
        "sleep" in key
        or "stress" in key
        or "wellness" in key
        or "recovery" in key
        or "battery" in key
    ):
        return "sleepWellness"
    if "gps" in key or "location" in key or "latitude" in key or "longitude" in key:
        return "gps"
    if "body" in key or "weight" in key or "mass" in key or "fat" in key:
        return "bodyComposition"
    return "activities"


def _series_data_class(series: Mapping[str, Any]) -> str:
    series_type = str(series.get("type", ""))
    if series_type == "heartRate":
        return "heartRate"
    if series_type == "location":
        return "gps"
    return "activities"


def _metric_value_units(value: Any) -> set[str]:
    if isinstance(value, Mapping):
        if isinstance(value.get("unit"), str):
            return {str(value["unit"]).lower()}
        units = set()
        for field_value in value.values():
            if isinstance(field_value, Mapping) and isinstance(field_value.get("unit"), str):
                units.add(str(field_value["unit"]).lower())
        return units
    return set()


def _integration_failure_report(
    error: BaseException, *, trigger: str
) -> dict[str, Any]:
    root = _root_cause(error)
    report: dict[str, Any] = {"source": "garmin", "trigger": trigger}

    if isinstance(error, GarminLoginError) or isinstance(root, GarminLoginError):
        return {
            **report,
            "condition": "reauth_required",
            "failureKind": "login",
        }

    prn_error = _find_error(error, PerenniaHttpError)
    if prn_error is not None:
        if prn_error.status_code == 429:
            return {
                **report,
                "condition": "rate_limited",
                "failureKind": "rate_limit",
                "retryAfterSeconds": _retry_after_seconds(prn_error)
                or DEFAULT_POLL_INTERVAL_SECONDS,
            }
        if prn_error.status_code in (401, 403):
            return {
                **report,
                "condition": "reauth_required",
                "failureKind": "token_expired",
            }
        if prn_error.status_code >= 500:
            return {
                **report,
                "condition": "temporary_failure",
                "failureKind": "server",
            }

    if isinstance(root, urllib.error.URLError):
        return {
            **report,
            "condition": "temporary_failure",
            "failureKind": "network",
        }

    return {
        **report,
        "condition": "temporary_failure",
        "failureKind": "unknown",
    }


def _report_integration_status_safely(
    status_client: IntegrationStatusClient | None,
    report: Mapping[str, Any],
) -> None:
    if status_client is None:
        return
    try:
        status_client.post_integration_status(report)
    except Exception as error:
        LOGGER.warning(
            "Garmin integration status report failed with %s.",
            type(error).__name__,
        )


def _sleep_seconds_for_tick(
    config: GarminSidecarConfig, tick: GarminCadenceTickResult
) -> int:
    return max(config.poll_interval_seconds, tick.retry_after_seconds or 0)


def _retry_after_seconds(error: BaseException) -> int | None:
    prn_error = _find_error(error, PerenniaHttpError)
    if prn_error is None:
        return None
    return prn_error.retry_after_seconds


def _retry_after_header(headers: Any) -> int | None:
    raw = headers.get("Retry-After") if headers is not None else None
    if raw is None:
        return None
    try:
        value = int(str(raw).strip())
    except ValueError:
        return None
    return value if value > 0 else None


def _find_error(error: BaseException, error_type: type[Any]) -> Any | None:
    current: BaseException | None = error
    while current is not None:
        if isinstance(current, error_type):
            return current
        current = current.__cause__
    return None


def _root_cause(error: BaseException) -> BaseException:
    current = error
    while current.__cause__ is not None:
        current = current.__cause__
    return current


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Sync Garmin history and incremental edge data as canonical imports to Perennia."
        )
    )
    parser.add_argument(
        "--config",
        help="Path to a self-hosted JSON config file. Environment variables are used when omitted.",
    )
    parser.add_argument(
        "--schedule",
        action="store_true",
        help="Poll forever on the configured self-host interval.",
    )
    parser.add_argument(
        "--manual-trigger",
        action="store_true",
        help="Run one immediate pull and import. This is also the default.",
    )
    parser.add_argument(
        "--max-ticks",
        type=int,
        help="Stop scheduled mode after this many ticks. Useful for smoke tests.",
    )
    args = parser.parse_args(argv)
    config = (
        GarminSidecarConfig.from_file(args.config)
        if args.config
        else GarminSidecarConfig.from_env()
    )
    if args.schedule:
        cadence = run_scheduled(config, max_ticks=args.max_ticks)
        print(
            json.dumps(
                {
                    "trigger": "scheduled",
                    "tickCount": cadence.tick_count,
                    "ticks": [_tick_output(tick) for tick in cadence.ticks],
                },
                sort_keys=True,
            )
        )
        return 0

    result = run_manual_trigger(config).sync
    print(
        json.dumps(
            {"trigger": "manual", **_sync_output(result)},
            sort_keys=True,
        )
    )
    return 0


def _tick_output(tick: GarminCadenceTickResult) -> dict[str, Any]:
    if tick.error is not None:
        output = {"ok": False, "error": tick.error}
        if tick.retry_after_seconds is not None:
            output["retryAfterSeconds"] = tick.retry_after_seconds
        return output
    return {"ok": True, **_sync_output(tick.sync)}


def _sync_output(result: Any) -> dict[str, Any]:
    batches = tuple(getattr(result, "batches", ()))
    return {
        "mode": getattr(result, "mode", None),
        "batchCount": len(batches),
        "idempotencyKeys": list(getattr(result, "batch_keys", [])),
        "accepted": all(batch.response.get("accepted") for batch in batches),
        "duplicates": [
            batch.idempotency_key
            for batch in batches
            if batch.response.get("duplicate")
        ],
    }


def _download_fit_bytes(client: Any, activity_id: str) -> bytes:
    download_format = getattr(
        getattr(client, "ActivityDownloadFormat", object()),
        "ORIGINAL",
        None,
    )
    if download_format is None:
        payload = client.download_activity(activity_id)
    else:
        payload = client.download_activity(activity_id, dl_fmt=download_format)

    if isinstance(payload, bytes):
        return payload
    if isinstance(payload, bytearray):
        return bytes(payload)
    if isinstance(payload, str):
        return Path(payload).read_bytes()
    if hasattr(payload, "read"):
        return payload.read()

    raise RuntimeError("Garmin FIT download did not return bytes or a file path.")


def _call_optional_garmin_method(
    client: Any,
    name: str,
    *args: Any,
    default: Any,
) -> Any:
    method = getattr(client, name, None)
    if method is None:
        return default
    result = method(*args)
    return default if result is None else result


def _as_mapping(value: Any) -> Mapping[str, Any]:
    return value if isinstance(value, Mapping) else {}


def _as_mapping_sequence(value: Any) -> Sequence[Mapping[str, Any]]:
    if isinstance(value, Mapping):
        return (value,)
    if not isinstance(value, Sequence) or isinstance(value, (str, bytes, bytearray)):
        return ()
    return tuple(item for item in value if isinstance(item, Mapping))


def _bool_value(value: Any, default: bool) -> bool:
    if value is None:
        return default
    if isinstance(value, bool):
        return value
    normalized = str(value).strip().lower()
    if normalized in {"1", "true", "yes", "on"}:
        return True
    if normalized in {"0", "false", "no", "off"}:
        return False
    raise ValueError(f"Expected a boolean value, got {value!r}.")


def _positive_int(value: Any, default: int) -> int:
    if value is None:
        return default
    parsed = int(value)
    if parsed < 1:
        raise ValueError(f"Expected a positive integer, got {value!r}.")
    return parsed


def _summary_activity_id(summary: Mapping[str, Any]) -> str | None:
    for key in ("activityId", "activity_id", "id"):
        value = summary.get(key)
        if value is not None and str(value):
            return str(value)
    return None


def _summary_activity_type(summary: Mapping[str, Any]) -> str | None:
    for key in ("activityType", "activityTypeDTO", "activity_type"):
        value = summary.get(key)
        if isinstance(value, Mapping):
            for nested_key in ("typeKey", "type_key", "key"):
                nested = value.get(nested_key)
                if nested is not None and str(nested):
                    return str(nested)
        elif value is not None and str(value):
            return str(value)
    return None


def _summary_dimensions(summary: Mapping[str, Any]) -> dict[str, Any]:
    dimensions: dict[str, Any] = {}
    distance = _first_number(summary, ("distance", "distanceMeters", "distance_meters"))
    if distance is not None:
        dimensions["distance"] = {"value": distance, "unit": "meter"}
    duration = _first_number(summary, ("duration", "elapsedDuration", "movingDuration"))
    if duration is not None:
        dimensions["duration"] = {"value": duration, "unit": "second"}
    return dimensions


def _merge_summary_metrics(
    *,
    existing: Sequence[Mapping[str, Any]],
    summary: Mapping[str, Any],
    source: str,
    external_id: str,
    started_at: str,
    ended_at: str,
    timezone: str,
) -> list[dict[str, Any]]:
    by_key = {str(metric["metricKey"]): dict(metric) for metric in existing}
    at = {
        "kind": "window",
        "startedAt": started_at,
        "endedAt": ended_at,
        "timezone": timezone,
    }
    candidates = (
        ("averageHeartRate", ("averageHR", "averageHeartRate"), "beatsPerMinute"),
        ("maxHeartRate", ("maxHR", "maxHeartRate"), "beatsPerMinute"),
        ("activeKilocalories", ("calories", "activeKilocalories"), "kilocalorie"),
        (
            "averageCadence",
            ("averageCadence", "averageRunningCadenceInStepsPerMinute"),
            "revolutionsPerMinute",
        ),
        (
            "maxCadence",
            ("maxCadence", "maxRunningCadenceInStepsPerMinute"),
            "revolutionsPerMinute",
        ),
    )
    for metric_key, keys, unit in candidates:
        value = _first_number(summary, keys)
        if value is None:
            continue
        by_key[metric_key] = {
            "source": source,
            "externalId": f"{external_id}:summary:{metric_key}",
            "metricKey": metric_key,
            "value": {"value": value, "unit": unit},
            "at": at,
        }

    for metric in by_key.values():
        if str(metric.get("externalId", "")).startswith("fit:"):
            metric["externalId"] = f"{external_id}:summary:{metric['metricKey']}"
        metric["source"] = source

    return list(by_key.values())


def _first_number(summary: Mapping[str, Any], keys: Sequence[str]) -> int | float | None:
    for key in keys:
        value = summary.get(key)
        if isinstance(value, bool):
            continue
        if isinstance(value, (int, float)):
            return value
    return None


def _first_activity(batch: Mapping[str, Any]) -> dict[str, Any]:
    activities = batch.get("activities")
    if not isinstance(activities, list) or not activities:
        raise RuntimeError("Canonical FIT mapper did not emit an activity.")
    activity = activities[0]
    if not isinstance(activity, dict):
        raise RuntimeError("Canonical FIT mapper emitted a non-object activity.")
    return activity


def _replace_external_id(
    value: str,
    old_external_id: str,
    new_external_id: str,
    fallback_suffix: str,
) -> str:
    if value.startswith(old_external_id):
        return f"{new_external_id}{value[len(old_external_id):]}"
    return f"{new_external_id}{fallback_suffix}"


def _required(source: Mapping[str, Any], key: str) -> str:
    value = source.get(key)
    if value is None or str(value) == "":
        raise ValueError(f"{key} is required.")
    return str(value)


def _csv_tuple(value: str | None, default: Sequence[str]) -> tuple[str, ...]:
    if value is None or value.strip() == "":
        return tuple(default)
    return tuple(item.strip() for item in value.split(",") if item.strip())


def _redact_email(value: str) -> str:
    if "@" not in value:
        return "<redacted>"
    local, domain = value.split("@", 1)
    return f"{local[:1]}***@{domain}"


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


if __name__ == "__main__":
    sys.exit(main())
