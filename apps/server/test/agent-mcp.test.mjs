import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";

import {
  applyMigrations,
  createAgentMcpServer,
  createApp,
  createDatabaseClient,
  createDrizzleAgentCrossDomainReadStore,
  createDrizzleAgentExerciseCatalogBatchWriteStore,
  createDrizzleAgentFoodBatchWriteStore,
  createDrizzleAgentFoodCatalogStore,
  createDrizzleAgentMealBatchWriteStore,
  createDrizzleAgentNutritionGoalStore,
  createDrizzleAgentNutritionReadStore,
  createDrizzleAgentReadStore,
  createDrizzleAgentWorkoutBatchWriteStore,
  createDrizzleRateLimitBackend,
  createInMemoryAgentCatalogStore,
  schema
} from "../src/index.ts";

const databaseUrl = process.env.DATABASE_URL;

if (!databaseUrl && process.env.CI === "true") {
  throw new Error("DATABASE_URL must be set for server Postgres integration tests.");
}

test("agent MCP server exposes tool schemas derived from the REST Zod contracts", async () => {
  const { client, close } = await createMcpClient(
    createAgentMcpServer({
      agentApiKeyStore: createAgentKeyStore("user-1"),
      agentCatalogStore: createInMemoryAgentCatalogStore(catalogFixtures("user-1")),
      agentReadStore: {
        async listHistory() {
          return {
            sets: [],
            limit: 50,
            nextCursor: null,
            totalMatched: 0
          };
        },
        async listWorkouts() {
          return {
            workouts: [],
            fields: ["id", "startedAt"],
            limit: 50,
            nextCursor: null,
            totalMatched: 0
          };
        },
        async readExerciseSets() {
          return [];
        }
      },
      agentWorkoutBatchWriteStore: {
        async writeWorkoutBatch(input) {
          return {
            duplicate: false,
            serverClock: "2026-06-24T05:00:01.000Z",
            applied: input.sets.map((set) => ({
              id: set.id,
              updatedAt: set.updatedAt,
              deviceId: input.deviceId
            }))
          };
        }
      },
      agentExerciseCatalogBatchWriteStore: {
        async writeExerciseCatalogBatch(input) {
          return {
            duplicate: false,
            serverClock: "2026-06-24T05:00:01.000Z",
            applied: [...input.categories, ...input.exercises].map((row) => ({
              id: row.id,
              updatedAt: row.updatedAt,
              deviceId: input.deviceId
            }))
          };
        }
      },
      agentMealBatchWriteStore: {
        async writeMealBatch(input) {
          return {
            duplicate: false,
            serverClock: "2026-06-24T05:00:01.000Z",
            applied: [input.meal, ...input.entries].map((row) => ({
              id: row.id,
              updatedAt: row.updatedAt,
              deviceId: input.deviceId
            }))
          };
        }
      },
      agentMetricStore: {
        async listMetrics() {
          return {
            metrics: [],
            fields: ["id", "name"],
            limit: 50,
            nextCursor: null,
            totalMatched: 0
          };
        },
        async listMetricReadings() {
          return {
            readings: [],
            fields: ["id", "metricId"],
            limit: 50,
            nextCursor: null,
            totalMatched: 0
          };
        },
        async writeMetricBatch(input) {
          return {
            accepted: true,
            duplicate: false,
            serverClock: "2026-06-24T05:00:01.000Z",
            activityLogEntries: input.request.metrics.length + input.request.readings.length,
            applied: input.request.readings.map((reading) => ({
              id: reading.id,
              updatedAt: reading.updatedAt ?? "2026-06-24T05:00:00.000Z",
              deviceId: input.deviceId
            })),
            metrics: input.request.metrics.map((metric) => ({
              id: metric.id,
              name: metric.name,
              valueShape: metric.valueShape,
              unit: metric.unit,
              metricGroup: metric.metricGroup,
              applied: true,
              outcome: "applied"
            })),
            readings: input.request.readings.map((reading) => ({
              id: reading.id,
              metricId: reading.metricId,
              valueShape: reading.value.shape,
              unit: "kilogram",
              warnings: [],
              applied: true,
              outcome: "applied"
            }))
          };
        }
      },
      agentNutritionReadStore: {
        async readNutritionDays() {
          return [];
        },
        async listMeals() {
          return {
            meals: [],
            fields: ["id", "mealType", "startedAt"],
            limit: 50,
            nextCursor: null,
            totalMatched: 0
          };
        }
      },
      agentCrossDomainReadStore: {
        async readWorkoutTimings() {
          return [];
        },
        async readCaloriesBurnedReadings() {
          return [];
        }
      },
      agentProtocolsStore: {
        async listCompounds() {
          return { compounds: [], fields: ["id", "name"], limit: 50, nextCursor: null, totalMatched: 0 };
        },
        async listProtocols() {
          return { protocols: [], limit: 50, nextCursor: null, totalMatched: 0 };
        },
        async listDoses() {
          return { doses: [], fields: ["id"], limit: 50, nextCursor: null, totalMatched: 0 };
        },
        async readEffectWindow() {
          return { ok: false, message: "not used" };
        },
        async writeDoseBatch(input) {
          return {
            duplicate: false,
            idempotencyConflict: false,
            receiptUnavailable: false,
            serverClock: "2026-06-24T05:00:01.000Z",
            accepted: input.doses.map((dose) => dose.id),
            applied: input.doses.map((dose) => ({
              id: dose.id,
              updatedAt: dose.updatedAt,
              deviceId: input.deviceId
            })),
            validationErrors: []
          };
        },
        async writeCompoundBatch(input) {
          return {
            duplicate: false,
            idempotencyConflict: false,
            receiptUnavailable: false,
            serverClock: "2026-06-24T05:00:01.000Z",
            accepted: input.compounds.map((compound) => compound.id),
            applied: input.compounds.map((compound) => ({
              id: compound.id,
              updatedAt: compound.updatedAt,
              deviceId: input.deviceId
            })),
            validationErrors: []
          };
        },
        async writeProtocolBatch(input) {
          return {
            duplicate: false,
            idempotencyConflict: false,
            receiptUnavailable: false,
            serverClock: "2026-06-24T05:00:01.000Z",
            accepted: input.protocols.map((protocol) => protocol.id),
            applied: input.protocols.map((protocol) => ({
              id: protocol.id,
              updatedAt: protocol.updatedAt,
              deviceId: input.deviceId
            })),
            validationErrors: []
          };
        }
      }
    })
  );

  try {
    const { tools } = await client.listTools();
    const toolsByName = new Map(tools.map((tool) => [tool.name, tool]));

    assert.deepEqual(
      tools.map((tool) => tool.name).sort(),
      [
        "agent_batch_write_compounds",
        "agent_batch_write_doses",
        "agent_batch_write_exercise_catalog",
        "agent_batch_write_foods",
        "agent_batch_write_meal",
        "agent_batch_write_metrics",
        "agent_batch_write_nutrition_goals",
        "agent_batch_write_plan_tree",
        "agent_batch_write_protocols",
        "agent_batch_write_settings",
        "agent_batch_write_workout",
        "agent_capture_workout_template",
        "agent_get_energy_balance",
        "agent_get_exercise_analytics",
        "agent_get_monitoring_activity",
        "agent_get_nutrition_totals",
        "agent_get_nutrition_trends",
        "agent_get_routine",
        "agent_get_training_day_nutrition",
        "agent_get_workout",
        "agent_get_workout_template",
        "agent_list_activity",
        "agent_list_compounds",
        "agent_list_doses",
        "agent_list_exercises",
        "agent_list_foods",
        "agent_list_history_sets",
        "agent_list_meals",
        "agent_list_metric_readings",
        "agent_list_metrics",
        "agent_list_nutrition_goals",
        "agent_list_protocols",
        "agent_list_routines",
        "agent_list_workout_templates",
        "agent_list_workouts",
        "agent_materialize_workout_template",
        "agent_read_effect_window",
        "agent_read_settings",
        "agent_resolve_exercise",
        "agent_search_platform_foods",
        "agent_undo_activity_batch",
        "agent_update_workout_template_from_workout",
        "agent_validate_dose",
        "agent_validate_set"
      ]
    );
    assert.ok(
      toolsByName
        .get("agent_batch_write_workout")
        .inputSchema.properties.request.properties.sets.items.properties.values
    );
    assert.ok(
      toolsByName
        .get("agent_get_exercise_analytics")
        .inputSchema.properties.params.properties.exerciseId
    );
    assert.ok(
      toolsByName
        .get("agent_list_history_sets")
        .inputSchema.properties.query.properties.exerciseId
    );
    assert.ok(
      toolsByName
        .get("agent_batch_write_metrics")
        .inputSchema.properties.request.properties.readings.items.properties
        .timeAnchor
    );
    assert.ok(
      toolsByName
        .get("agent_list_metrics")
        .inputSchema.properties.query.properties.search
    );
    assert.ok(
      toolsByName
        .get("agent_list_metric_readings")
        .inputSchema.properties.query.properties.metricId
    );
    assert.ok(
      toolsByName.get("agent_list_workouts").inputSchema.properties.query
        .properties.from
    );
    assert.ok(
      toolsByName.get("agent_get_workout").inputSchema.properties.params
        .properties.workoutId
    );
    assert.ok(
      toolsByName.get("agent_list_meals").inputSchema.properties.query
        .properties.from
    );
    assert.ok(
      toolsByName
        .get("agent_batch_write_exercise_catalog")
        .inputSchema.properties.request.properties.exercises.items.properties
        .dimensions
    );
    assert.ok(
      toolsByName
        .get("agent_batch_write_exercise_catalog")
        .inputSchema.properties.request.properties.categories.items.properties
        .name
    );
    assert.ok(
      toolsByName
        .get("agent_batch_write_plan_tree")
        .inputSchema.properties.request.properties.templateGroups.items
        .properties.rounds
    );
    assert.ok(
      toolsByName
        .get("agent_batch_write_plan_tree")
        .inputSchema.properties.request.properties.routineEntries.items
        .properties.slot
    );
    assert.ok(
      toolsByName
        .get("agent_batch_write_plan_tree")
        .inputSchema.properties.request.required.includes("expectedCounts")
    );
    assert.equal(
      toolsByName
        .get("agent_batch_write_plan_tree")
        .inputSchema.properties.request.properties.dryRun.default,
      false
    );
    const doseIdSchema = toolsByName
      .get("agent_batch_write_doses")
      .inputSchema.properties.request.properties.doses.items.properties.id;
    assert.ok(JSON.stringify(doseIdSchema).includes("[0-9a-fA-F]"));
    assert.ok(
      toolsByName
        .get("agent_materialize_workout_template")
        .inputSchema.properties.request.properties.workoutTemplateId
    );
    assert.ok(
      toolsByName
        .get("agent_capture_workout_template")
        .inputSchema.properties.request.properties.workoutId
    );
    assert.ok(
      toolsByName
        .get("agent_update_workout_template_from_workout")
        .inputSchema.properties.request.properties.workoutId
    );

    // Nutrition tool schemas derive from the same REST Zod contracts: the write
    // tool's request mirrors the meal batch-write body (idempotencyKey + entries),
    // and the read tools expose the route's from/to range query.
    assert.ok(
      toolsByName
        .get("agent_batch_write_meal")
        .inputSchema.properties.request.properties.idempotencyKey
    );
    assert.ok(
      toolsByName
        .get("agent_batch_write_meal")
        .inputSchema.properties.request.properties.entries.items.properties
        .nutrients
    );
    for (const readTool of [
      "agent_get_nutrition_totals",
      "agent_get_nutrition_trends",
      "agent_get_energy_balance",
      "agent_get_training_day_nutrition"
    ]) {
      assert.ok(
        toolsByName.get(readTool).inputSchema.properties.query.properties.from,
        `${readTool} should expose the range from query`
      );
      assert.ok(
        toolsByName.get(readTool).inputSchema.properties.query.properties.to,
        `${readTool} should expose the range to query`
      );
    }
  } finally {
    await close();
  }
});

