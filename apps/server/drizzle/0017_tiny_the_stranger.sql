CREATE TABLE "garmin_oauth_connections" (
	"id" text PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"source" text NOT NULL,
	"credential_name" text NOT NULL,
	"provider_user_id" text,
	"scope" text,
	"encrypted_refresh_token" text,
	"access_token_expires_at" timestamp with time zone,
	"connected_at" timestamp with time zone NOT NULL,
	"revoked_at" timestamp with time zone,
	"updated_at" timestamp with time zone NOT NULL,
	"received_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "garmin_oauth_connections" ADD CONSTRAINT "garmin_oauth_connections_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "garmin_oauth_connections_user_source_unique" ON "garmin_oauth_connections" USING btree ("user_id","source");--> statement-breakpoint
CREATE INDEX "garmin_oauth_connections_user_updated_at_index" ON "garmin_oauth_connections" USING btree ("user_id","updated_at");