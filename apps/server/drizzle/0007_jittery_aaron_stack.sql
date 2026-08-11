CREATE TABLE "rate_limit_windows" (
	"id" text PRIMARY KEY NOT NULL,
	"key" text NOT NULL,
	"window_started_at" timestamp with time zone NOT NULL,
	"count" integer DEFAULT 0 NOT NULL,
	"expires_at" timestamp with time zone NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX "rate_limit_windows_key_window_started_at_unique" ON "rate_limit_windows" USING btree ("key","window_started_at");--> statement-breakpoint
CREATE INDEX "rate_limit_windows_expires_at_index" ON "rate_limit_windows" USING btree ("expires_at");