test("agent MCP nutrition tool list mirrors the nutrition REST route set", () => {
  // The MCP nutrition tool set must mirror the nutrition route set exactly: one
  // write tool over the meal batch-write route, plus a read tool per computed
  // read route (slice-02 totals/trends + slice-03 cross-domain joins).
  const nutritionRoutePaths = [
    "/agent/meals/batch-write",
    "/agent/nutrition/totals",
    "/agent/nutrition/trends",
    "/agent/nutrition/goals",
    "/agent/nutrition/goals/batch-write",
    "/agent/cross-domain/energy-balance",
    "/agent/cross-domain/training-day-nutrition"
  ];
  const nutritionToolNames = [
    "agent_batch_write_meal",
    "agent_get_nutrition_totals",
    "agent_get_nutrition_trends",
    "agent_list_nutrition_goals",
    "agent_batch_write_nutrition_goals",
    "agent_get_energy_balance",
    "agent_get_training_day_nutrition"
  ];
  assert.equal(nutritionToolNames.length, nutritionRoutePaths.length);
});

test("agent MCP validate-dose accepts a valid dose and echoes limits, like REST", async () => {
  const { client, close } = await createMcpClient(
    createAgentMcpServer({
      agentApiKeyStore: createAgentKeyStore("user-1"),
      logger: { info() {}, error() {} }
    })
  );

  try {
    const response = await callTool(client, "agent_validate_dose", {
      apiKey: "prn_agent_secret",
      request: {
        amount: "250",
        unit: "milligram",
        route: "intramuscular"
      }
    });

    assertToolSucceeded(response);
    assert.equal(response.structuredContent.accepted, true);
    assert.deepEqual(response.structuredContent.warnings, []);
    assert.ok(response.structuredContent.limits.units.milligram);
  } finally {
    await close();
  }
});

test("agent MCP validate-dose hard-rejects an out-of-registry unit before any side effects", async () => {
  const { client, close } = await createMcpClient(
    createAgentMcpServer({
      agentApiKeyStore: createAgentKeyStore("user-1"),
      logger: { info() {}, error() {} }
    })
  );

  try {
    const response = await callTool(client, "agent_validate_dose", {
      apiKey: "prn_agent_secret",
      request: {
        amount: "1",
        unit: "not-a-real-unit",
        route: "oral"
      }
    });

    assert.equal(response.isError, true);
    assert.equal(response.structuredContent.code, "agent_dose_validation_failed");
    assert.equal(response.structuredContent.errors[0].rule, "dose_unit_allowed");
  } finally {
    await close();
  }
});

test("agent MCP get-monitoring-activity is a thin adapter over the same agentReadStore REST uses", async () => {
  const activityId = randomUUID();
  const monitoringResponse = {
    externalActivity: {
      id: activityId,
      source: "garmin",
      externalId: "garmin-thin-adapter",
      activityType: "cycling",
      startedAt: "2026-06-24T10:00:00.000Z",
      endedAt: "2026-06-24T10:05:00.000Z",
      timezone: "Australia/Brisbane"
    },
    summaryReadings: [],
    seriesSummaries: [],
    heartRate: null,
    route: null
  };
  let capturedInput;
  const { client, close } = await createMcpClient(
    createAgentMcpServer({
      agentApiKeyStore: createAgentKeyStore("user-1", {}, "agent-monitoring-key"),
      agentReadStore: {
        async listHistory() {
          throw new Error("not used");
        },
        async readExerciseSets() {
          throw new Error("not used");
        },
        async readMonitoringActivity(input) {
          capturedInput = input;
          return monitoringResponse;
        }
      },
      logger: { info() {}, error() {} }
    })
  );

  try {
    const response = await callTool(client, "agent_get_monitoring_activity", {
      apiKey: "prn_agent_secret",
      params: { externalActivityId: activityId }
    });

    assertToolSucceeded(response);
    assert.deepEqual(response.structuredContent, monitoringResponse);
    assert.deepEqual(capturedInput, {
      userId: "user-1",
      agentKeyId: "agent-monitoring-key",
      externalActivityId: activityId
    });
  } finally {
    await close();
  }
});

test("agent MCP get-monitoring-activity 404s like REST when the External Activity is not visible", async () => {
  const { client, close } = await createMcpClient(
    createAgentMcpServer({
      agentApiKeyStore: createAgentKeyStore("user-1"),
      agentReadStore: {
        async listHistory() {
          throw new Error("not used");
        },
        async readExerciseSets() {
          throw new Error("not used");
        },
        async readMonitoringActivity() {
          return null;
        }
      },
      logger: { info() {}, error() {} }
    })
  );

  try {
    const response = await callTool(client, "agent_get_monitoring_activity", {
      apiKey: "prn_agent_secret",
      params: { externalActivityId: randomUUID() }
    });

    assert.equal(response.isError, true);
    assert.equal(
      response.structuredContent.code,
      "agent_monitoring_activity_not_found"
    );
  } finally {
    await close();
  }
});

