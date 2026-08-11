CREATE TABLE "device_push_tokens" (
	"id" text PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"device_id" text NOT NULL,
	"platform" text NOT NULL,
	"token" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "device_push_tokens" ADD CONSTRAINT "device_push_tokens_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "device_push_tokens_user_device_platform_unique" ON "device_push_tokens" USING btree ("user_id","device_id","platform");--> statement-breakpoint
CREATE INDEX "device_push_tokens_user_id_index" ON "device_push_tokens" USING btree ("user_id");