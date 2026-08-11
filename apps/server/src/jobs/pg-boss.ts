import {
  PgBoss,
  type ConstructorOptions,
  type Job as PgBossJob
} from "pg-boss";

import type { JobData, JobQueue, JobWorkHandler } from "./index.js";

export type PgBossLogger = {
  info(payload: Record<string, unknown>, message: string): void;
  warn?(payload: Record<string, unknown>, message: string): void;
  error?(payload: Record<string, unknown>, message: string): void;
};

export function createPgBossOptions(databaseUrl: string): ConstructorOptions {
  return {
    connectionString: databaseUrl,
    application_name: "perennia-worker",
    schema: "pgboss",
    migrate: true,
    schedule: true
  };
}

export function createPgBossJobQueue({
  databaseUrl,
  logger
}: {
  databaseUrl: string;
  logger: PgBossLogger;
}): JobQueue {
  const boss = new PgBoss(createPgBossOptions(databaseUrl));

  boss.on("error", (error) => {
    logger.error?.({ error }, "pg-boss error");
  });
  boss.on("warning", (warning) => {
    logger.warn?.({ warning }, "pg-boss warning");
  });

  return {
    async start() {
      await boss.start();
      logger.info({ schema: "pgboss" }, "pg-boss started");
    },
    async stop() {
      await boss.stop();
      logger.info({ schema: "pgboss" }, "pg-boss stopped");
    },
    async ensureQueue({ name }) {
      await boss.createQueue(name);
    },
    async schedule({ name, cron, key, data }) {
      await boss.schedule(name, cron, data, { key });
    },
    async send({ name, data, options }) {
      return boss.send(name, data, options);
    },
    async work<Data extends JobData>(
      name: string,
      handler: JobWorkHandler<Data>
    ) {
      await boss.work<Data>(name, async (jobs) => {
        for (const job of jobs) {
          await handler(toJobEnvelope(job));
        }
      });
    }
  };
}

function toJobEnvelope<Data extends JobData>(job: PgBossJob<Data>) {
  return {
    id: job.id,
    name: job.name,
    data: job.data
  };
}