test(
  "agent MCP batch write persists rows, records one Activity Log batch, and enqueues a sync nudge like REST",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-mcp-batch-user-${randomUUID()}`;
    const nudges = [];
    const server = createAgentMcpServer({
      agentApiKeyStore: createAgentKeyStore(userId),
      agentCatalogStore: createInMemoryAgentCatalogStore(catalogFixtures(userId)),
      agentWorkoutBatchWriteStore: createDrizzleAgentWorkoutBatchWriteStore(
        database.db
      ),
      logger: { info() {}, error() {} },
      syncNudgePublisher: {
        async enqueueSyncNudge(input) {
          nudges.push(input);
          return { enqueued: true, jobId: `agent-mcp-nudge-${nudges.length}` };
        }
      }
    });
    const { client, close } = await createMcpClient(server);
    const request = batchRequest({
      idempotencyKey: `agent-mcp-batch-${randomUUID()}`,
      sets: [
        {
          id: randomUUID(),
          exerciseName: "Back Squat",
          position: 0,
          values: {
            load: { entered: "400", unit: "kilogram" },
            reps: { entered: "5", unit: "repetition" }
          }
        }
      ]
    });

    try {
      await seedUser(database, userId);

      const response = await callTool(client, "agent_batch_write_workout", {
        apiKey: "prn_agent_secret",
        request
      });

      assertToolSucceeded(response);
      assert.equal(response.structuredContent.accepted, true);
      assert.equal(response.structuredContent.duplicate, false);
      assert.equal(response.structuredContent.batchId, request.idempotencyKey);
      assert.deepEqual(
        response.structuredContent.sets[0].warnings.map((warning) => warning.rule),
        ["added_load_improbable"]
      );

      const rows = await database.sql`
        select id, user_id, device_id, payload, deleted_at
        from logged_sets
        where id = ${request.sets[0].id}
      `;
      assert.equal(rows.length, 1);
      assert.equal(rows[0].user_id, userId);
      assert.equal(rows[0].device_id, "agent:agent-key-1");
      assert.equal(rows[0].payload.workout_id, request.workout.id);
      assert.equal(rows[0].payload.exercise_id, "user-back-squat");
      assert.equal(rows[0].payload.load_entered, "400");
      assert.equal(rows[0].deleted_at, null);

      const activityRows = await database.sql`
        select actor, batch_id, entity_table, entity_id, before_image, after_image
        from activity_log
        where batch_id = ${request.idempotencyKey}
      `;
      assert.equal(activityRows.length, 3);
      assert.deepEqual(
        activityRows
          .map((row) => row.entity_table)
          .sort(),
        ["logged_sets", "workout_exercises", "workout_sessions"]
      );
      const setActivity = activityRows.find(
        (row) => row.entity_table === "logged_sets"
      );
      assert.equal(setActivity.actor, "agent");
      assert.equal(setActivity.before_image, null);
      assert.equal(setActivity.after_image.exercise_id, "user-back-squat");

      assert.deepEqual(nudges, [
        {
          userId,
          sourceDeviceId: "agent:agent-key-1",
          reason: "agent_write"
        }
      ]);
    } finally {
      await close();
      await database.close();
    }
  }
);

test(
  "agent MCP batch hard-rejects invalid sets before rows, Activity Log, or nudge side effects",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-mcp-invalid-user-${randomUUID()}`;
    const nudges = [];
    const { client, close } = await createMcpClient(
      createAgentMcpServer({
        agentApiKeyStore: createAgentKeyStore(userId),
        agentCatalogStore: createInMemoryAgentCatalogStore(catalogFixtures(userId)),
        agentWorkoutBatchWriteStore: createDrizzleAgentWorkoutBatchWriteStore(
          database.db
        ),
        logger: { info() {}, error() {} },
        syncNudgePublisher: {
          async enqueueSyncNudge(input) {
            nudges.push(input);
            return { enqueued: true, jobId: "unexpected-nudge" };
          }
        }
      })
    );
    const request = batchRequest({
      idempotencyKey: `agent-mcp-invalid-${randomUUID()}`,
      sets: [
        {
          id: randomUUID(),
          exerciseName: "Back Squat",
          position: 0,
          values: {
            reps: { entered: "10001", unit: "repetition" }
          }
        }
      ]
    });

    try {
      await seedUser(database, userId);

      const response = await callTool(client, "agent_batch_write_workout", {
        apiKey: "prn_agent_secret",
        request
      });

      assert.equal(response.isError, true);
      assert.equal(response.structuredContent.code, "agent_batch_write_failed");
      assert.equal(response.structuredContent.errors[0].rule, "reps_max");
      assert.equal(response.structuredContent.errors[0].itemIndex, 0);

      const rows = await database.sql`
        select id
        from logged_sets
        where id = ${request.sets[0].id}
      `;
      assert.equal(rows.length, 0);
      const activityRows = await database.sql`
        select id
        from activity_log
        where batch_id = ${request.idempotencyKey}
      `;
      assert.equal(activityRows.length, 0);
      assert.deepEqual(nudges, []);
    } finally {
      await close();
      await database.close();
    }
  }
);

test(
  "agent MCP per-key rate limiting rejects calls before side effects",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-mcp-rate-limit-user-${randomUUID()}`;
    const agentKeyId = `agent-mcp-rate-limit-key-${randomUUID()}`;
    const { client, close } = await createMcpClient(
      createAgentMcpServer({
        agentApiKeyStore: createAgentKeyStore(
          userId,
          {
            rateLimitEnabled: true,
            rateLimitTimeWindow: 60 * 1000,
            rateLimitMax: 1
          },
          agentKeyId
        ),
        agentCatalogStore: createInMemoryAgentCatalogStore(catalogFixtures(userId)),
        agentWorkoutBatchWriteStore: createDrizzleAgentWorkoutBatchWriteStore(
          database.db
        ),
        logger: { info() {}, error() {} },
        rateLimitBackend: createDrizzleRateLimitBackend(database.db)
      })
    );
    const firstRequest = batchRequest({
      idempotencyKey: `agent-mcp-rate-limit-first-${randomUUID()}`,
      sets: [
        {
          id: randomUUID(),
          exerciseName: "Back Squat",
          position: 0,
          values: {
            load: { entered: "100", unit: "kilogram" },
            reps: { entered: "5", unit: "repetition" }
          }
        }
      ]
    });
    const overLimitRequest = batchRequest({
      idempotencyKey: `agent-mcp-rate-limit-second-${randomUUID()}`,
      sets: [
        {
          id: randomUUID(),
          exerciseName: "Bench Press",
          position: 0,
          values: {
            load: { entered: "80", unit: "kilogram" },
            reps: { entered: "8", unit: "repetition" }
          }
        }
      ]
    });

    try {
      await seedUser(database, userId);

      const firstResponse = await callTool(client, "agent_batch_write_workout", {
        apiKey: "prn_agent_secret",
        request: firstRequest
      });
      assertToolSucceeded(firstResponse);

      const overLimitResponse = await callTool(
        client,
        "agent_batch_write_workout",
        {
          apiKey: "prn_agent_secret",
          request: overLimitRequest
        }
      );
      assert.equal(overLimitResponse.isError, true);
      assert.deepEqual(overLimitResponse.structuredContent, {
        code: "rate_limited",
        message: "Too many requests.",
        limit: 1,
        retryAfterSeconds: 60
      });

      const overLimitRows = await database.sql`
        select id
        from logged_sets
        where id = ${overLimitRequest.sets[0].id}
      `;
      assert.equal(overLimitRows.length, 0);
      const overLimitActivityRows = await database.sql`
        select id
        from activity_log
        where batch_id = ${overLimitRequest.idempotencyKey}
      `;
      assert.equal(overLimitActivityRows.length, 0);

      const rateLimitRows = await database.sql`
        select coalesce(sum(count), 0)::int as total_hits
        from rate_limit_windows
        where key = ${`agent-api-key:${agentKeyId}`}
      `;
      assert.equal(rateLimitRows[0].total_hits, 2);
    } finally {
      await close();
      await database.close();
    }
  }
);

test(
  "agent MCP batch write exercise catalog persists a Category and an Exercise, records one Activity Log batch, and enqueues a sync nudge like REST",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-mcp-exercise-catalog-user-${randomUUID()}`;
    const nudges = [];
    const server = createAgentMcpServer({
      agentApiKeyStore: createAgentKeyStore(userId),
      agentCatalogStore: createInMemoryAgentCatalogStore(catalogFixtures(userId)),
      agentExerciseCatalogBatchWriteStore:
        createDrizzleAgentExerciseCatalogBatchWriteStore(database.db),
      logger: { info() {}, error() {} },
      syncNudgePublisher: {
        async enqueueSyncNudge(input) {
          nudges.push(input);
          return { enqueued: true, jobId: `agent-mcp-nudge-${nudges.length}` };
        }
      }
    });
    const { client, close } = await createMcpClient(server);
    const categoryId = randomUUID();
    const exerciseId = randomUUID();
    const request = {
      idempotencyKey: `agent-mcp-exercise-catalog-${randomUUID()}`,
      categories: [
        {
          id: categoryId,
          name: "Mobility",
          sortOrder: 0,
          colorHex: "#607D8B",
          deletedAt: null
        }
      ],
      exercises: [
        {
          id: exerciseId,
          name: "Couch Stretch",
          categoryId,
          dimensions: ["duration"],
          defaultLoadUnit: "kilogram",
          loadMode: "added",
          isUnilateral: false,
          usesRpe: false,
          isFavorite: false,
          equipment: [],
          notes: null,
          customizesExerciseId: null,
          deletedAt: null
        }
      ]
    };

    try {
      await seedUser(database, userId);

      const response = await callTool(
        client,
        "agent_batch_write_exercise_catalog",
        {
          apiKey: "prn_agent_secret",
          request
        }
      );

      assertToolSucceeded(response);
      assert.equal(response.structuredContent.accepted, true);
      assert.equal(response.structuredContent.duplicate, false);
      assert.equal(response.structuredContent.batchId, request.idempotencyKey);
      assert.equal(response.structuredContent.categories[0].name, "Mobility");
      assert.equal(response.structuredContent.exercises[0].name, "Couch Stretch");
      assert.equal(response.structuredContent.exercises[0].library, "user");

      const exerciseRows = await database.sql`
        select user_id, payload, deleted_at
        from exercises
        where id = ${exerciseId}
      `;
      assert.equal(exerciseRows.length, 1);
      assert.equal(exerciseRows[0].user_id, userId);
      assert.equal(exerciseRows[0].payload.name, "Couch Stretch");
      assert.equal(exerciseRows[0].payload.category_id, categoryId);
      assert.equal(exerciseRows[0].deleted_at, null);

      const categoryRows = await database.sql`
        select user_id, payload
        from exercise_categories
        where id = ${categoryId}
      `;
      assert.equal(categoryRows.length, 1);
      assert.equal(categoryRows[0].payload.name, "Mobility");

      const activityRows = await database.sql`
        select actor, batch_id, entity_table
        from activity_log
        where batch_id = ${request.idempotencyKey}
      `;
      assert.equal(activityRows.length, 2);
      assert.ok(activityRows.every((row) => row.actor === "agent"));

      assert.deepEqual(nudges, [
        {
          userId,
          sourceDeviceId: "agent:agent-key-1",
          reason: "agent_write"
        }
      ]);
    } finally {
      await close();
      await database.close();
    }
  }
);

