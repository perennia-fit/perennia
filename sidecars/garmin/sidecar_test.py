import dataclasses
import json
import subprocess
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from sidecars.garmin.sidecar import (
    CANONICAL_IMPORT_PATH,
    GarminActivity,
    GarminDailyMonitoring,
    PerenniaHttpError,
    GarminSidecarConfig,
    NodeFitMapper,
    PerenniaImportClient,
    canonical_batch_with_garmin_summary,
    filter_canonical_batch_by_consent,
    garmin_activity_streams_to_canonical_series,
    garmin_daily_monitoring_to_canonical,
    run_manual_trigger,
    run_once,
    run_scheduled,
    run_sync,
)


class GarminSidecarTest(unittest.TestCase):
    def test_stubbed_garmin_pull_maps_and_posts_canonical_batch(self):
        garmin = StubGarminClient()
        mapper = StubMapper()
        perennia = RecordingImportClient()
        config = GarminSidecarConfig(
            garmin_email="athlete@example.test",
            garmin_password="garmin-secret",
            prn_base_url="https://perennia.example.test",
            prn_integration_token="perennia-secret",
            timezone="Australia/Brisbane",
            consented_data_classes=("activities", "heartRate", "gps"),
        )

        result = run_once(
            config,
            garmin_client=garmin,
            fit_mapper=mapper,
            import_client=perennia,
        )

        self.assertTrue(garmin.logged_in)
        self.assertEqual(mapper.calls, [(b"fit-bytes", "Australia/Brisbane")])
        self.assertEqual(result.activity_external_id, "garmin-activity-42")
        self.assertEqual(result.idempotency_key, "garmin-sidecar:garmin-activity-42")
        self.assertEqual(
            perennia.requests[0]["idempotency_key"],
            "garmin-sidecar:garmin-activity-42",
        )
        posted = perennia.requests[0]["canonical"]
        activity = posted["activities"][0]
        self.assertEqual(activity["externalId"], "garmin-activity-42")
        self.assertEqual(activity["activityType"], "strength_training")
        self.assertEqual(activity["summary"]["distance"], {"value": 5000, "unit": "meter"})
        self.assertEqual(activity["summary"]["duration"], {"value": 1800, "unit": "second"})
        self.assertEqual(activity["sets"][0]["externalId"], "garmin-activity-42:set:1")
        self.assertEqual(
            posted["series"][0]["anchor"],
            {
                "kind": "activity",
                "source": "garmin",
                "externalId": "garmin-activity-42",
            },
        )
        self.assertEqual(posted["series"][0]["externalId"], "garmin-activity-42:series:heartRate")
        self.assertEqual(posted["consentedDataClasses"], ["activities", "heartRate", "gps"])
        self.assertEqual(result.response["accepted"], True)

    def test_daily_monitoring_maps_to_canonical_readings_and_series(self):
        mapped = garmin_daily_monitoring_to_canonical(
            daily_monitoring(),
            timezone="Australia/Brisbane",
            consented_data_classes=("activities", "heartRate", "sleepWellness"),
        )

        readings = {
            reading["metricKey"]: reading
            for reading in mapped["metricReadings"]
        }
        self.assertEqual(
            readings["restingHeartRate"]["value"],
            {"value": 48, "unit": "beatsPerMinute"},
        )
        self.assertEqual(
            readings["sleepDuration"]["value"],
            {"value": 27000, "unit": "second"},
        )
        self.assertEqual(readings["hrv"]["value"], {"value": 62, "unit": "millisecond"})
        self.assertEqual(
            readings["averageStress"]["value"],
            {"value": 21, "unit": "score"},
        )
        self.assertEqual(
            readings["bodyBattery"]["value"],
            {"value": 77, "unit": "score"},
        )
        self.assertEqual(readings["steps"]["value"], {"value": 12345, "unit": "count"})
        self.assertEqual(
            readings["activeKilocalories"]["value"],
            {"value": 640, "unit": "kilocalorie"},
        )
        self.assertEqual(
            readings["sleepDuration"]["at"],
            {
                "kind": "window",
                "startedAt": "2026-06-23T12:30:00.000Z",
                "endedAt": "2026-06-23T20:00:00.000Z",
                "timezone": "Australia/Brisbane",
            },
        )
        self.assertEqual(len(mapped["series"]), 1)
        self.assertEqual(mapped["series"][0]["type"], "heartRate")
        self.assertEqual(mapped["series"][0]["anchor"]["kind"], "timeWindow")
        self.assertEqual(
            mapped["series"][0]["samples"],
            [
                {
                    "offsetSeconds": 0.0,
                    "value": {"value": 49, "unit": "beatsPerMinute"},
                },
                {
                    "offsetSeconds": 300.0,
                    "value": {"value": 55, "unit": "beatsPerMinute"},
                },
            ],
        )

    def test_run_once_pulls_daily_monitoring_and_posts_consent_filtered_batch(self):
        garmin = StubMonitoringGarminClient()
        mapper = StubMapper()
        perennia = RecordingImportClient()
        config = GarminSidecarConfig(
            garmin_email="athlete@example.test",
            garmin_password="garmin-secret",
            prn_base_url="https://perennia.example.test",
            prn_integration_token="perennia-secret",
            timezone="Australia/Brisbane",
            consented_data_classes=("activities", "heartRate", "sleepWellness"),
            monitoring_date="2026-06-24",
        )

        result = run_once(
            config,
            garmin_client=garmin,
            fit_mapper=mapper,
            import_client=perennia,
        )

        self.assertEqual(result.activity_external_id, "garmin-activity-42")
        self.assertEqual(
            garmin.daily_monitoring_calls,
            [("2026-06-24", ("activities", "heartRate", "sleepWellness"))],
        )
        self.assertEqual(garmin.activity_stream_calls, [])
        posted = perennia.requests[0]["canonical"]
        self.assertEqual(posted["consentedDataClasses"], ["activities", "heartRate", "sleepWellness"])
        self.assertEqual(
            sorted(reading["metricKey"] for reading in posted["metricReadings"]),
            [
                "activeKilocalories",
                "averageStress",
                "bodyBattery",
                "hrv",
                "restingHeartRate",
                "sleepDuration",
                "steps",
            ],
        )
        self.assertEqual(
            [series["type"] for series in posted["series"]],
            ["heartRate", "heartRate"],
        )
        self.assertEqual(
            any(series["type"] == "location" for series in posted["series"]),
            False,
        )

    def test_run_once_never_pulls_unconsented_daily_classes_or_gps_details(self):
        garmin = StubMonitoringGarminClient()
        mapper = StubMapper()
        perennia = RecordingImportClient()
        config = GarminSidecarConfig(
            garmin_email="athlete@example.test",
            garmin_password="garmin-secret",
            prn_base_url="https://perennia.example.test",
            prn_integration_token="perennia-secret",
            timezone="Australia/Brisbane",
            consented_data_classes=("activities",),
            monitoring_date="2026-06-24",
        )

        run_once(config, garmin_client=garmin, fit_mapper=mapper, import_client=perennia)

        self.assertEqual(
            garmin.daily_monitoring_calls,
            [("2026-06-24", ("activities",))],
        )
        self.assertEqual(garmin.activity_stream_calls, [])
        posted = perennia.requests[0]["canonical"]
        self.assertEqual(posted["metricReadings"][0]["metricKey"], "steps")
        self.assertEqual(
            [reading["metricKey"] for reading in posted["metricReadings"]],
            ["steps", "activeKilocalories"],
        )
        self.assertEqual(posted["series"], [])

    def test_activity_streams_map_to_hr_and_location_series_when_consented(self):
        series = garmin_activity_streams_to_canonical_series(
            {
                "activityDetailMetrics": [
                    {
                        "startTimeGMT": "2026-06-23T20:00:00.000Z",
                        "heartRate": 121,
                        "latitude": -27.4698,
                        "longitude": 153.0251,
                    },
                    {
                        "startTimeGMT": "2026-06-23T20:00:05.000Z",
                        "heartRate": 123,
                        "latitude": -27.4699,
                        "longitude": 153.0252,
                    },
                ]
            },
            activity_external_id="garmin-activity-42",
            source="garmin",
            timezone="Australia/Brisbane",
            consented_data_classes=("activities", "heartRate", "gps"),
        )

        self.assertEqual([item["type"] for item in series], ["heartRate", "location"])
        self.assertEqual(series[0]["anchor"]["externalId"], "garmin-activity-42")
        self.assertEqual(
            series[1]["samples"][0]["value"],
            {
                "latitude": {"value": -27.4698, "unit": "degree"},
                "longitude": {"value": 153.0251, "unit": "degree"},
            },
        )

    def test_monitoring_filter_keeps_data_out_of_training_fields(self):
        batch = {
            "activities": [
                {
                    **canonical_batch()["activities"][0],
                    "summaryMetrics": [
                        {
                            "source": "garmin",
                            "externalId": "activity-1:gps",
                            "metricKey": "gpsLatitude",
                            "value": {"value": -27.4698, "unit": "degree"},
                            "at": {
                                "kind": "instant",
                                "at": "2026-06-23T20:00:00.000Z",
                                "timezone": "Australia/Brisbane",
                            },
                        }
                    ],
                }
            ],
            "metricReadings": daily_monitoring_batch()["metricReadings"],
            "series": [
                *canonical_batch()["series"],
                {
                    "source": "garmin",
                    "externalId": "activity-1:series:location",
                    "type": "location",
                    "anchor": {
                        "kind": "activity",
                        "source": "garmin",
                        "externalId": "activity-1",
                    },
                    "baseTime": "2026-06-23T20:00:00.000Z",
                    "timezone": "Australia/Brisbane",
                    "samples": [
                        {
                            "offsetSeconds": 0,
                            "value": {
                                "latitude": {"value": -27.4698, "unit": "degree"},
                                "longitude": {"value": 153.0251, "unit": "degree"},
                            },
                        }
                    ],
                },
            ],
        }

        filtered = filter_canonical_batch_by_consent(
            batch,
            ("activities", "heartRate", "sleepWellness"),
        )

        activity = filtered["activities"][0]
        self.assertEqual(activity["summaryMetrics"], [])
        self.assertEqual(
            activity["sets"][0]["dimensions"],
            {
                "load": {"value": 100, "unit": "kilogram"},
                "reps": {"value": 5, "unit": "repetition"},
            },
        )
        self.assertEqual(
            all("dimensions" not in reading for reading in filtered["metricReadings"]),
            True,
        )
        self.assertEqual(
            any(series["type"] == "location" for series in filtered["series"]),
            False,
        )

    def test_retry_uses_same_activity_idempotency_key(self):
        garmin = StubGarminClient()
        mapper = StubMapper()
        perennia = RecordingImportClient()
        config = GarminSidecarConfig(
            garmin_email="athlete@example.test",
            garmin_password="garmin-secret",
            prn_base_url="https://perennia.example.test",
            prn_integration_token="perennia-secret",
        )

        first = run_once(config, garmin_client=garmin, fit_mapper=mapper, import_client=perennia)
        second = run_once(config, garmin_client=garmin, fit_mapper=mapper, import_client=perennia)

        self.assertEqual(first.idempotency_key, second.idempotency_key)
        self.assertEqual(
            [request["idempotency_key"] for request in perennia.requests],
            [
                "garmin-sidecar:garmin-activity-42",
                "garmin-sidecar:garmin-activity-42",
            ],
        )

    def test_config_reads_edge_credentials_and_redacts_safe_summary(self):
        config = GarminSidecarConfig.from_env(
            {
                "GARMIN_EMAIL": "athlete@example.test",
                "GARMIN_PASSWORD": "garmin-secret",
                "PRN_BASE_URL": "https://perennia.example.test",
                "PRN_INTEGRATION_TOKEN": "perennia-secret",
                "PRN_TIMEZONE": "Australia/Brisbane",
                "PRN_CONSENTED_DATA_CLASSES": "activities,heartRate",
                "PRN_BACKFILL_FORCE": "true",
                "PRN_BACKFILL_START_DATE": "2026-01-01",
                "PRN_BACKFILL_END_DATE": "2026-06-24",
                "PRN_BACKFILL_ACTIVITY_CHUNK_SIZE": "25",
                "PRN_BACKFILL_MONITORING_CHUNK_DAYS": "3",
                "PRN_POLL_INTERVAL_SECONDS": "900",
                "PRN_STATE_PATH": "sidecars/garmin/local.state.json",
            }
        )

        self.assertEqual(config.garmin_email, "athlete@example.test")
        self.assertEqual(config.garmin_password, "garmin-secret")
        self.assertEqual(config.prn_integration_token, "perennia-secret")
        self.assertEqual(config.consented_data_classes, ("activities", "heartRate"))
        self.assertEqual(config.backfill_enabled, True)
        self.assertEqual(config.backfill_force, True)
        self.assertEqual(config.backfill_start_date, "2026-01-01")
        self.assertEqual(config.backfill_end_date, "2026-06-24")
        self.assertEqual(config.backfill_activity_chunk_size, 25)
        self.assertEqual(config.backfill_monitoring_chunk_days, 3)
        self.assertEqual(config.poll_interval_seconds, 900)
        self.assertEqual(config.state_path, "sidecars/garmin/local.state.json")
        safe = config.safe_summary()
        self.assertNotIn("garmin-secret", json.dumps(safe))
        self.assertNotIn("perennia-secret", json.dumps(safe))
        self.assertEqual(safe["garmin_email"], "a***@example.test")

    def test_owl_client_posts_only_to_canonical_import_with_bearer_credential(self):
        received = []

        class Handler(BaseHTTPRequestHandler):
            def do_POST(self):
                length = int(self.headers["Content-Length"])
                received.append(
                    {
                        "path": self.path,
                        "authorization": self.headers["Authorization"],
                        "body": json.loads(self.rfile.read(length).decode("utf-8")),
                    }
                )
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(b'{"accepted":true,"duplicate":false}')

            def log_message(self, _format, *args):
                return

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            client = PerenniaImportClient(
                base_url=f"http://127.0.0.1:{server.server_port}",
                integration_token="perennia-import-token",
            )
            response = client.post_canonical_import(
                idempotency_key="batch-1",
                canonical={
                    "activities": [{"source": "garmin"}],
                    "metricReadings": [],
                    "series": [],
                    "consentedDataClasses": ["activities"],
                },
            )
        finally:
            server.shutdown()
            server.server_close()

        self.assertEqual(response["accepted"], True)
        self.assertEqual(received[0]["path"], CANONICAL_IMPORT_PATH)
        self.assertEqual(received[0]["authorization"], "Bearer perennia-import-token")
        self.assertEqual(received[0]["body"]["idempotencyKey"], "batch-1")
        self.assertEqual(received[0]["body"]["activities"], [{"source": "garmin"}])

    def test_node_fit_mapper_invokes_slice_one_bridge(self):
        def runner(command, *, input, stdout, stderr, cwd, check):
            self.assertIn("fit_mapper_bridge.mjs", command[-3])
            self.assertEqual(command[-2:], ["--timezone", "Australia/Brisbane"])
            self.assertEqual(input, b"fit-bytes")
            self.assertFalse(check)
            return subprocess.CompletedProcess(
                command,
                0,
                stdout=json.dumps({"activities": [], "metricReadings": [], "series": []}).encode(
                    "utf-8"
                ),
                stderr=b"",
            )

        mapper = NodeFitMapper(command=("node", "fit_mapper_bridge.mjs"), runner=runner)
        self.assertEqual(
            mapper.map_fit(b"fit-bytes", timezone="Australia/Brisbane"),
            {"activities": [], "metricReadings": [], "series": []},
        )

    def test_summary_merge_preserves_fit_mapper_when_garmin_summary_is_sparse(self):
        merged = canonical_batch_with_garmin_summary(
            canonical_batch(),
            summary={"activityId": "garmin-activity-42"},
            fallback_activity_id="fallback",
            consented_data_classes=["activities"],
        )

        activity = merged["activities"][0]
        self.assertEqual(activity["externalId"], "garmin-activity-42")
        self.assertEqual(activity["activityType"], "strength_training")
        self.assertEqual(activity["summary"]["duration"], {"value": 1800, "unit": "second"})

    def test_summary_merge_uses_pulled_activity_id_when_summary_has_no_id(self):
        merged = canonical_batch_with_garmin_summary(
            canonical_batch(),
            summary={},
            fallback_activity_id="pulled-activity-99",
            consented_data_classes=["activities"],
        )

        activity = merged["activities"][0]
        self.assertEqual(activity["externalId"], "pulled-activity-99")
        self.assertEqual(activity["sets"][0]["externalId"], "pulled-activity-99:set:1")
        self.assertEqual(
            merged["series"][0]["anchor"]["externalId"],
            "pulled-activity-99",
        )

    def test_run_sync_backfills_history_as_bounded_idempotent_chunks(self):
        with tempfile.TemporaryDirectory() as directory:
            state_path = Path(directory) / "garmin-state.json"
            garmin = StubBackfillGarminClient()
            mapper = StubMapper()
            perennia = RecordingImportClient()

            result = run_sync(
                backfill_config(state_path),
                garmin_client=garmin,
                fit_mapper=mapper,
                import_client=perennia,
            )

            self.assertEqual(result.mode, "backfill")
            self.assertTrue(garmin.logged_in)
            self.assertEqual(
                garmin.activity_range_calls,
                [("2026-06-21", "2026-06-24", 2)],
            )
            self.assertEqual(
                [request["idempotency_key"] for request in perennia.requests],
                [
                    "garmin-sidecar:backfill:activities:2026-06-21:2026-06-24:0001",
                    "garmin-sidecar:backfill:activities:2026-06-21:2026-06-24:0002",
                    "garmin-sidecar:backfill:daily:2026-06-21:2026-06-22",
                    "garmin-sidecar:backfill:daily:2026-06-23:2026-06-24",
                ],
            )
            activity_counts = [
                len(request["canonical"]["activities"])
                for request in perennia.requests[:2]
            ]
            self.assertEqual(activity_counts, [2, 1])
            self.assertEqual(
                [
                    activity["externalId"]
                    for activity in perennia.requests[0]["canonical"]["activities"]
                ],
                ["garmin-activity-3", "garmin-activity-2"],
            )
            self.assertEqual(
                [call[0] for call in garmin.daily_monitoring_calls],
                ["2026-06-21", "2026-06-22", "2026-06-23", "2026-06-24"],
            )
            self.assertEqual(
                result.batch_keys,
                [request["idempotency_key"] for request in perennia.requests],
            )

            state = json.loads(state_path.read_text(encoding="utf-8"))
            self.assertEqual(state["backfillCompleted"], True)
            self.assertEqual(state["lastMonitoringDate"], "2026-06-24")
            self.assertEqual(
                state["lastActivityStartedAt"],
                "2026-06-24T20:00:00.000Z",
            )

    def test_run_sync_replays_backfill_chunks_after_mid_backfill_restart(self):
        with tempfile.TemporaryDirectory() as directory:
            state_path = Path(directory) / "garmin-state.json"
            first_owl = FailingImportClient(fail_on_call=2)

            with self.assertRaisesRegex(RuntimeError, "simulated import failure"):
                run_sync(
                    backfill_config(state_path),
                    garmin_client=StubBackfillGarminClient(),
                    fit_mapper=StubMapper(),
                    import_client=first_owl,
                )

            self.assertEqual(
                first_owl.requests[0]["idempotency_key"],
                "garmin-sidecar:backfill:activities:2026-06-21:2026-06-24:0001",
            )
            if state_path.exists():
                self.assertNotEqual(
                    json.loads(state_path.read_text(encoding="utf-8")).get(
                        "backfillCompleted"
                    ),
                    True,
                )

            retry_owl = RecordingImportClient(
                duplicate_keys={
                    "garmin-sidecar:backfill:activities:2026-06-21:2026-06-24:0001"
                }
            )
            result = run_sync(
                backfill_config(state_path),
                garmin_client=StubBackfillGarminClient(),
                fit_mapper=StubMapper(),
                import_client=retry_owl,
            )

            self.assertEqual(result.mode, "backfill")
            self.assertEqual(
                [request["idempotency_key"] for request in retry_owl.requests],
                [
                    "garmin-sidecar:backfill:activities:2026-06-21:2026-06-24:0001",
                    "garmin-sidecar:backfill:activities:2026-06-21:2026-06-24:0002",
                    "garmin-sidecar:backfill:daily:2026-06-21:2026-06-22",
                    "garmin-sidecar:backfill:daily:2026-06-23:2026-06-24",
                ],
            )
            self.assertEqual(result.responses[0]["duplicate"], True)
            self.assertEqual(
                json.loads(state_path.read_text(encoding="utf-8"))[
                    "backfillCompleted"
                ],
                True,
            )

    def test_run_sync_forced_full_rerun_uses_same_chunk_keys_as_duplicates(self):
        with tempfile.TemporaryDirectory() as directory:
            state_path = Path(directory) / "garmin-state.json"
            config = backfill_config(state_path)
            first_owl = RecordingImportClient()
            first = run_sync(
                config,
                garmin_client=StubBackfillGarminClient(),
                fit_mapper=StubMapper(),
                import_client=first_owl,
            )

            rerun_owl = RecordingImportClient(duplicate_keys=set(first.batch_keys))
            rerun = run_sync(
                dataclasses.replace(config, backfill_force=True),
                garmin_client=StubBackfillGarminClient(),
                fit_mapper=StubMapper(),
                import_client=rerun_owl,
            )

            self.assertEqual(rerun.mode, "backfill")
            self.assertEqual(rerun.batch_keys, first.batch_keys)
            self.assertEqual(
                [response["duplicate"] for response in rerun.responses],
                [True, True, True, True],
            )

    def test_run_sync_switches_to_incremental_after_backfill_completion(self):
        with tempfile.TemporaryDirectory() as directory:
            state_path = Path(directory) / "garmin-state.json"
            config = backfill_config(state_path)
            run_sync(
                config,
                garmin_client=StubBackfillGarminClient(),
                fit_mapper=StubMapper(),
                import_client=RecordingImportClient(),
            )

            garmin = StubBackfillGarminClient(
                activities=[
                    backfill_activity(
                        "garmin-activity-new",
                        "2026-06-25T20:00:00.000Z",
                    ),
                    backfill_activity(
                        "garmin-activity-3",
                        "2026-06-24T20:00:00.000Z",
                    ),
                ]
            )
            perennia = RecordingImportClient()
            incremental = run_sync(
                dataclasses.replace(config, monitoring_date="2026-06-25"),
                garmin_client=garmin,
                fit_mapper=StubMapper(),
                import_client=perennia,
            )

            self.assertEqual(incremental.mode, "incremental")
            self.assertEqual(
                garmin.activity_range_calls,
                [("2026-06-24", "2026-06-25", 2)],
            )
            self.assertEqual(
                [request["idempotency_key"] for request in perennia.requests],
                [
                    "garmin-sidecar:garmin-activity-new",
                    "garmin-sidecar:daily:2026-06-25",
                ],
            )
            self.assertEqual(
                perennia.requests[0]["canonical"]["activities"][0]["externalId"],
                "garmin-activity-new",
            )
            self.assertEqual(
                json.loads(state_path.read_text(encoding="utf-8"))[
                    "lastActivityStartedAt"
                ],
                "2026-06-25T20:00:00.000Z",
            )

    def test_run_scheduled_polls_on_self_host_interval(self):
        calls = []
        sleeps = []
        config = GarminSidecarConfig(
            garmin_email="athlete@example.test",
            garmin_password="garmin-secret",
            prn_base_url="https://perennia.example.test",
            prn_integration_token="perennia-secret",
            poll_interval_seconds=300,
        )

        result = run_scheduled(
            config,
            runner=lambda scheduled_config: calls.append(scheduled_config)
            or GarminSyncResultStub("incremental", ["batch-1"]),
            sleeper=sleeps.append,
            max_ticks=3,
        )

        self.assertEqual(calls, [config, config, config])
        self.assertEqual(sleeps, [300, 300])
        self.assertEqual(result.tick_count, 3)
        self.assertEqual([tick.trigger for tick in result.ticks], ["scheduled"] * 3)
        self.assertEqual(result.ticks[0].sync.batch_keys, ["batch-1"])

    def test_run_scheduled_records_tick_failure_and_keeps_polling(self):
        calls = []
        sleeps = []
        config = GarminSidecarConfig(
            garmin_email="athlete@example.test",
            garmin_password="garmin-secret",
            prn_base_url="https://perennia.example.test",
            prn_integration_token="perennia-secret",
            poll_interval_seconds=300,
        )

        def runner(scheduled_config):
            calls.append(scheduled_config)
            if len(calls) == 2:
                raise RuntimeError("transient failure for garmin-secret")
            return GarminSyncResultStub("incremental", [f"batch-{len(calls)}"])

        with self.assertLogs("sidecars.garmin.sidecar", level="WARNING") as logs:
            result = run_scheduled(
                config,
                runner=runner,
                sleeper=sleeps.append,
                max_ticks=3,
            )

        self.assertEqual(calls, [config, config, config])
        self.assertEqual(sleeps, [300, 300])
        self.assertEqual(result.tick_count, 3)
        self.assertEqual(result.ticks[0].sync.batch_keys, ["batch-1"])
        self.assertIsNone(result.ticks[0].error)
        self.assertIsNone(result.ticks[1].sync)
        self.assertEqual(result.ticks[1].error, "RuntimeError")
        self.assertEqual(result.ticks[2].sync.batch_keys, ["batch-3"])
        self.assertNotIn("garmin-secret", " ".join(logs.output))

    def test_run_scheduled_rate_limit_failure_backs_off_next_tick(self):
        sleeps = []
        config = GarminSidecarConfig(
            garmin_email="athlete@example.test",
            garmin_password="garmin-secret",
            prn_base_url="https://perennia.example.test",
            prn_integration_token="perennia-secret",
            poll_interval_seconds=300,
        )

        result = run_scheduled(
            config,
            runner=lambda _: (_ for _ in ()).throw(
                PerenniaHttpError(status_code=429, retry_after_seconds=900)
            ),
            sleeper=sleeps.append,
            max_ticks=2,
        )

        self.assertEqual(sleeps, [900])
        self.assertEqual(result.tick_count, 2)
        self.assertEqual(result.ticks[0].error, "PerenniaHttpError")
        self.assertEqual(result.ticks[0].retry_after_seconds, 900)

    def test_run_sync_reports_login_failure_without_importing_domain_payloads(self):
        status = RecordingStatusClient()
        perennia = RecordingImportClient()
        config = GarminSidecarConfig(
            garmin_email="athlete@example.test",
            garmin_password="garmin-secret",
            prn_base_url="https://perennia.example.test",
            prn_integration_token="perennia-secret",
            poll_interval_seconds=300,
        )

        with self.assertRaisesRegex(RuntimeError, "Garmin login failed"):
            run_sync(
                config,
                garmin_client=FailingLoginGarminClient(),
                fit_mapper=StubMapper(),
                import_client=perennia,
                status_client=status,
                trigger="scheduled",
            )

        self.assertEqual(perennia.requests, [])
        self.assertEqual(status.reports, [
            {
                "source": "garmin",
                "condition": "reauth_required",
                "failureKind": "login",
                "trigger": "scheduled",
            }
        ])
        self.assertNotIn("garmin-secret", json.dumps(status.reports))
        self.assertNotIn("activity", json.dumps(status.reports).lower())

    def test_run_sync_reports_rate_limit_backoff_without_payloads(self):
        status = RecordingStatusClient()
        config = GarminSidecarConfig(
            garmin_email="athlete@example.test",
            garmin_password="garmin-secret",
            prn_base_url="https://perennia.example.test",
            prn_integration_token="perennia-secret",
            backfill_enabled=False,
            state_path=None,
        )

        with self.assertRaises(PerenniaHttpError):
            run_sync(
                config,
                garmin_client=StubBackfillGarminClient(),
                fit_mapper=StubMapper(),
                import_client=RateLimitedImportClient(),
                status_client=status,
                trigger="scheduled",
            )

        self.assertEqual(status.reports, [
            {
                "source": "garmin",
                "condition": "rate_limited",
                "failureKind": "rate_limit",
                "trigger": "scheduled",
                "retryAfterSeconds": 120,
            }
        ])
        self.assertNotIn("fit-bytes", json.dumps(status.reports))
        self.assertNotIn("garmin-activity-42", json.dumps(status.reports))

    def test_run_sync_reports_success_as_status_metadata(self):
        status = RecordingStatusClient()
        config = GarminSidecarConfig(
            garmin_email="athlete@example.test",
            garmin_password="garmin-secret",
            prn_base_url="https://perennia.example.test",
            prn_integration_token="perennia-secret",
            backfill_enabled=False,
            state_path=None,
        )

        result = run_sync(
            config,
            garmin_client=StubBackfillGarminClient(),
            fit_mapper=StubMapper(),
            import_client=RecordingImportClient(),
            status_client=status,
            trigger="manual",
        )

        self.assertEqual(result.mode, "incremental")
        self.assertEqual(status.reports, [
            {
                "source": "garmin",
                "condition": "ok",
                "trigger": "manual",
            }
        ])

    def test_manual_trigger_forces_immediate_pull_without_sleeping(self):
        calls = []
        config = GarminSidecarConfig(
            garmin_email="athlete@example.test",
            garmin_password="garmin-secret",
            prn_base_url="https://perennia.example.test",
            prn_integration_token="perennia-secret",
            poll_interval_seconds=300,
        )

        result = run_manual_trigger(
            config,
            runner=lambda manual_config: calls.append(manual_config)
            or GarminSyncResultStub("incremental", ["manual-batch"]),
        )

        self.assertEqual(calls, [config])
        self.assertEqual(result.trigger, "manual")
        self.assertEqual(result.sync.batch_keys, ["manual-batch"])


