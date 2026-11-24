ALTER TABLE "metrics" ADD COLUMN "lab_test_key" text;--> statement-breakpoint
CREATE INDEX "metrics_user_lab_test_key_index" ON "metrics" USING btree ("user_id","lab_test_key");