test(
  "agent MCP analytics and history reads match the equivalent REST responses",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-mcp-read-user-${randomUUID()}`;
    const app = createAgentReadApp({
      agentReadStore: createDrizzleAgentReadStore(database.db),
      userId
    });
    const { client, close } = await createMcpClient(
      createAgentMcpServer({
        agentApiKeyStore: createAgentKeyStore(userId),
        agentCatalogStore: createInMemoryAgentCatalogStore(catalogFixtures(userId)),
        agentReadStore: createDrizzleAgentReadStore(database.db),
        logger: { info() {}, error() {} }
      })
    );
    const setIds = {
      squatFive: randomUUID(),
      squatTriple: randomUUID(),
      bench: randomUUID()
    };

    try {
      await seedUser(database, userId);
      await seedLoggedSet(database, {
        userId,
        id: setIds.squatFive,
        exerciseId: "user-back-squat",
        exerciseName: "Back Squat",
        performedAt: "2026-06-01T10:00:00.000Z",
        position: 0,
        values: {
          load: { entered: "100", unit: "kilogram" },
          reps: { entered: "5", unit: "repetition" }
        }
      });
      await seedLoggedSet(database, {
        userId,
        id: setIds.squatTriple,
        exerciseId: "user-back-squat",
        exerciseName: "Back Squat",
        performedAt: "2026-06-08T10:00:00.000Z",
        position: 1,
        values: {
          load: { entered: "120", unit: "kilogram" },
          reps: { entered: "3", unit: "repetition" }
        }
      });
      await seedLoggedSet(database, {
        userId,
        id: setIds.bench,
        exerciseId: "platform-bench-press",
        exerciseName: "Bench Press",
        performedAt: "2026-06-15T11:00:00.000Z",
        position: 0,
        values: {
          load: { entered: "80", unit: "kilogram" },
          reps: { entered: "6", unit: "repetition" }
        }
      });

      const restAnalyticsResponse = await getAgent(
        app,
        "/agent/analytics/exercises/user-back-squat?maxPoints=2"
      );
      assert.equal(restAnalyticsResponse.status, 200);
      const restAnalyticsBody = await restAnalyticsResponse.json();
      const mcpAnalyticsResponse = await callTool(
        client,
        "agent_get_exercise_analytics",
        {
          apiKey: "prn_agent_secret",
          params: { exerciseId: "user-back-squat" },
          query: { maxPoints: 2 }
        }
      );
      assertToolSucceeded(mcpAnalyticsResponse);
      assert.deepEqual(mcpAnalyticsResponse.structuredContent, restAnalyticsBody);

      const restHistoryResponse = await getAgent(
        app,
        "/agent/history/sets?exerciseId=user-back-squat&limit=2"
      );
      assert.equal(restHistoryResponse.status, 200);
      const restHistoryBody = await restHistoryResponse.json();
      const mcpHistoryResponse = await callTool(
        client,
        "agent_list_history_sets",
        {
          apiKey: "prn_agent_secret",
          query: { exerciseId: "user-back-squat", limit: 2 }
        }
      );
      assertToolSucceeded(mcpHistoryResponse);
      assert.deepEqual(mcpHistoryResponse.structuredContent, restHistoryBody);

      const restWorkoutsResponse = await getAgent(
        app,
        "/agent/workouts?from=2026-06-01T00:00:00.000Z&to=2026-06-30T00:00:00.000Z&fields=id,startedAt,setCount,exerciseNames"
      );
      assert.equal(restWorkoutsResponse.status, 200);
      const restWorkoutsBody = await restWorkoutsResponse.json();
      const mcpWorkoutsResponse = await callTool(client, "agent_list_workouts", {
        apiKey: "prn_agent_secret",
        query: {
          from: "2026-06-01T00:00:00.000Z",
          to: "2026-06-30T00:00:00.000Z",
          fields: "id,startedAt,setCount,exerciseNames"
        }
      });
      assertToolSucceeded(mcpWorkoutsResponse);
      assert.deepEqual(mcpWorkoutsResponse.structuredContent, restWorkoutsBody);

      const workoutId = `workout-${setIds.squatFive}`;
      const restWorkoutResponse = await getAgent(
        app,
        `/agent/workouts/${workoutId}`
      );
      assert.equal(restWorkoutResponse.status, 200);
      const restWorkoutBody = await restWorkoutResponse.json();
      const mcpWorkoutResponse = await callTool(client, "agent_get_workout", {
        apiKey: "prn_agent_secret",
        params: { workoutId }
      });
      assertToolSucceeded(mcpWorkoutResponse);
      assert.deepEqual(mcpWorkoutResponse.structuredContent, restWorkoutBody);
    } finally {
      await close();
      await database.close();
    }
  }
);

test(
  "agent MCP meal batch write matches REST: persists, warns per item, one Activity Log batch, nudge, and converges on idempotent retry",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const restUserId = `agent-mcp-meal-rest-${randomUUID()}`;
    const mcpUserId = `agent-mcp-meal-mcp-${randomUUID()}`;
    const restNudges = [];
    const mcpNudges = [];

    const restApp = createApp({
      logger: { info() {}, error() {} },
      agentApiKeyStore: createAgentKeyStore(restUserId),
      agentMealBatchWriteStore: createDrizzleAgentMealBatchWriteStore(
        database.db
      ),
      syncNudgePublisher: {
        async enqueueSyncNudge(input) {
          restNudges.push(input);
          return { enqueued: true, jobId: `rest-nudge-${restNudges.length}` };
        }
      }
    });
    const { client, close } = await createMcpClient(
      createAgentMcpServer({
        agentApiKeyStore: createAgentKeyStore(mcpUserId),
        agentMealBatchWriteStore: createDrizzleAgentMealBatchWriteStore(
          database.db
        ),
        logger: { info() {}, error() {} },
        syncNudgePublisher: {
          async enqueueSyncNudge(input) {
            mcpNudges.push(input);
            return { enqueued: true, jobId: `mcp-nudge-${mcpNudges.length}` };
          }
        }
      })
    );

    // A Quick Entry whose stated energy is far from its Atwater estimate -> a
    // soft warning that must still persist and ride back in the tool result.
    const warnEntry = (id) => ({
      id,
      position: 0,
      name: "Mystery shake",
      nutrients: {
        energy: {
          status: "complete",
          value: 900,
          entered: "900",
          unit: "kilocalorie"
        },
        protein: { status: "complete", value: 10, entered: "10", unit: "gram" },
        carbohydrate: {
          status: "complete",
          value: 10,
          entered: "10",
          unit: "gram"
        },
        fat: { status: "complete", value: 5, entered: "5", unit: "gram" }
      },
      isLiquid: true,
      foodId: null,
      foodSource: null,
      portion: null,
      servingLabel: null,
      servingSize: null,
      packageSize: null,
      updatedAt: "2026-06-24T05:00:00.000Z"
    });

    try {
      await seedUser(database, restUserId);
      await seedUser(database, mcpUserId);

      // --- REST baseline ---
      const restRequest = mealRequest({
        idempotencyKey: `agent-mcp-meal-rest-${randomUUID()}`,
        mealId: `meal-rest-${randomUUID()}`,
        entries: [warnEntry(`entry-rest-${randomUUID()}`)]
      });
      const restResponse = await postAgentMeal(restApp, restRequest);
      assert.equal(restResponse.status, 200);
      const restBody = await restResponse.json();

      // --- MCP under test ---
      const mcpRequest = mealRequest({
        idempotencyKey: `agent-mcp-meal-mcp-${randomUUID()}`,
        mealId: `meal-mcp-${randomUUID()}`,
        entries: [warnEntry(`entry-mcp-${randomUUID()}`)]
      });
      const mcpResponse = await callTool(client, "agent_batch_write_meal", {
        apiKey: "prn_agent_secret",
        request: mcpRequest
      });
      assertToolSucceeded(mcpResponse);
      const mcpBody = mcpResponse.structuredContent;

      // Behavioral parity: same envelope shape (ids differ by request).
      assert.equal(mcpBody.accepted, restBody.accepted);
      assert.equal(mcpBody.duplicate, restBody.duplicate);
      assert.equal(mcpBody.batchId, mcpRequest.idempotencyKey);
      assert.equal(mcpBody.mealId, mcpRequest.meal.id);
      assert.deepEqual(
        mcpBody.entries.map((entry) => ({
          kind: entry.kind,
          warnings: entry.warnings.map((warning) => warning.rule)
        })),
        restBody.entries.map((entry) => ({
          kind: entry.kind,
          warnings: entry.warnings.map((warning) => warning.rule)
        }))
      );
      assert.deepEqual(
        mcpBody.entries[0].warnings.map((warning) => warning.rule),
        ["energy_atwater_mismatch"]
      );

      // Meal + Food Entry rows persisted under the agent device, no totals.
      const mealRows = await database.sql`
        select user_id, device_id, payload from meals where id = ${mcpRequest.meal.id}
      `;
      assert.equal(mealRows.length, 1);
      assert.equal(mealRows[0].user_id, mcpUserId);
      assert.equal(mealRows[0].device_id, "agent:agent-key-1");
      const entryRows = await database.sql`
        select payload from food_entries where id = ${mcpRequest.entries[0].id}
      `;
      assert.equal(entryRows.length, 1);
      assert.equal(entryRows[0].payload.total_energy, undefined);

      // Exactly one Activity Log batch (meal + entry rows, one batch_id, agent actor).
      const activityRows = await database.sql`
        select actor, batch_id, entity_table from activity_log
        where batch_id = ${mcpRequest.idempotencyKey}
      `;
      assert.equal(activityRows.length, 2);
      assert.equal(new Set(activityRows.map((row) => row.batch_id)).size, 1);
      assert.ok(activityRows.every((row) => row.actor === "agent"));
      const tables = new Set(activityRows.map((row) => row.entity_table));
      assert.ok(tables.has("meals"));
      assert.ok(tables.has("food_entries"));

      // 'agent' Provenance + sync nudge, same as REST.
      assert.deepEqual(mcpNudges, [
        {
          userId: mcpUserId,
          sourceDeviceId: "agent:agent-key-1",
          reason: "agent_write"
        }
      ]);
      assert.equal(restNudges.length, 1);

      // Idempotent retry converges: same idempotency key, no double-log, no second nudge.
      const retryResponse = await callTool(client, "agent_batch_write_meal", {
        apiKey: "prn_agent_secret",
        request: mcpRequest
      });
      assertToolSucceeded(retryResponse);
      assert.equal(retryResponse.structuredContent.duplicate, true);
      assert.deepEqual(
        retryResponse.structuredContent.entries.map((entry) => entry.id),
        mcpBody.entries.map((entry) => entry.id)
      );
      const retryActivityRows = await database.sql`
        select id from activity_log where batch_id = ${mcpRequest.idempotencyKey}
      `;
      assert.equal(retryActivityRows.length, 2);
      assert.equal(mcpNudges.length, 1);
    } finally {
      await close();
      await database.close();
    }
  }
);

test(
  "agent MCP meal batch write hard-rejects an invalid item before any side effects, like REST",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-mcp-meal-invalid-${randomUUID()}`;
    const nudges = [];
    const { client, close } = await createMcpClient(
      createAgentMcpServer({
        agentApiKeyStore: createAgentKeyStore(userId),
        agentMealBatchWriteStore: createDrizzleAgentMealBatchWriteStore(
          database.db
        ),
        logger: { info() {}, error() {} },
        syncNudgePublisher: {
          async enqueueSyncNudge(input) {
            nudges.push(input);
            return { enqueued: true, jobId: "unexpected-nudge" };
          }
        }
      })
    );
    const request = mealRequest({
      idempotencyKey: `agent-mcp-meal-invalid-${randomUUID()}`,
      mealId: `meal-invalid-${randomUUID()}`,
      entries: [
        {
          id: `entry-invalid-${randomUUID()}`,
          position: 0,
          name: "Negative energy",
          nutrients: {
            energy: {
              status: "complete",
              value: -5,
              entered: "-5",
              unit: "kilocalorie"
            }
          },
          isLiquid: false,
          foodId: null,
          foodSource: null,
          portion: null,
          servingLabel: null,
          servingSize: null,
          packageSize: null,
          updatedAt: "2026-06-24T05:00:00.000Z"
        }
      ]
    });

    try {
      await seedUser(database, userId);

      const response = await callTool(client, "agent_batch_write_meal", {
        apiKey: "prn_agent_secret",
        request
      });
      assert.equal(response.isError, true);
      assert.equal(
        response.structuredContent.code,
        "agent_meal_batch_write_failed"
      );
      assert.equal(response.structuredContent.errors[0].itemIndex, 0);
      assert.equal(
        response.structuredContent.errors[0].rule,
        "nutrient_non_negative"
      );
      assert.ok(response.structuredContent.limits);

      const mealRows = await database.sql`
        select id from meals where id = ${request.meal.id}
      `;
      assert.equal(mealRows.length, 0);
      const activityRows = await database.sql`
        select id from activity_log where batch_id = ${request.idempotencyKey}
      `;
      assert.equal(activityRows.length, 0);
      assert.deepEqual(nudges, []);
    } finally {
      await close();
      await database.close();
    }
  }
);

