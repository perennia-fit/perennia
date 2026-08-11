import { sql } from "drizzle-orm";
import {
  boolean,
  customType,
  doublePrecision,
  index,
  integer,
  jsonb,
  pgTable,
  text,
  timestamp,
  uniqueIndex
} from "drizzle-orm/pg-core";

const createdAt = () =>
  timestamp("createdAt", { withTimezone: true }).notNull().defaultNow();
const updatedAt = () =>
  timestamp("updatedAt", { withTimezone: true }).notNull().defaultNow();
const bytea = customType<{ data: Buffer; driverData: Buffer }>({
  dataType() {
    return "bytea";
  }
});

export const user = pgTable(
  "user",
  {
    id: text("id").primaryKey(),
    name: text("name").notNull(),
    email: text("email").notNull(),
    emailVerified: boolean("emailVerified").notNull().default(false),
    image: text("image"),
    deletionRequestedAt: timestamp("deletion_requested_at", {
      withTimezone: true
    }),
    createdAt: createdAt(),
    updatedAt: updatedAt()
  },
  (table) => ({
    emailUnique: uniqueIndex("user_email_unique").on(table.email)
  })
);

export const session = pgTable(
  "session",
  {
    id: text("id").primaryKey(),
    expiresAt: timestamp("expiresAt", { withTimezone: true }).notNull(),
    token: text("token").notNull(),
    createdAt: createdAt(),
    updatedAt: updatedAt(),
    ipAddress: text("ipAddress"),
    userAgent: text("userAgent"),
    userId: text("userId")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" })
  },
  (table) => ({
    tokenUnique: uniqueIndex("session_token_unique").on(table.token),
    userIdIndex: index("session_user_id_index").on(table.userId)
  })
);

export const account = pgTable(
  "account",
  {
    id: text("id").primaryKey(),
    accountId: text("accountId").notNull(),
    providerId: text("providerId").notNull(),
    userId: text("userId")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    accessToken: text("accessToken"),
    refreshToken: text("refreshToken"),
    idToken: text("idToken"),
    accessTokenExpiresAt: timestamp("accessTokenExpiresAt", {
      withTimezone: true
    }),
    refreshTokenExpiresAt: timestamp("refreshTokenExpiresAt", {
      withTimezone: true
    }),
    scope: text("scope"),
    password: text("password"),
    createdAt: createdAt(),
    updatedAt: updatedAt()
  },
  (table) => ({
    userIdIndex: index("account_user_id_index").on(table.userId),
    providerAccountUnique: uniqueIndex("account_provider_account_unique").on(
      table.providerId,
      table.accountId
    )
  })
);

export const verification = pgTable("verification", {
  id: text("id").primaryKey(),
  identifier: text("identifier").notNull(),
  value: text("value").notNull(),
  expiresAt: timestamp("expiresAt", { withTimezone: true }).notNull(),
  createdAt: createdAt(),
  updatedAt: updatedAt()
});

export const apikey = pgTable(
  "apikey",
  {
    id: text("id").primaryKey(),
    configId: text("configId").notNull().default("default"),
    name: text("name"),
    start: text("start"),
    prefix: text("prefix"),
    key: text("key").notNull(),
    referenceId: text("referenceId")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    refillInterval: integer("refillInterval"),
    refillAmount: integer("refillAmount"),
    lastRefillAt: timestamp("lastRefillAt", { withTimezone: true }),
    enabled: boolean("enabled").notNull().default(true),
    rateLimitEnabled: boolean("rateLimitEnabled").notNull().default(true),
    rateLimitTimeWindow: integer("rateLimitTimeWindow").default(86400000),
    rateLimitMax: integer("rateLimitMax").default(10),
    requestCount: integer("requestCount").notNull().default(0),
    remaining: integer("remaining"),
    lastRequest: timestamp("lastRequest", { withTimezone: true }),
    expiresAt: timestamp("expiresAt", { withTimezone: true }),
    createdAt: createdAt(),
    updatedAt: updatedAt(),
    permissions: text("permissions"),
    metadata: text("metadata")
  },
  (table) => ({
    configIdIndex: index("apikey_config_id_index").on(table.configId),
    keyIndex: index("apikey_key_index").on(table.key),
    referenceIdIndex: index("apikey_reference_id_index").on(table.referenceId)
  })
);

