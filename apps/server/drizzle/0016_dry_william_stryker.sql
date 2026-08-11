CREATE TABLE "integration_data_class_consents" (
	"id" text PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"device_id" text NOT NULL,
	"credential_id" text NOT NULL,
	"data_class" text NOT NULL,
	"enabled" boolean DEFAULT false NOT NULL,
	"updated_at" timestamp with time zone NOT NULL,
	"deleted_at" timestamp with time zone,
	"received_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "integration_data_class_consents" ADD CONSTRAINT "integration_data_class_consents_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "integration_data_class_consents_user_credential_data_class_unique" ON "integration_data_class_consents" USING btree ("user_id","credential_id","data_class");--> statement-breakpoint
CREATE INDEX "integration_data_class_consents_user_updated_at_index" ON "integration_data_class_consents" USING btree ("user_id","updated_at");