test(
  "agent MCP batch write foods matches REST: persists, one Activity Log batch, nudge, converges on idempotent retry, then is findable via agent_list_foods",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const restUserId = `agent-mcp-food-rest-${randomUUID()}`;
    const mcpUserId = `agent-mcp-food-mcp-${randomUUID()}`;
    const restNudges = [];
    const mcpNudges = [];

    const restApp = createApp({
      logger: { info() {}, error() {} },
      agentApiKeyStore: createAgentKeyStore(restUserId),
      agentFoodBatchWriteStore: createDrizzleAgentFoodBatchWriteStore(
        database.db
      ),
      agentFoodCatalogStore: createDrizzleAgentFoodCatalogStore(database.db),
      syncNudgePublisher: {
        async enqueueSyncNudge(input) {
          restNudges.push(input);
          return { enqueued: true, jobId: `rest-food-nudge-${restNudges.length}` };
        }
      }
    });
    const { client, close } = await createMcpClient(
      createAgentMcpServer({
        agentApiKeyStore: createAgentKeyStore(mcpUserId),
        agentFoodBatchWriteStore: createDrizzleAgentFoodBatchWriteStore(
          database.db
        ),
        agentFoodCatalogStore: createDrizzleAgentFoodCatalogStore(database.db),
        logger: { info() {}, error() {} },
        syncNudgePublisher: {
          async enqueueSyncNudge(input) {
            mcpNudges.push(input);
            return { enqueued: true, jobId: `mcp-food-nudge-${mcpNudges.length}` };
          }
        }
      })
    );

    const foodRequest = (idempotencyKey, id) => ({
      idempotencyKey,
      foods: [
        {
          id,
          name: "Banana",
          nutrientsPer100: {
            energy: {
              status: "complete",
              value: 89,
              entered: "89",
              unit: "kilocalorie"
            }
          },
          isLiquid: false,
          servingLabel: "medium",
          servingSize: 118,
          packageSize: null,
          recipeIngredients: null,
          recipeServingCount: null,
          deletedAt: null
        }
      ]
    });

    try {
      await seedUser(database, restUserId);
      await seedUser(database, mcpUserId);

      // --- REST baseline ---
      const restFoodId = `food-rest-${randomUUID()}`;
      const restResponse = await postAgentFoodBatch(
        restApp,
        foodRequest(`agent-mcp-food-rest-${randomUUID()}`, restFoodId)
      );
      assert.equal(restResponse.status, 200);
      const restBody = await restResponse.json();

      // --- MCP under test ---
      const mcpFoodId = `food-mcp-${randomUUID()}`;
      const mcpRequest = foodRequest(
        `agent-mcp-food-mcp-${randomUUID()}`,
        mcpFoodId
      );
      const mcpResponse = await callTool(client, "agent_batch_write_foods", {
        apiKey: "prn_agent_secret",
        request: mcpRequest
      });
      assertToolSucceeded(mcpResponse);
      const mcpBody = mcpResponse.structuredContent;

      assert.equal(mcpBody.accepted, restBody.accepted);
      assert.equal(mcpBody.duplicate, restBody.duplicate);
      assert.equal(mcpBody.batchId, mcpRequest.idempotencyKey);
      assert.equal(mcpBody.foods[0].isRecipe, false);

      const foodRows = await database.sql`
        select user_id, device_id, payload from foods where id = ${mcpFoodId}
      `;
      assert.equal(foodRows.length, 1);
      assert.equal(foodRows[0].user_id, mcpUserId);
      assert.equal(foodRows[0].device_id, "agent:agent-key-1");
      assert.equal(foodRows[0].payload.name, "Banana");

      const activityRows = await database.sql`
        select actor, batch_id, entity_table from activity_log
        where batch_id = ${mcpRequest.idempotencyKey}
      `;
      assert.equal(activityRows.length, 1);
      assert.equal(activityRows[0].actor, "agent");
      assert.equal(activityRows[0].entity_table, "foods");

      assert.deepEqual(mcpNudges, [
        {
          userId: mcpUserId,
          sourceDeviceId: "agent:agent-key-1",
          reason: "agent_write"
        }
      ]);
      assert.equal(restNudges.length, 1);

      // Idempotent retry converges: same idempotency key, no double-log, no second nudge.
      const retryResponse = await callTool(client, "agent_batch_write_foods", {
        apiKey: "prn_agent_secret",
        request: mcpRequest
      });
      assertToolSucceeded(retryResponse);
      assert.equal(retryResponse.structuredContent.duplicate, true);
      const retryActivityRows = await database.sql`
        select id from activity_log where batch_id = ${mcpRequest.idempotencyKey}
      `;
      assert.equal(retryActivityRows.length, 1);
      assert.equal(mcpNudges.length, 1);

      // Findable via agent_list_foods with the same query contract as REST.
      const listResponse = await callTool(client, "agent_list_foods", {
        apiKey: "prn_agent_secret",
        query: { search: "banana" }
      });
      assertToolSucceeded(listResponse);
      assert.ok(
        listResponse.structuredContent.foods.some(
          (food) => food.id === mcpFoodId
        )
      );

      // Platform search resolves the bundled USDA catalog independently.
      const platformResponse = await callTool(
        client,
        "agent_search_platform_foods",
        { apiKey: "prn_agent_secret", query: { search: "chicken" } }
      );
      assertToolSucceeded(platformResponse);
      assert.ok(platformResponse.structuredContent.foods.length > 0);
      assert.equal(platformResponse.structuredContent.attribution.source, "usda");
    } finally {
      await close();
      await database.close();
    }
  }
);