class StubGarminClient:
    def __init__(self):
        self.logged_in = False

    def login(self):
        self.logged_in = True

    def pull_latest_activity(self):
        return GarminActivity(
            activity_id="garmin-activity-42",
            summary={
                "activityId": "garmin-activity-42",
                "activityType": {"typeKey": "strength_training"},
                "distance": 5000,
                "duration": 1800,
                "averageHR": 132,
                "maxHR": 166,
                "calories": 410,
            },
            fit_bytes=b"fit-bytes",
        )


class StubMonitoringGarminClient(StubGarminClient):
    def __init__(self):
        super().__init__()
        self.daily_monitoring_calls = []
        self.activity_stream_calls = []

    def pull_daily_monitoring(self, *, calendar_date, consented_data_classes):
        self.daily_monitoring_calls.append(
            (calendar_date, tuple(consented_data_classes))
        )
        return daily_monitoring(calendar_date)

    def pull_activity_streams(self, *, activity_id, consented_data_classes):
        self.activity_stream_calls.append(
            (activity_id, tuple(consented_data_classes))
        )
        return {
            "activityDetailMetrics": [
                {
                    "startTimeGMT": "2026-06-23T20:00:00.000Z",
                    "heartRate": 121,
                    "latitude": -27.4698,
                    "longitude": 153.0251,
                }
            ]
        }