export const integrationStatuses = pgTable(
  "integration_statuses",
  {
    id: text("id").primaryKey(),
    userId: text("user_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    credentialId: text("credential_id").notNull(),
    credentialName: text("credential_name"),
    source: text("source").notNull(),
    condition: text("condition").notNull(),
    recoveryAction: text("recovery_action").notNull(),
    lastSuccessfulAt: timestamp("last_successful_at", {
      withTimezone: true
    }),
    firstFailureAt: timestamp("first_failure_at", { withTimezone: true }),
    lastFailureAt: timestamp("last_failure_at", { withTimezone: true }),
    failureKind: text("failure_kind"),
    trigger: text("trigger"),
    retryAfterSeconds: integer("retry_after_seconds"),
    nextAttemptAt: timestamp("next_attempt_at", { withTimezone: true }),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull(),
    receivedAt: timestamp("received_at", { withTimezone: true })
      .notNull()
      .defaultNow()
  },
  (table) => ({
    userSourceCredentialUnique: uniqueIndex(
      "integration_statuses_user_source_credential_unique"
    ).on(table.userId, table.source, table.credentialId),
    userUpdatedAtIndex: index("integration_statuses_user_updated_at_index").on(
      table.userId,
      table.updatedAt
    )
  })
);

export const garminOAuthConnections = pgTable(
  "garmin_oauth_connections",
  {
    id: text("id").primaryKey(),
    userId: text("user_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    source: text("source").notNull(),
    credentialName: text("credential_name").notNull(),
    providerUserId: text("provider_user_id"),
    scope: text("scope"),
    encryptedRefreshToken: text("encrypted_refresh_token"),
    accessTokenExpiresAt: timestamp("access_token_expires_at", {
      withTimezone: true
    }),
    connectedAt: timestamp("connected_at", { withTimezone: true }).notNull(),
    revokedAt: timestamp("revoked_at", { withTimezone: true }),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull(),
    receivedAt: timestamp("received_at", { withTimezone: true })
      .notNull()
      .defaultNow()
  },
  (table) => ({
    userSourceUnique: uniqueIndex("garmin_oauth_connections_user_source_unique").on(
      table.userId,
      table.source
    ),
    userUpdatedAtIndex: index("garmin_oauth_connections_user_updated_at_index").on(
      table.userId,
      table.updatedAt
    )
  })
);

export const integrationDataClassConsents = pgTable(
  "integration_data_class_consents",
  {
    id: text("id").primaryKey(),
    userId: text("user_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    deviceId: text("device_id").notNull(),
    credentialId: text("credential_id").notNull(),
    dataClass: text("data_class").notNull(),
    enabled: boolean("enabled").notNull().default(false),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull(),
    deletedAt: timestamp("deleted_at", { withTimezone: true }),
    receivedAt: timestamp("received_at", { withTimezone: true })
      .notNull()
      .defaultNow()
  },
  (table) => ({
    userCredentialDataClassUnique: uniqueIndex(
      "integration_data_class_consents_user_credential_data_class_unique"
    ).on(table.userId, table.credentialId, table.dataClass),
    userUpdatedAtIndex: index(
      "integration_data_class_consents_user_updated_at_index"
    ).on(table.userId, table.updatedAt)
  })
);

export const loggedSets = pgTable(
  "logged_sets",
  {
    id: text("id").primaryKey(),
    userId: text("user_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    deviceId: text("device_id").notNull(),
    payload: jsonb("payload").$type<Record<string, unknown>>().notNull(),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull(),
    deletedAt: timestamp("deleted_at", { withTimezone: true }),
    receivedAt: timestamp("received_at", { withTimezone: true })
      .notNull()
      .defaultNow()
  },
  (table) => ({
    userUpdatedAtIndex: index("logged_sets_user_updated_at_index").on(
      table.userId,
      table.updatedAt
    )
  })
);

export const meals = pgTable(
  "meals",
  {
    id: text("id").primaryKey(),
    userId: text("user_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    deviceId: text("device_id").notNull(),
    payload: jsonb("payload").$type<Record<string, unknown>>().notNull(),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull(),
    deletedAt: timestamp("deleted_at", { withTimezone: true }),
    receivedAt: timestamp("received_at", { withTimezone: true })
      .notNull()
      .defaultNow()
  },
  (table) => ({
    userUpdatedAtIndex: index("meals_user_updated_at_index").on(
      table.userId,
      table.updatedAt
    )
  })
);

export const foodEntries = pgTable(
  "food_entries",
  {
    id: text("id").primaryKey(),
    userId: text("user_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    deviceId: text("device_id").notNull(),
    payload: jsonb("payload").$type<Record<string, unknown>>().notNull(),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull(),
    deletedAt: timestamp("deleted_at", { withTimezone: true }),
    receivedAt: timestamp("received_at", { withTimezone: true })
      .notNull()
      .defaultNow()
  },
  (table) => ({
    userUpdatedAtIndex: index("food_entries_user_updated_at_index").on(
      table.userId,
      table.updatedAt
    )
  })
);

// A user's per-nutrient `Goal` target (NUTRITION.md §4/§7) on the
// opaque-payload sync rails: the server never inspects domain columns,
// exactly like meals/food entries. Goal targets are configuration, never a
// stored derived value — the payload holds only the target the
// user typed. Archives via the in-payload deleted_at; merge by UUID,
// tenant-isolated by userId.
export const nutritionGoals = pgTable(
  "nutrition_goals",
  {
    id: text("id").primaryKey(),
    userId: text("user_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    deviceId: text("device_id").notNull(),
    payload: jsonb("payload").$type<Record<string, unknown>>().notNull(),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull(),
    deletedAt: timestamp("deleted_at", { withTimezone: true }),
    receivedAt: timestamp("received_at", { withTimezone: true })
      .notNull()
      .defaultNow()
  },
  (table) => ({
    userUpdatedAtIndex: index("nutrition_goals_user_updated_at_index").on(
      table.userId,
      table.updatedAt
    )
  })
);

// The account-level half of a user's Settings as a synced singleton
// on the opaque-payload sync rails: one row per user, keyed by a stable
// well-known client id (never a UUIDv7 list). The server never inspects domain
// columns, exactly like nutrition goals. Device-level settings (screen-on,
// crash reporting, auto-backup) stay in the device's local JSON and never reach
// this table. Overwritten in place via LWW (updated_at); a settings row is
// never archived, so deleted_at stays null. Merge by id, tenant-isolated by
// userId.
export const userSettings = pgTable(
  "user_settings",
  {
    id: text("id").primaryKey(),
    userId: text("user_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    deviceId: text("device_id").notNull(),
    payload: jsonb("payload").$type<Record<string, unknown>>().notNull(),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull(),
    deletedAt: timestamp("deleted_at", { withTimezone: true }),
    receivedAt: timestamp("received_at", { withTimezone: true })
      .notNull()
      .defaultNow()
  },
  (table) => ({
    userUpdatedAtIndex: index("user_settings_user_updated_at_index").on(
      table.userId,
      table.updatedAt
    )
  })
);

// A user-authored `Food` (CONTEXT.md, NUTRITION.md §3) on the opaque-payload
// sync rails: the server never inspects domain columns, exactly like
// meals/food entries. Covers both a plain User Food and a Recipe (a Food whose
// payload carries its own flat ingredient snapshot) — both are always
// `food_source: user`. Platform reference data (USDA/Open Food Facts) never
// reaches this table on the client and so never syncs (mirrors the
// Platform exercise library exclusion). Archives via the in-payload
// deleted_at; merge by UUID, tenant-isolated by userId.
export const foods = pgTable(
  "foods",
  {
    id: text("id").primaryKey(),
    userId: text("user_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    deviceId: text("device_id").notNull(),
    payload: jsonb("payload").$type<Record<string, unknown>>().notNull(),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull(),
    deletedAt: timestamp("deleted_at", { withTimezone: true }),
    receivedAt: timestamp("received_at", { withTimezone: true })
      .notNull()
      .defaultNow()
  },
  (table) => ({
    userUpdatedAtIndex: index("foods_user_updated_at_index").on(
      table.userId,
      table.updatedAt
    )
  })
);

// A user's `Meal Type` (CONTEXT.md, NUTRITION.md §3) on the opaque-payload
// sync rails, mirroring `foods` exactly. The client seeds a small deterministic
// default set (Breakfast/Lunch/Dinner/Snack, stable ids) the first time it is
// needed; those rows are ordinary user-editable/archivable rows (unlike the
// Platform exercise library) so they sync like any other Meal Type.
export const mealTypes = pgTable(
  "meal_types",
  {
    id: text("id").primaryKey(),
    userId: text("user_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    deviceId: text("device_id").notNull(),
    payload: jsonb("payload").$type<Record<string, unknown>>().notNull(),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull(),
    deletedAt: timestamp("deleted_at", { withTimezone: true }),
    receivedAt: timestamp("received_at", { withTimezone: true })
      .notNull()
      .defaultNow()
  },
  (table) => ({
    userUpdatedAtIndex: index("meal_types_user_updated_at_index").on(
      table.userId,
      table.updatedAt
    )
  })
);

// A user's `Exercise Category` (CONTEXT.md) on the opaque-payload
// sync rails: the server never inspects domain columns, exactly like
// meals/compounds. Only User Library categories sync — the Platform Library
// is a deterministic bundled seed and never crosses the server.
// Archives via the in-payload deleted_at; merge by UUID, tenant-isolated by
// userId.
export const exerciseCategories = pgTable(
  "exercise_categories",
  {
    id: text("id").primaryKey(),
    userId: text("user_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    deviceId: text("device_id").notNull(),
    payload: jsonb("payload").$type<Record<string, unknown>>().notNull(),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull(),
    deletedAt: timestamp("deleted_at", { withTimezone: true }),
    receivedAt: timestamp("received_at", { withTimezone: true })
      .notNull()
      .defaultNow()
  },
  (table) => ({
    userUpdatedAtIndex: index(
      "exercise_categories_user_updated_at_index"
    ).on(table.userId, table.updatedAt)
  })
);

// A user's `Exercise` (CONTEXT.md) on the opaque-payload sync rails,
// mirroring `exercise_categories` exactly. Covers both User Library exercises
// and a user's customization of a Platform exercise (a shadowing copy per
//); the Platform Library itself never syncs.
export const exercises = pgTable(
  "exercises",
  {
    id: text("id").primaryKey(),
    userId: text("user_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    deviceId: text("device_id").notNull(),
    payload: jsonb("payload").$type<Record<string, unknown>>().notNull(),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull(),
    deletedAt: timestamp("deleted_at", { withTimezone: true }),
    receivedAt: timestamp("received_at", { withTimezone: true })
      .notNull()
      .defaultNow()
  },
  (table) => ({
    userUpdatedAtIndex: index("exercises_user_updated_at_index").on(
      table.userId,
      table.updatedAt
    )
  })
);

// Protocols catalogue entry (CONTEXT.md `Compound`) on the opaque-payload sync
// rails: the server never inspects domain columns, exactly like meals/food
// entries. Archives via the in-payload deleted_at (PROTOCOLS.md §7); merge by
// UUID, tenant-isolated by userId.
export const compounds = pgTable(
  "compounds",
  {
    id: text("id").primaryKey(),
    userId: text("user_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    deviceId: text("device_id").notNull(),
    payload: jsonb("payload").$type<Record<string, unknown>>().notNull(),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull(),
    deletedAt: timestamp("deleted_at", { withTimezone: true }),
    receivedAt: timestamp("received_at", { withTimezone: true })
      .notNull()
      .defaultNow()
  },
  (table) => ({
    userUpdatedAtIndex: index("compounds_user_updated_at_index").on(
      table.userId,
      table.updatedAt
    )
  })
);

// A single logged administration (CONTEXT.md `Dose`) on the opaque-payload sync
// rails. The Dose is a SELF-CONTAINED snapshot: the payload carries
// the Compound name + strength frozen at log time, so it round-trips even if the
// Compound row is absent or archived on the other device. Hard-deletes to a
// tombstone via the in-payload deleted_at (PROTOCOLS.md §7); no cascades.
export const doses = pgTable(
  "doses",
  {
    id: text("id").primaryKey(),
    userId: text("user_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    deviceId: text("device_id").notNull(),
    payload: jsonb("payload").$type<Record<string, unknown>>().notNull(),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull(),
    deletedAt: timestamp("deleted_at", { withTimezone: true }),
    receivedAt: timestamp("received_at", { withTimezone: true })
      .notNull()
      .defaultNow()
  },
  (table) => ({
    userUpdatedAtIndex: index("doses_user_updated_at_index").on(
      table.userId,
      table.updatedAt
    )
  })
);

// A `Protocol` (CONTEXT.md, PROTOCOLS.md §1.4/§7) on the opaque-payload sync
// rails: the server never inspects domain columns, exactly like
// meals/compounds. Archives via the in-payload deleted_at; merge by UUID,
// tenant-isolated by userId. Never cascades to a Dose.
export const protocols = pgTable(
  "protocols",
  {
    id: text("id").primaryKey(),
    userId: text("user_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    deviceId: text("device_id").notNull(),
    payload: jsonb("payload").$type<Record<string, unknown>>().notNull(),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull(),
    deletedAt: timestamp("deleted_at", { withTimezone: true }),
    receivedAt: timestamp("received_at", { withTimezone: true })
      .notNull()
      .defaultNow()
  },
  (table) => ({
    userUpdatedAtIndex: index("protocols_user_updated_at_index").on(
      table.userId,
      table.updatedAt
    )
  })
);

// A `Protocol`'s ordered member `Compound` (PROTOCOLS.md §1.4) on the
// opaque-payload sync rails, mirroring `protocols` exactly.
export const protocolCompounds = pgTable(
  "protocol_compounds",
  {
    id: text("id").primaryKey(),
    userId: text("user_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    deviceId: text("device_id").notNull(),
    payload: jsonb("payload").$type<Record<string, unknown>>().notNull(),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull(),
    deletedAt: timestamp("deleted_at", { withTimezone: true }),
    receivedAt: timestamp("received_at", { withTimezone: true })
      .notNull()
      .defaultNow()
  },
  (table) => ({
    userUpdatedAtIndex: index(
      "protocol_compounds_user_updated_at_index"
    ).on(table.userId, table.updatedAt)
  })
);

// A `Schedule` (CONTEXT.md, PROTOCOLS.md §1.4/§7) on the opaque-payload sync
// rails, mirroring `protocols` exactly. Purely prescriptive plan data; never
// touches a logged Dose.
export const schedules = pgTable(
  "schedules",
  {
    id: text("id").primaryKey(),
    userId: text("user_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    deviceId: text("device_id").notNull(),
    payload: jsonb("payload").$type<Record<string, unknown>>().notNull(),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull(),
    deletedAt: timestamp("deleted_at", { withTimezone: true }),
    receivedAt: timestamp("received_at", { withTimezone: true })
      .notNull()
      .defaultNow()
  },
  (table) => ({
    userUpdatedAtIndex: index("schedules_user_updated_at_index").on(
      table.userId,
      table.updatedAt
    )
  })
);

// A `Protocol`'s declared target outcome (PROTOCOLS.md §1.4/§4) on the
// opaque-payload sync rails, mirroring `protocols` exactly. Plan data only;
// no analysis computed or stored here.
export const protocolTargetOutcomes = pgTable(
  "protocol_target_outcomes",
  {
    id: text("id").primaryKey(),
    userId: text("user_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    deviceId: text("device_id").notNull(),
    payload: jsonb("payload").$type<Record<string, unknown>>().notNull(),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull(),
    deletedAt: timestamp("deleted_at", { withTimezone: true }),
    receivedAt: timestamp("received_at", { withTimezone: true })
      .notNull()
      .defaultNow()
  },
  (table) => ({
    userUpdatedAtIndex: index(
      "protocol_target_outcomes_user_updated_at_index"
    ).on(table.userId, table.updatedAt)
  })
);

// A redesigned `Routine` is a curated collection of Workout Templates with an
// optional Cadence (ROUTINES.md). It remains an opaque LWW row on the server;
// RoutineEntries carry membership and TemplateLinks preserve materialization
// provenance. No plan-row archive cascades to a logged Workout/LoggedSet.
export const routines = pgTable(
  "routines",
  {
    id: text("id").primaryKey(),
    userId: text("user_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    deviceId: text("device_id").notNull(),
    payload: jsonb("payload").$type<Record<string, unknown>>().notNull(),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull(),
    deletedAt: timestamp("deleted_at", { withTimezone: true }),
    receivedAt: timestamp("received_at", { withTimezone: true })
      .notNull()
      .defaultNow()
  },
  (table) => ({
    userUpdatedAtIndex: index("routines_user_updated_at_index").on(
      table.userId,
      table.updatedAt
    )
  })
);

// The redesigned authored plan tree rides the ordinary opaque-payload LWW
// rails. The server deliberately knows only the sync envelope; domain
// validation and FK ordering live at the client/agent boundaries, while every
// table remains tenant-isolated by `user_id` on write (ROUTINES.md §6).
function opaqueSyncTable(tableName: string, userUpdatedAtIndexName: string) {
  return pgTable(
    tableName,
    {
      id: text("id").primaryKey(),
      userId: text("user_id")
        .notNull()
        .references(() => user.id, { onDelete: "cascade" }),
      deviceId: text("device_id").notNull(),
      payload: jsonb("payload").$type<Record<string, unknown>>().notNull(),
      updatedAt: timestamp("updated_at", { withTimezone: true }).notNull(),
      deletedAt: timestamp("deleted_at", { withTimezone: true }),
      receivedAt: timestamp("received_at", { withTimezone: true })
        .notNull()
        .defaultNow()
    },
    (table) => ({
      userUpdatedAtIndex: index(userUpdatedAtIndexName).on(
        table.userId,
        table.updatedAt
      ),
      ...(tableName === "workout_exercises"
        ? {
            workoutIdIndex: index(
              "workout_exercises_user_workout_id_index"
            ).on(
              table.userId,
              sql`(${table.payload} ->> 'workout_id')`
            )
          }
        : {}),
      ...(tableName === "exercise_groups"
        ? {
            workoutIdIndex: index(
              "exercise_groups_user_workout_id_index"
            ).on(
              table.userId,
              sql`(${table.payload} ->> 'workout_id')`
            )
          }
        : {}),
      ...(tableName === "exercise_group_members"
        ? {
            groupIdIndex: index(
              "exercise_group_members_user_group_id_index"
            ).on(
              table.userId,
              sql`(${table.payload} ->> 'group_id')`
            ),
            workoutExerciseIdIndex: index(
              "exercise_group_members_user_workout_exercise_id_index"
            ).on(
              table.userId,
              sql`(${table.payload} ->> 'workout_exercise_id')`
            )
          }
        : {})
    })
  );
}

export const workoutSessions = opaqueSyncTable(
  "workout_sessions",
  "workout_sessions_user_updated_at_index"
);
export const workoutExercises = opaqueSyncTable(
  "workout_exercises",
  "workout_exercises_user_updated_at_index"
);
export const exerciseGroups = opaqueSyncTable(
  "exercise_groups",
  "exercise_groups_user_updated_at_index"
);
export const exerciseGroupMembers = opaqueSyncTable(
  "exercise_group_members",
  "exercise_group_members_user_updated_at_index"
);
export const workoutTemplates = opaqueSyncTable(
  "workout_templates",
  "workout_templates_user_updated_at_index"
);
export const templateExercises = opaqueSyncTable(
  "template_exercises",
  "template_exercises_user_updated_at_index"
);
export const prescriptions = opaqueSyncTable(
  "prescriptions",
  "prescriptions_user_updated_at_index"
);
export const templateGroups = opaqueSyncTable(
  "template_groups",
  "template_groups_user_updated_at_index"
);
export const templateGroupMembers = opaqueSyncTable(
  "template_group_members",
  "template_group_members_user_updated_at_index"
);
export const routineEntries = opaqueSyncTable(
  "routine_entries",
  "routine_entries_user_updated_at_index"
);
export const templateLinks = opaqueSyncTable(
  "template_links",
  "template_links_user_updated_at_index"
);

export const metrics = pgTable(
  "metrics",
  {
    id: text("id").primaryKey(),
    userId: text("user_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    deviceId: text("device_id").notNull(),
    name: text("name").notNull(),
    unit: text("unit").notNull(),
    valueShape: text("value_shape").notNull(),
    metricGroup: text("metric_group").notNull(),
    goalType: text("goal_type"),
    goalTargetValue: doublePrecision("goal_target_value"),
    enabled: boolean("enabled").notNull().default(true),
    pinned: boolean("pinned").notNull().default(false),
    sortOrder: integer("sort_order").notNull(),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull(),
    deletedAt: timestamp("deleted_at", { withTimezone: true }),
    receivedAt: timestamp("received_at", { withTimezone: true })
      .notNull()
      .defaultNow()
  },
  (table) => ({
    userUpdatedAtIndex: index("metrics_user_updated_at_index").on(
      table.userId,
      table.updatedAt
    ),
    userSortOrderIndex: index("metrics_user_sort_order_index").on(
      table.userId,
      table.sortOrder
    )
  })
);

export const metricReadings = pgTable(
  "metric_readings",
  {
    id: text("id").primaryKey(),
    userId: text("user_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    deviceId: text("device_id").notNull(),
    metricId: text("metric_id")
      .notNull()
      .references(() => metrics.id),
    externalActivityId: text("external_activity_id"),
    valueJson: jsonb("value_json").$type<Record<string, unknown>>().notNull(),
    scalarValue: doublePrecision("scalar_value"),
    scalarEntered: text("scalar_entered"),
    atTime: timestamp("at_time", { withTimezone: true }),
    windowStartedAt: timestamp("window_started_at", { withTimezone: true }),
    windowEndedAt: timestamp("window_ended_at", { withTimezone: true }),
    provenance: text("provenance").notNull(),
    source: text("source").notNull(),
    externalId: text("external_id"),
    comment: text("comment"),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull(),
    deletedAt: timestamp("deleted_at", { withTimezone: true }),
    receivedAt: timestamp("received_at", { withTimezone: true })
      .notNull()
      .defaultNow()
  },
  (table) => ({
    userUpdatedAtIndex: index("metric_readings_user_updated_at_index").on(
      table.userId,
      table.updatedAt
    ),
    metricIdIndex: index("metric_readings_metric_id_index").on(table.metricId),
    externalActivityIdIndex: index(
      "metric_readings_external_activity_id_index"
    ).on(table.externalActivityId),
    sourceExternalIdIndex: index(
      "metric_readings_source_external_id_index"
    ).on(table.source, table.externalId)
  })
);

export const externalActivities = pgTable(
  "external_activities",
  {
    id: text("id").primaryKey(),
    userId: text("user_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    deviceId: text("device_id").notNull(),
    source: text("source").notNull(),
    externalId: text("external_id").notNull(),
    startedAt: timestamp("started_at", { withTimezone: true }).notNull(),
    endedAt: timestamp("ended_at", { withTimezone: true }).notNull(),
    timezone: text("timezone").notNull(),
    activityType: text("activity_type").notNull(),
    mappedExerciseId: text("mapped_exercise_id"),
    summaryJson: jsonb("summary_json")
      .$type<Record<string, unknown>>()
      .notNull(),
    summaryMetricsJson: jsonb("summary_metrics_json")
      .$type<unknown[]>()
      .notNull(),
    setsJson: jsonb("sets_json").$type<unknown[] | null>(),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull(),
    deletedAt: timestamp("deleted_at", { withTimezone: true }),
    receivedAt: timestamp("received_at", { withTimezone: true })
      .notNull()
      .defaultNow()
  },
  (table) => ({
    userSourceExternalIdUnique: uniqueIndex(
      "external_activities_user_source_external_id_unique"
    ).on(table.userId, table.source, table.externalId),
    userUpdatedAtIndex: index("external_activities_user_updated_at_index").on(
      table.userId,
      table.updatedAt
    )
  })
);

export const activityLinks = pgTable(
  "activity_links",
  {
    id: text("id").primaryKey(),
    userId: text("user_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    deviceId: text("device_id").notNull(),
    workoutId: text("workout_id").notNull(),
    externalActivityId: text("external_activity_id")
      .notNull()
      .references(() => externalActivities.id),
    linkKind: text("link_kind").notNull(),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull(),
    deletedAt: timestamp("deleted_at", { withTimezone: true }),
    receivedAt: timestamp("received_at", { withTimezone: true })
      .notNull()
      .defaultNow()
  },
  (table) => ({
    userWorkoutIdIndex: index("activity_links_user_workout_id_index").on(
      table.userId,
      table.workoutId
    ),
    userExternalActivityUnique: uniqueIndex(
      "activity_links_user_external_activity_unique"
    ).on(table.userId, table.externalActivityId)
  })
);

export const monitoringSeries = pgTable(
  "monitoring_series",
  {
    id: text("id").primaryKey(),
    userId: text("user_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    deviceId: text("device_id").notNull(),
    externalActivityId: text("external_activity_id").references(
      () => externalActivities.id
    ),
    source: text("source").notNull(),
    externalId: text("external_id").notNull(),
    seriesType: text("series_type").notNull(),
    anchorJson: jsonb("anchor_json").$type<Record<string, unknown>>().notNull(),
    baseTime: timestamp("base_time", { withTimezone: true }).notNull(),
    timezone: text("timezone").notNull(),
    sampleCount: integer("sample_count").notNull(),
    encoding: text("encoding").notNull(),
    compression: text("compression").notNull(),
    blob: bytea("blob").notNull(),
    uncompressedByteLength: integer("uncompressed_byte_length").notNull(),
    compressedByteLength: integer("compressed_byte_length").notNull(),
    sha256: text("sha256").notNull(),
    provenance: text("provenance").notNull(),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull(),
    deletedAt: timestamp("deleted_at", { withTimezone: true }),
    receivedAt: timestamp("received_at", { withTimezone: true })
      .notNull()
      .defaultNow()
  },
  (table) => ({
    userSourceExternalIdUnique: uniqueIndex(
      "monitoring_series_user_source_external_id_unique"
    ).on(table.userId, table.source, table.externalId),
    externalActivityIdIndex: index(
      "monitoring_series_external_activity_id_index"
    ).on(table.externalActivityId),
    userUpdatedAtIndex: index("monitoring_series_user_updated_at_index").on(
      table.userId,
      table.updatedAt
    )
  })
);

export const activityLog = pgTable(
  "activity_log",
  {
    id: text("id").primaryKey(),
    userId: text("user_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    actor: text("actor").notNull(),
    batchId: text("batch_id").notNull(),
    entityTable: text("entity_table").notNull(),
    entityId: text("entity_id").notNull(),
    beforeImage:
      jsonb("before_image").$type<Record<string, unknown> | null>(),
    afterImage:
      jsonb("after_image").$type<Record<string, unknown> | null>(),
    occurredAt: timestamp("occurred_at", { withTimezone: true }).notNull(),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .defaultNow()
  },
  (table) => ({
    batchIdIndex: index("activity_log_batch_id_index").on(table.batchId),
    occurredAtIndex: index("activity_log_occurred_at_index").on(
      table.occurredAt
    ),
    userOccurredAtIndex: index("activity_log_user_occurred_at_index").on(
      table.userId,
      table.occurredAt
    )
  })
);

export const devicePushTokens = pgTable(
  "device_push_tokens",
  {
    id: text("id").primaryKey(),
    userId: text("user_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    deviceId: text("device_id").notNull(),
    platform: text("platform").notNull(),
    token: text("token").notNull(),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
    updatedAt: timestamp("updated_at", { withTimezone: true })
      .notNull()
      .defaultNow()
  },
  (table) => ({
    userDevicePlatformUnique: uniqueIndex(
      "device_push_tokens_user_device_platform_unique"
    ).on(table.userId, table.deviceId, table.platform),
    userIdIndex: index("device_push_tokens_user_id_index").on(table.userId)
  })
);

export const loggedSetTombstoneGcMarkers = pgTable(
  "logged_set_tombstone_gc_markers",
  {
    id: text("id").primaryKey(),
    userId: text("user_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    loggedSetId: text("logged_set_id").notNull(),
    deviceId: text("device_id").notNull(),
    tombstoneUpdatedAt: timestamp("tombstone_updated_at", {
      withTimezone: true
    }).notNull(),
    deletedAt: timestamp("deleted_at", { withTimezone: true }).notNull(),
    gcAt: timestamp("gc_at", { withTimezone: true }).notNull(),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .defaultNow()
  },
  (table) => ({
    userLoggedSetUnique: uniqueIndex(
      "logged_set_tombstone_gc_markers_user_logged_set_unique"
    ).on(table.userId, table.loggedSetId),
    userIdIndex: index("logged_set_tombstone_gc_markers_user_id_index").on(
      table.userId
    )
  })
);

export const jobHeartbeats = pgTable(
  "job_heartbeats",
  {
    id: text("id").primaryKey(),
    jobName: text("job_name").notNull(),
    marker: text("marker").notNull(),
    kind: text("kind").notNull(),
    payload: jsonb("payload").$type<Record<string, unknown>>().notNull(),
    ranAt: timestamp("ran_at", { withTimezone: true }).notNull(),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .defaultNow()
  },
  (table) => ({
    jobMarkerUnique: uniqueIndex("job_heartbeats_job_marker_unique").on(
      table.jobName,
      table.marker
    ),
    jobRanAtIndex: index("job_heartbeats_job_ran_at_index").on(
      table.jobName,
      table.ranAt
    )
  })
);

export const rateLimitWindows = pgTable(
  "rate_limit_windows",
  {
    id: text("id").primaryKey(),
    key: text("key").notNull(),
    windowStartedAt: timestamp("window_started_at", {
      withTimezone: true
    }).notNull(),
    count: integer("count").notNull().default(0),
    expiresAt: timestamp("expires_at", { withTimezone: true }).notNull(),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
    updatedAt: timestamp("updated_at", { withTimezone: true })
      .notNull()
      .defaultNow()
  },
  (table) => ({
    keyWindowStartedAtUnique: uniqueIndex(
      "rate_limit_windows_key_window_started_at_unique"
    ).on(table.key, table.windowStartedAt),
    expiresAtIndex: index("rate_limit_windows_expires_at_index").on(
      table.expiresAt
    )
  })
);
