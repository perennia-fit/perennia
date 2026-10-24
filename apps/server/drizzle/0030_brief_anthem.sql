CREATE TABLE "metric_aliases" (
	"id" text PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"metric_id" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "metric_aliases" ADD CONSTRAINT "metric_aliases_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "metric_aliases" ADD CONSTRAINT "metric_aliases_metric_id_metrics_id_fk" FOREIGN KEY ("metric_id") REFERENCES "public"."metrics"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "metric_aliases_metric_id_index" ON "metric_aliases" USING btree ("metric_id");