class StubBackfillGarminClient(StubMonitoringGarminClient):
    def __init__(self, activities=None):
        super().__init__()
        self.activities = list(activities or default_backfill_activities())
        self.activity_range_calls = []

    def pull_activities(self, *, start_date, end_date, page_size):
        self.activity_range_calls.append((start_date, end_date, page_size))
        return list(self.activities)


class StubMapper:
    def __init__(self):
        self.calls = []

    def map_fit(self, fit_bytes, *, timezone):
        self.calls.append((fit_bytes, timezone))
        return canonical_batch()


class RecordingImportClient:
    def __init__(self, *, duplicate_keys=None):
        self.requests = []
        self.duplicate_keys = set(duplicate_keys or ())

    def post_canonical_import(self, *, idempotency_key, canonical):
        self.requests.append(
            {
                "idempotency_key": idempotency_key,
                "canonical": canonical,
            }
        )
        duplicate = idempotency_key in self.duplicate_keys
        self.duplicate_keys.add(idempotency_key)
        return {
            "accepted": True,
            "duplicate": duplicate,
            "batchId": idempotency_key,
        }


class FailingImportClient(RecordingImportClient):
    def __init__(self, *, fail_on_call):
        super().__init__()
        self.fail_on_call = fail_on_call

    def post_canonical_import(self, *, idempotency_key, canonical):
        if len(self.requests) + 1 == self.fail_on_call:
            raise RuntimeError("simulated import failure")
        return super().post_canonical_import(
            idempotency_key=idempotency_key,
            canonical=canonical,
        )