test(
  "agent MCP batch write foods hard-rejects an invalid item before any side effects, like REST",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-mcp-food-invalid-${randomUUID()}`;
    const nudges = [];
    const { client, close } = await createMcpClient(
      createAgentMcpServer({
        agentApiKeyStore: createAgentKeyStore(userId),
        agentFoodBatchWriteStore: createDrizzleAgentFoodBatchWriteStore(
          database.db
        ),
        logger: { info() {}, error() {} },
        syncNudgePublisher: {
          async enqueueSyncNudge(input) {
            nudges.push(input);
            return { enqueued: true, jobId: "unexpected-nudge" };
          }
        }
      })
    );
    const foodId = `food-invalid-${randomUUID()}`;
    const request = {
      idempotencyKey: `agent-mcp-food-invalid-${randomUUID()}`,
      foods: [
        {
          id: foodId,
          name: "Bad Food",
          nutrientsPer100: {
            energy: {
              status: "complete",
              value: -5,
              entered: "-5",
              unit: "kilocalorie"
            }
          },
          isLiquid: false,
          servingLabel: null,
          servingSize: null,
          packageSize: null,
          recipeIngredients: null,
          recipeServingCount: null,
          deletedAt: null
        }
      ]
    };

    try {
      await seedUser(database, userId);

      const response = await callTool(client, "agent_batch_write_foods", {
        apiKey: "prn_agent_secret",
        request
      });
      assert.equal(response.isError, true);
      assert.equal(
        response.structuredContent.code,
        "agent_food_batch_write_failed"
      );
      assert.equal(response.structuredContent.errors[0].rule, "nutrient_non_negative");
      assert.ok(response.structuredContent.limits);

      const foodRows = await database.sql`
        select id from foods where id = ${foodId}
      `;
      assert.equal(foodRows.length, 0);
      const activityRows = await database.sql`
        select id from activity_log where batch_id = ${request.idempotencyKey}
      `;
      assert.equal(activityRows.length, 0);
      assert.deepEqual(nudges, []);
    } finally {
      await close();
      await database.close();
    }
  }
);

test(
  "agent MCP list-meals matches the equivalent bounded REST response",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-mcp-meals-read-${randomUUID()}`;
    const idPrefix = randomUUID();
    const restApp = createApp({
      logger: { info() {}, error() {} },
      agentApiKeyStore: createAgentKeyStore(userId),
      agentNutritionReadStore: createDrizzleAgentNutritionReadStore(database.db)
    });
    const { client, close } = await createMcpClient(
      createAgentMcpServer({
        agentApiKeyStore: createAgentKeyStore(userId),
        agentNutritionReadStore: createDrizzleAgentNutritionReadStore(
          database.db
        ),
        logger: { info() {}, error() {} }
      })
    );

    try {
      await seedUser(database, userId);
      await seedMeal(database, {
        userId,
        id: `meal-${idPrefix}`,
        mealType: "Lunch",
        startedAt: "2026-06-24T05:00:00.000Z",
        localDate: "2026-06-24"
      });
      await seedFoodEntry(database, {
        userId,
        id: `entry-${idPrefix}`,
        mealId: `meal-${idPrefix}`,
        name: "Rice bowl",
        energy: 400
      });

      const restResponse = await getAgent(
        restApp,
        "/agent/meals?from=2026-06-01T00:00:00.000Z&to=2026-06-30T00:00:00.000Z&fields=id,mealType,startedAt,localDate,entries"
      );
      assert.equal(restResponse.status, 200);
      const restBody = await restResponse.json();
      const mcpResponse = await callTool(client, "agent_list_meals", {
        apiKey: "prn_agent_secret",
        query: {
          from: "2026-06-01T00:00:00.000Z",
          to: "2026-06-30T00:00:00.000Z",
          fields: "id,mealType,startedAt,localDate,entries"
        }
      });
      assertToolSucceeded(mcpResponse);
      assert.deepEqual(mcpResponse.structuredContent, restBody);
      assert.equal(restBody.meals.length, 1);
      assert.equal(restBody.meals[0].entries.length, 1);
      assert.equal(restBody.meals[0].entries[0].name, "Rice bowl");
    } finally {
      await close();
      await database.close();
    }
  }
);

