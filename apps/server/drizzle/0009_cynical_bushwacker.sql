CREATE TABLE "metric_readings" (
	"id" text PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"device_id" text NOT NULL,
	"metric_id" text NOT NULL,
	"value_json" jsonb NOT NULL,
	"scalar_value" double precision,
	"scalar_entered" text,
	"at_time" timestamp with time zone,
	"window_started_at" timestamp with time zone,
	"window_ended_at" timestamp with time zone,
	"provenance" text NOT NULL,
	"source" text NOT NULL,
	"external_id" text,
	"comment" text,
	"updated_at" timestamp with time zone NOT NULL,
	"deleted_at" timestamp with time zone,
	"received_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "metrics" (
	"id" text PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"device_id" text NOT NULL,
	"name" text NOT NULL,
	"unit" text NOT NULL,
	"value_shape" text NOT NULL,
	"metric_group" text NOT NULL,
	"goal_type" text,
	"goal_target_value" double precision,
	"enabled" boolean DEFAULT true NOT NULL,
	"pinned" boolean DEFAULT false NOT NULL,
	"sort_order" integer NOT NULL,
	"updated_at" timestamp with time zone NOT NULL,
	"deleted_at" timestamp with time zone,
	"received_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "metric_readings" ADD CONSTRAINT "metric_readings_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "metric_readings" ADD CONSTRAINT "metric_readings_metric_id_metrics_id_fk" FOREIGN KEY ("metric_id") REFERENCES "public"."metrics"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "metrics" ADD CONSTRAINT "metrics_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "metric_readings_user_updated_at_index" ON "metric_readings" USING btree ("user_id","updated_at");--> statement-breakpoint
CREATE INDEX "metric_readings_metric_id_index" ON "metric_readings" USING btree ("metric_id");--> statement-breakpoint
CREATE INDEX "metric_readings_source_external_id_index" ON "metric_readings" USING btree ("source","external_id");--> statement-breakpoint
CREATE INDEX "metrics_user_updated_at_index" ON "metrics" USING btree ("user_id","updated_at");--> statement-breakpoint
CREATE INDEX "metrics_user_sort_order_index" ON "metrics" USING btree ("user_id","sort_order");
--> statement-breakpoint
-- Defensive legacy-data bridge: the checked-in server migration history never
-- created measurements, but this keeps out-of-band Measurement deployments
-- idempotently recoverable without touching their source rows.
DO $$
BEGIN
	IF to_regclass('public.measurements') IS NOT NULL
		AND to_regclass('public.measurement_entries') IS NOT NULL
		AND EXISTS (
			SELECT 1
			FROM information_schema.columns
			WHERE table_schema = 'public'
				AND table_name = 'measurements'
				AND column_name = 'user_id'
		)
		AND EXISTS (
			SELECT 1
			FROM information_schema.columns
			WHERE table_schema = 'public'
				AND table_name = 'measurements'
				AND column_name = 'device_id'
		)
		AND EXISTS (
			SELECT 1
			FROM information_schema.columns
			WHERE table_schema = 'public'
				AND table_name = 'measurements'
				AND column_name = 'target_value'
		)
		AND EXISTS (
			SELECT 1
			FROM information_schema.columns
			WHERE table_schema = 'public'
				AND table_name = 'measurement_entries'
				AND column_name = 'device_id'
		)
		AND EXISTS (
			SELECT 1
			FROM information_schema.columns
			WHERE table_schema = 'public'
				AND table_name = 'measurement_entries'
				AND column_name = 'comment'
		)
	THEN
		INSERT INTO "metrics" (
			"id",
			"user_id",
			"device_id",
			"name",
			"unit",
			"value_shape",
			"metric_group",
			"goal_type",
			"goal_target_value",
			"enabled",
			"pinned",
			"sort_order",
			"updated_at",
			"deleted_at"
		)
		SELECT
			"id",
			"user_id",
			"device_id",
			"name",
			"unit",
			'scalar',
			'bodyComposition',
			"goal_type",
			"target_value",
			"enabled",
			"enabled",
			"sort_order",
			"updated_at",
			"deleted_at"
		FROM "measurements"
		ON CONFLICT ("id") DO NOTHING;

		INSERT INTO "metric_readings" (
			"id",
			"user_id",
			"device_id",
			"metric_id",
			"value_json",
			"scalar_value",
			"scalar_entered",
			"at_time",
			"window_started_at",
			"window_ended_at",
			"provenance",
			"source",
			"external_id",
			"comment",
			"updated_at",
			"deleted_at"
		)
		SELECT
			entry."id",
			measurement."user_id",
			entry."device_id",
			entry."measurement_id",
			jsonb_build_object(
				'shape',
				'scalar',
				'value',
				entry."value",
				'entered',
				entry."value_entered"
			),
			entry."value",
			entry."value_entered",
			entry."measured_at",
			NULL,
			NULL,
			'manual',
			'manual',
			entry."id",
			entry."comment",
			entry."updated_at",
			entry."deleted_at"
		FROM "measurement_entries" AS entry
		INNER JOIN "measurements" AS measurement
			ON measurement."id" = entry."measurement_id"
		ON CONFLICT ("id") DO NOTHING;
	END IF;
END $$;