class RateLimitedImportClient(RecordingImportClient):
    def post_canonical_import(self, *, idempotency_key, canonical):
        self.requests.append(
            {
                "idempotency_key": idempotency_key,
                "canonical": canonical,
            }
        )
        raise PerenniaHttpError(status_code=429, retry_after_seconds=120)


class RecordingStatusClient:
    def __init__(self):
        self.reports = []

    def post_integration_status(self, report):
        self.reports.append(dict(report))
        return {"accepted": True}


class FailingLoginGarminClient(StubGarminClient):
    def login(self):
        raise RuntimeError("bad Garmin password for garmin-secret")


class GarminSyncResultStub:
    def __init__(self, mode, batch_keys):
        self.mode = mode
        self.batch_keys = list(batch_keys)


def canonical_batch():
    return {
        "activities": [
            {
                "source": "garmin",
                "externalId": "fit:serial:2026-06-23T20:00:00.000Z",
                "startedAt": "2026-06-23T20:00:00.000Z",
                "endedAt": "2026-06-23T20:30:00.000Z",
                "timezone": "Australia/Brisbane",
                "activityType": "strength_training",
                "summary": {
                    "duration": {"value": 1800, "unit": "second"},
                },
                "summaryMetrics": [
                    {
                        "source": "garmin",
                        "externalId": "fit:serial:2026-06-23T20:00:00.000Z:summary:averageHeartRate",
                        "metricKey": "averageHeartRate",
                        "value": {"value": 130, "unit": "beatsPerMinute"},
                        "at": {
                            "kind": "window",
                            "startedAt": "2026-06-23T20:00:00.000Z",
                            "endedAt": "2026-06-23T20:30:00.000Z",
                            "timezone": "Australia/Brisbane",
                        },
                    }
                ],
                "sets": [
                    {
                        "source": "garmin",
                        "externalId": "fit:serial:2026-06-23T20:00:00.000Z:set:1",
                        "timezone": "Australia/Brisbane",
                        "performedAt": "2026-06-23T20:10:00.000Z",
                        "dimensions": {
                            "load": {"value": 100, "unit": "kilogram"},
                            "reps": {"value": 5, "unit": "repetition"},
                        },
                    }
                ],
            }
        ],
        "metricReadings": [],
        "series": [
            {
                "source": "garmin",
                "externalId": "fit:serial:2026-06-23T20:00:00.000Z:series:heartRate",
                "type": "heartRate",
                "anchor": {
                    "kind": "activity",
                    "source": "garmin",
                    "externalId": "fit:serial:2026-06-23T20:00:00.000Z",
                },
                "baseTime": "2026-06-23T20:00:10.000Z",
                "timezone": "Australia/Brisbane",
                "samples": [
                    {
                        "offsetSeconds": 0,
                        "value": {"value": 130, "unit": "beatsPerMinute"},
                    }
                ],
            }
        ],
    }


