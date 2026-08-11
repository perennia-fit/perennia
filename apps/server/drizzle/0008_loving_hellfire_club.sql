CREATE TABLE "apikey" (
	"id" text PRIMARY KEY NOT NULL,
	"configId" text DEFAULT 'default' NOT NULL,
	"name" text,
	"start" text,
	"prefix" text,
	"key" text NOT NULL,
	"referenceId" text NOT NULL,
	"refillInterval" integer,
	"refillAmount" integer,
	"lastRefillAt" timestamp with time zone,
	"enabled" boolean DEFAULT true NOT NULL,
	"rateLimitEnabled" boolean DEFAULT true NOT NULL,
	"rateLimitTimeWindow" integer DEFAULT 86400000,
	"rateLimitMax" integer DEFAULT 10,
	"requestCount" integer DEFAULT 0 NOT NULL,
	"remaining" integer,
	"lastRequest" timestamp with time zone,
	"expiresAt" timestamp with time zone,
	"createdAt" timestamp with time zone DEFAULT now() NOT NULL,
	"updatedAt" timestamp with time zone DEFAULT now() NOT NULL,
	"permissions" text,
	"metadata" text
);
--> statement-breakpoint
ALTER TABLE "apikey" ADD CONSTRAINT "apikey_referenceId_user_id_fk" FOREIGN KEY ("referenceId") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "apikey_config_id_index" ON "apikey" USING btree ("configId");--> statement-breakpoint
CREATE INDEX "apikey_key_index" ON "apikey" USING btree ("key");--> statement-breakpoint
CREATE INDEX "apikey_reference_id_index" ON "apikey" USING btree ("referenceId");