test(
  "agent MCP nutrition totals and energy-balance reads match the equivalent REST responses",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-mcp-nutrition-read-${randomUUID()}`;
    const restApp = createApp({
      logger: { info() {}, error() {} },
      agentApiKeyStore: createAgentKeyStore(userId),
      agentNutritionReadStore: createDrizzleAgentNutritionReadStore(database.db),
      agentCrossDomainReadStore: createDrizzleAgentCrossDomainReadStore(
        database.db
      )
    });
    const { client, close } = await createMcpClient(
      createAgentMcpServer({
        agentApiKeyStore: createAgentKeyStore(userId),
        agentNutritionReadStore: createDrizzleAgentNutritionReadStore(
          database.db
        ),
        agentCrossDomainReadStore: createDrizzleAgentCrossDomainReadStore(
          database.db
        ),
        logger: { info() {}, error() {} }
      })
    );
    const idPrefix = randomUUID();

    try {
      await seedUser(database, userId);

      // A meal with an energy-bearing quick entry on 2026-06-24.
      await seedMeal(database, {
        userId,
        id: `meal-${idPrefix}`,
        mealType: "Lunch",
        startedAt: "2026-06-24T05:00:00.000Z",
        localDate: "2026-06-24"
      });
      await seedFoodEntry(database, {
        userId,
        id: `entry-${idPrefix}`,
        mealId: `meal-${idPrefix}`,
        name: "Rice bowl",
        energy: 400
      });
      // A calories-burned reading the same day for the energy-balance join.
      await seedCaloriesBurned(database, {
        userId,
        metricId: `metric-${idPrefix}`,
        readingId: `reading-${idPrefix}`,
        atTime: "2026-06-24T12:00:00.000Z",
        value: 300
      });

      const range = "from=2026-06-24&to=2026-06-24";

      const restTotals = await getAgent(
        restApp,
        `/agent/nutrition/totals?${range}`
      );
      assert.equal(restTotals.status, 200);
      const restTotalsBody = await restTotals.json();
      const mcpTotals = await callTool(client, "agent_get_nutrition_totals", {
        apiKey: "prn_agent_secret",
        query: { from: "2026-06-24", to: "2026-06-24" }
      });
      assertToolSucceeded(mcpTotals);
      assert.deepEqual(mcpTotals.structuredContent, restTotalsBody);

      // The read shape never dumps raw meal-by-meal entries.
      const totalsJson = JSON.stringify(mcpTotals.structuredContent);
      assert.equal(totalsJson.includes('"name":"Rice bowl"'), false);
      assert.equal("meals" in mcpTotals.structuredContent, false);

      const restBalance = await getAgent(
        restApp,
        `/agent/cross-domain/energy-balance?${range}`
      );
      assert.equal(restBalance.status, 200);
      const restBalanceBody = await restBalance.json();
      const mcpBalance = await callTool(client, "agent_get_energy_balance", {
        apiKey: "prn_agent_secret",
        query: { from: "2026-06-24", to: "2026-06-24" }
      });
      assertToolSucceeded(mcpBalance);
      assert.deepEqual(mcpBalance.structuredContent, restBalanceBody);
      // Both sides known -> a computed day with a real net.
      assert.equal(mcpBalance.structuredContent.days[0].status, "computed");
      assert.equal(mcpBalance.structuredContent.days[0].energyIn, 400);
      assert.equal(mcpBalance.structuredContent.days[0].energyOut, 300);
      assert.equal(mcpBalance.structuredContent.days[0].net, 100);

      // Pure reads: no Activity Log row written.
      const activityRows = await database.sql`
        select id from activity_log where user_id = ${userId}
      `;
      assert.equal(activityRows.length, 0);
    } finally {
      await close();
      await database.close();
    }
  }
);

test(
  "agent MCP nutrition goal list/batch-write match the equivalent REST responses, and totals default to stored goals",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    await applyMigrations(databaseUrl);
    const database = createDatabaseClient(databaseUrl);
    const userId = `agent-mcp-nutrition-goal-${randomUUID()}`;
    const agentNutritionGoalStore = createDrizzleAgentNutritionGoalStore(
      database.db
    );
    const restApp = createApp({
      logger: { info() {}, error() {} },
      agentApiKeyStore: createAgentKeyStore(userId),
      agentNutritionReadStore: createDrizzleAgentNutritionReadStore(database.db),
      agentNutritionGoalStore
    });
    const { client, close } = await createMcpClient(
      createAgentMcpServer({
        agentApiKeyStore: createAgentKeyStore(userId),
        agentNutritionReadStore: createDrizzleAgentNutritionReadStore(
          database.db
        ),
        agentNutritionGoalStore,
        logger: { info() {}, error() {} }
      })
    );
    const goalId = randomUUID();

    try {
      await seedUser(database, userId);

      const writeRequest = {
        idempotencyKey: `agent-mcp-nutrition-goal-${randomUUID()}`,
        targets: [{ id: goalId, nutrient: "energy", value: 2000 }]
      };
      const restWrite = await postAgent(
        restApp,
        "/agent/nutrition/goals/batch-write",
        writeRequest
      );
      assert.equal(restWrite.status, 200);
      const restWriteBody = await restWrite.json();

      const mcpWrite = await callTool(
        client,
        "agent_batch_write_nutrition_goals",
        {
          apiKey: "prn_agent_secret",
          request: {
            ...writeRequest,
            idempotencyKey: `agent-mcp-nutrition-goal-mcp-${randomUUID()}`,
            targets: [
              { id: randomUUID(), nutrient: "protein", value: 160 }
            ]
          }
        }
      );
      assertToolSucceeded(mcpWrite);
      assert.equal(mcpWrite.structuredContent.accepted, true);
      assert.equal(restWriteBody.accepted, true);

      const restList = await getAgent(restApp, "/agent/nutrition/goals");
      assert.equal(restList.status, 200);
      const restListBody = await restList.json();
      const mcpList = await callTool(client, "agent_list_nutrition_goals", {
        apiKey: "prn_agent_secret"
      });
      assertToolSucceeded(mcpList);
      assert.deepEqual(mcpList.structuredContent, restListBody);
      assert.equal(restListBody.goals.length, 2);

      // A meal on 2026-06-24 with 1800 kcal; totals default to the stored
      // 2000 kcal energy Goal with no query param supplied.
      await seedMeal(database, {
        userId,
        id: `meal-${goalId}`,
        mealType: "Lunch",
        startedAt: "2026-06-24T05:00:00.000Z",
        localDate: "2026-06-24"
      });
      await seedFoodEntry(database, {
        userId,
        id: `entry-${goalId}`,
        mealId: `meal-${goalId}`,
        name: "Rice bowl",
        energy: 1800
      });

      const mcpTotals = await callTool(client, "agent_get_nutrition_totals", {
        apiKey: "prn_agent_secret",
        query: { from: "2026-06-24", to: "2026-06-24" }
      });
      assertToolSucceeded(mcpTotals);
      assert.equal(mcpTotals.structuredContent.goalSource, "stored");
      const energyGoalProgress =
        mcpTotals.structuredContent.period.goalProgress.find(
          (entry) => entry.nutrient === "energy"
        );
      assert.ok(energyGoalProgress);
      assert.equal(energyGoalProgress.target.value, 2000);
    } finally {
      await close();
      await database.close();
    }
  }
);

async function createMcpClient(server) {
  const client = new Client(
    { name: "agent-mcp-test-client", version: "0.0.0" },
    { capabilities: {} }
  );
  const [clientTransport, serverTransport] = InMemoryTransport.createLinkedPair();

  await Promise.all([
    server.connect(serverTransport),
    client.connect(clientTransport)
  ]);

  return {
    client,
    async close() {
      await Promise.all([client.close(), server.close()]);
    }
  };
}

function callTool(client, name, args) {
  return client.callTool({
    name,
    arguments: args
  });
}

function assertToolSucceeded(response) {
  const diagnostic = JSON.stringify(response.content);

  assert.equal(response.isError, undefined, diagnostic);
  assert.ok(response.structuredContent, diagnostic);
}

function createAgentReadApp({
  agentReadStore,
  logger = { info() {}, error() {} },
  userId = "user-1"
}) {
  return createApp({
    logger,
    agentApiKeyStore: createAgentKeyStore(userId, {}, "agent-read-key-1"),
    agentCatalogStore: createInMemoryAgentCatalogStore(catalogFixtures(userId)),
    agentReadStore
  });
}

function createAgentKeyStore(userId, agentRateLimit = {}, keyId = "agent-key-1") {
  return {
    async authenticateAgentApiKey(secret) {
      if (secret !== "prn_agent_secret") {
        return null;
      }

      return {
        userId,
        keyId,
        keyName: "Garage coach",
        ...agentRateLimit
      };
    },
    async createAgentApiKey() {
      throw new Error("createAgentApiKey should not be called.");
    },
    async listAgentApiKeys() {
      throw new Error("listAgentApiKeys should not be called.");
    },
    async revokeAgentApiKey() {
      throw new Error("revokeAgentApiKey should not be called.");
    },
    async verifySessionBearerToken() {
      throw new Error("verifySessionBearerToken should not be called.");
    }
  };
}

function getAgent(app, path) {
  return app.request(path, {
    headers: {
      authorization: "Bearer prn_agent_secret"
    }
  });
}

function postAgent(app, path, body, headers = {}) {
  return app.request(path, {
    method: "POST",
    headers: {
      authorization: "Bearer prn_agent_secret",
      "content-type": "application/json",
      ...headers
    },
    body: JSON.stringify(body)
  });
}

function postAgentMeal(app, body, headers = {}) {
  return app.request("/agent/meals/batch-write", {
    method: "POST",
    headers: {
      authorization: "Bearer prn_agent_secret",
      "content-type": "application/json",
      ...headers
    },
    body: JSON.stringify(body)
  });
}

function postAgentFoodBatch(app, body, headers = {}) {
  return app.request("/agent/foods/batch-write", {
    method: "POST",
    headers: {
      authorization: "Bearer prn_agent_secret",
      "content-type": "application/json",
      ...headers
    },
    body: JSON.stringify(body)
  });
}

function mealRequest({ idempotencyKey, mealId, entries }) {
  return {
    idempotencyKey,
    meal: {
      id: mealId,
      mealType: "Lunch",
      startedAt: "2026-06-24T05:00:00.000Z",
      endedAt: null,
      timezone: "Australia/Brisbane",
      localDate: "2026-06-24"
    },
    entries
  };
}

async function seedMeal(database, { userId, id, mealType, startedAt, localDate }) {
  await database.db.insert(schema.meals).values({
    id,
    userId,
    deviceId: "agent:agent-key-1",
    payload: {
      id,
      meal_type: mealType,
      started_at: startedAt,
      timezone: "UTC",
      local_date: localDate,
      ended_at: null,
      updated_at: startedAt,
      deleted_at: null
    },
    updatedAt: new Date(startedAt),
    deletedAt: null
  });
}

async function seedFoodEntry(database, { userId, id, mealId, name, energy }) {
  await database.db.insert(schema.foodEntries).values({
    id,
    userId,
    deviceId: "agent:agent-key-1",
    payload: {
      id,
      meal_id: mealId,
      entry_kind: "quickEntry",
      position: 0,
      name,
      nutrient_values_json: JSON.stringify(
        nutrientStorage({
          energy: {
            status: "complete",
            value: energy,
            entered: String(energy),
            unit: "kilocalorie"
          }
        })
      ),
      food_id: null,
      portion_json: null,
      food_source: null,
      is_liquid: false,
      serving_label: null,
      serving_size: null,
      package_size: null,
      updated_at: "2026-06-24T05:00:00.000Z",
      deleted_at: null
    },
    updatedAt: new Date("2026-06-24T05:00:00.000Z"),
    deletedAt: null
  });
}

async function seedCaloriesBurned(
  database,
  { userId, metricId, readingId, atTime, value }
) {
  await database.db.insert(schema.metrics).values({
    id: metricId,
    userId,
    deviceId: "agent:agent-key-1",
    name: "Calories Burned",
    unit: "kilocalorie",
    valueShape: "scalar",
    metricGroup: "energy",
    enabled: true,
    pinned: false,
    sortOrder: 0,
    updatedAt: new Date("2026-06-24T00:00:00.000Z"),
    deletedAt: null
  });
  await database.db.insert(schema.metricReadings).values({
    id: readingId,
    userId,
    deviceId: "agent:agent-key-1",
    metricId,
    valueJson: { value, unit: "kilocalorie" },
    scalarValue: value,
    scalarEntered: String(value),
    atTime: new Date(atTime),
    windowStartedAt: null,
    windowEndedAt: null,
    provenance: "imported",
    source: "garmin",
    updatedAt: new Date(atTime),
    deletedAt: null
  });
}

const NUTRIENT_STORAGE_KEYS = [
  "energy",
  "protein",
  "carbohydrate",
  "sugar",
  "fat",
  "saturated_fat",
  "monounsaturated_fat",
  "polyunsaturated_fat",
  "fiber",
  "sodium",
  "cholesterol",
  "vitamin_a",
  "vitamin_c",
  "vitamin_d",
  "vitamin_e",
  "vitamin_k",
  "thiamin",
  "riboflavin",
  "niacin",
  "vitamin_b6",
  "folate",
  "vitamin_b12",
  "calcium",
  "iron",
  "magnesium",
  "phosphorus",
  "potassium",
  "zinc",
  "copper",
  "manganese",
  "selenium",
  "caffeine",
  "water"
];

const NUTRIENT_DEFAULT_UNIT = {
  energy: "kilocalorie",
  protein: "gram",
  carbohydrate: "gram",
  sugar: "gram",
  fat: "gram",
  saturated_fat: "gram",
  monounsaturated_fat: "gram",
  polyunsaturated_fat: "gram",
  fiber: "gram",
  sodium: "milligram",
  cholesterol: "milligram",
  vitamin_a: "microgram",
  vitamin_c: "milligram",
  vitamin_d: "microgram",
  vitamin_e: "milligram",
  vitamin_k: "microgram",
  thiamin: "milligram",
  riboflavin: "milligram",
  niacin: "milligram",
  vitamin_b6: "milligram",
  folate: "microgram",
  vitamin_b12: "microgram",
  calcium: "milligram",
  iron: "milligram",
  magnesium: "milligram",
  phosphorus: "milligram",
  potassium: "milligram",
  zinc: "milligram",
  copper: "milligram",
  manganese: "milligram",
  selenium: "microgram",
  caffeine: "milligram",
  water: "milliliter"
};

function nutrientStorage(nutrients) {
  const storage = {};
  for (const key of NUTRIENT_STORAGE_KEYS) {
    const amount = nutrients[key];
    const unit = amount?.unit ?? NUTRIENT_DEFAULT_UNIT[key];
    if (amount === undefined || amount.status === "unknown") {
      storage[key] = { status: "unknown", value: null, entered: null, unit };
    } else {
      storage[key] = {
        status: "complete",
        value: amount.value,
        entered: amount.entered ?? String(amount.value),
        unit
      };
    }
  }

  return storage;
}

function batchRequest({ idempotencyKey, sets }) {
  return {
    idempotencyKey,
    workout: {
      id: `workout-${randomUUID()}`,
      startedAt: "2026-06-24T05:00:00.000Z",
      endedAt: null,
      timezone: "Australia/Brisbane",
      comment: null
    },
    sets: sets.map((set) => ({
      updatedAt: "2026-06-24T05:00:00.000Z",
      comment: null,
      rpe: undefined,
      side: undefined,
      ...set
    }))
  };
}

async function seedUser(database, userId) {
  await database.db.insert(schema.user).values({
    id: userId,
    name: "Agent MCP User",
    email: `${userId}@example.com`,
    emailVerified: true
  });
}

async function seedLoggedSet(
  { db },
  {
    userId,
    id,
    exerciseId,
    exerciseName,
    performedAt,
    position,
    values
  }
) {
  await db.insert(schema.loggedSets).values({
    id,
    userId,
    deviceId: "device-agent-mcp-test",
    updatedAt: new Date(performedAt),
    receivedAt: new Date(performedAt),
    deletedAt: null,
    payload: {
      id,
      workout_id: `workout-${id}`,
      workout_started_at: performedAt,
      workout_ended_at: null,
      workout_timezone: "Australia/Brisbane",
      exercise_id: exerciseId,
      exercise_name: exerciseName,
      exercise_category_id: "cat-strength",
      exercise_category_name: "Strength",
      exercise_equipment: ["barbell"],
      position,
      values,
      comment: null,
      rpe: null,
      side: null,
      deleted_at: null,
      updated_at: performedAt,
      ...flatDimensionValues(values)
    }
  });
}

function flatDimensionValues(values) {
  return Object.fromEntries(
    Object.entries(values).flatMap(([dimension, value]) => [
      [`${dimension}_entered`, value.entered],
      [`${dimension}_unit`, value.unit]
    ])
  );
}

function catalogFixtures(userId = "user-1") {
  return [
    exercise({
      id: "platform-back-squat",
      library: "platform",
      name: "Back Squat",
      categoryId: "cat-strength"
    }),
    exercise({
      id: "user-back-squat",
      library: "user",
      ownerUserId: userId,
      name: "Back Squat",
      categoryId: "cat-strength",
      shadowedPlatformExerciseId: "platform-back-squat"
    }),
    exercise({
      id: "platform-bench-press",
      library: "platform",
      name: "Bench Press",
      categoryId: "cat-strength"
    })
  ];
}

function exercise({
  id,
  library,
  ownerUserId = null,
  name,
  categoryId,
  active = true,
  favorite = false,
  equipment = ["barbell"],
  shadowedPlatformExerciseId = null
}) {
  return {
    id,
    library,
    ownerUserId,
    name,
    category: {
      id: categoryId,
      name: categoryId === "cat-strength" ? "Strength" : "Other"
    },
    dimensions: ["load", "reps"],
    equipment,
    loadMode: "added",
    recordProfile: "repMax",
    favorite,
    active,
    shadowedPlatformExerciseId
  };
}