def daily_monitoring(calendar_date="2026-06-24"):
    return GarminDailyMonitoring(
        calendar_date=calendar_date,
        daily_summary={
            "totalSteps": 12345,
            "activeKilocalories": 640,
            "restingHeartRate": 48,
        },
        heart_rates={
            "heartRateValues": [
                [1766520000000, 49],
                [1766520300000, 55],
            ]
        },
        sleep={
            "dailySleepDTO": {
                "sleepStartTimestampGMT": "2026-06-23T12:30:00.000Z",
                "sleepEndTimestampGMT": "2026-06-23T20:00:00.000Z",
                "sleepTimeSeconds": 27000,
            }
        },
        hrv={"hrvSummary": {"lastNightAvg": 62}},
        stress={"avgStressLevel": 21},
        body_battery=[
            {
                "bodyBatteryValuesArray": [
                    [1766520000000, 70],
                    [1766520300000, 77],
                ]
            }
        ],
        steps=[{"totalSteps": 12345}],
    )


def daily_monitoring_batch():
    return garmin_daily_monitoring_to_canonical(
        daily_monitoring(),
        timezone="Australia/Brisbane",
        consented_data_classes=("activities", "heartRate", "sleepWellness"),
    )


def backfill_config(state_path):
    return GarminSidecarConfig(
        garmin_email="athlete@example.test",
        garmin_password="garmin-secret",
        prn_base_url="https://perennia.example.test",
        prn_integration_token="perennia-secret",
        timezone="Australia/Brisbane",
        consented_data_classes=("activities", "heartRate", "sleepWellness"),
        monitoring_date="2026-06-24",
        backfill_start_date="2026-06-21",
        backfill_end_date="2026-06-24",
        backfill_activity_chunk_size=2,
        backfill_monitoring_chunk_days=2,
        state_path=str(state_path),
    )


def default_backfill_activities():
    return [
        backfill_activity("garmin-activity-3", "2026-06-24T20:00:00.000Z"),
        backfill_activity("garmin-activity-2", "2026-06-23T20:00:00.000Z"),
        backfill_activity("garmin-activity-1", "2026-06-22T20:00:00.000Z"),
    ]


def backfill_activity(activity_id, started_at):
    return GarminActivity(
        activity_id=activity_id,
        summary={
            "activityId": activity_id,
            "activityType": {"typeKey": "strength_training"},
            "startTimeGMT": started_at,
            "distance": 5000,
            "duration": 1800,
            "averageHR": 132,
        },
        fit_bytes=f"fit-{activity_id}".encode("utf-8"),
    )


if __name__ == "__main__":
    unittest.main()
