import {
  createDrizzleJobHeartbeatStore,
  type JobHeartbeatStore
} from "./heartbeat-store.js";
export {
  createDrizzleJobHeartbeatStore,
  type JobHeartbeatInput,
  type JobHeartbeatResult,
  type JobHeartbeatStore
} from "./heartbeat-store.js";
export {
  createPgBossJobQueue,
  createPgBossOptions
} from "./pg-boss.js";

export const JOB_SPINE_CRON_HEARTBEAT = "jobs.spine.cron-heartbeat";
export const JOB_SPINE_ENQUEUED_HEARTBEAT = "jobs.spine.enqueued-heartbeat";
export const JOB_SPINE_CRON_SCHEDULE_KEY = "worker-spine-cron-heartbeat";
export const JOB_SPINE_ENQUEUED_MARKER = "worker-spine-enqueued-heartbeat-v1";
export const JOB_SPINE_SCHEDULE_CRON = "*/5 * * * *";
export const JOB_SPINE_SINGLETON_SECONDS = 365 * 24 * 60 * 60;

export type JobData = Record<string, unknown>;

export type JobEnvelope<Data extends JobData = JobData> = {
  id: string;
  name: string;
  data: Data;
};

export type JobWorkHandler<Data extends JobData = JobData> = (
  job: JobEnvelope<Data>
) => Promise<void>;

export type JobSendOptions = {
  singletonKey?: string;
  singletonSeconds?: number;
  retryLimit?: number;
};

export type JobQueue = {
  start(): Promise<void>;
  stop(): Promise<void>;
  ensureQueue(input: { name: string }): Promise<void>;
  schedule(input: {
    name: string;
    cron: string;
    key: string;
    data: JobData;
  }): Promise<void>;
  send(input: {
    name: string;
    data: JobData;
    options?: JobSendOptions;
  }): Promise<string | null>;
  work<Data extends JobData>(
    name: string,
    handler: JobWorkHandler<Data>
  ): Promise<void>;
};

export type JobLogger = {
  info(payload: Record<string, unknown>, message: string): void;
  warn?(payload: Record<string, unknown>, message: string): void;
  error?(payload: Record<string, unknown>, message: string): void;
};

export type JobSpineOptions = {
  jobs: JobQueue;
  heartbeatStore: JobHeartbeatStore;
  logger: JobLogger;
  clock?: () => Date;
};

export type JobSpine = {
  start(): Promise<void>;
  stop(): Promise<void>;
};

type SpineJobData = JobData & {
  marker?: string;
  source?: string;
};

export function createJobSpine({
  jobs,
  heartbeatStore,
  logger,
  clock = () => new Date()
}: JobSpineOptions): JobSpine {
  return {
    async start() {
      await jobs.start();
      try {
        await jobs.ensureQueue({ name: JOB_SPINE_CRON_HEARTBEAT });
        await jobs.ensureQueue({ name: JOB_SPINE_ENQUEUED_HEARTBEAT });
        await jobs.work<SpineJobData>(
          JOB_SPINE_CRON_HEARTBEAT,
          async (job) => {
            const payload = createPayload(job);
            await recordAndLogHeartbeat({
              heartbeatStore,
              logger,
              jobName: JOB_SPINE_CRON_HEARTBEAT,
              marker: job.id,
              kind: "scheduled",
              payload,
              ranAt: clock()
            });
          }
        );
        await jobs.work<SpineJobData>(
          JOB_SPINE_ENQUEUED_HEARTBEAT,
          async (job) => {
            const marker =
              typeof job.data.marker === "string" ? job.data.marker : job.id;
            await recordAndLogHeartbeat({
              heartbeatStore,
              logger,
              jobName: JOB_SPINE_ENQUEUED_HEARTBEAT,
              marker,
              kind: "enqueued",
              payload: { jobId: job.id },
              ranAt: clock()
            });
          }
        );
        await jobs.schedule({
          name: JOB_SPINE_CRON_HEARTBEAT,
          cron: JOB_SPINE_SCHEDULE_CRON,
          key: JOB_SPINE_CRON_SCHEDULE_KEY,
          data: { source: "worker-spine" }
        });
        await jobs.send({
          name: JOB_SPINE_ENQUEUED_HEARTBEAT,
          data: {
            marker: JOB_SPINE_ENQUEUED_MARKER,
            source: "worker-spine"
          },
          options: {
            singletonKey: JOB_SPINE_ENQUEUED_MARKER,
            singletonSeconds: JOB_SPINE_SINGLETON_SECONDS,
            retryLimit: 3
          }
        });
        logger.info(
          {
            scheduledJob: JOB_SPINE_CRON_HEARTBEAT,
            enqueuedJob: JOB_SPINE_ENQUEUED_HEARTBEAT
          },
          "job spine started"
        );
      } catch (error) {
        await jobs.stop();
        throw error;
      }
    },
    async stop() {
      await jobs.stop();
    }
  };
}

function createPayload(job: JobEnvelope<SpineJobData>) {
  const payload: Record<string, unknown> = { jobId: job.id };

  if (typeof job.data.source === "string") {
    payload.source = job.data.source;
  }

  return payload;
}

async function recordAndLogHeartbeat({
  heartbeatStore,
  logger,
  jobName,
  marker,
  kind,
  payload,
  ranAt
}: {
  heartbeatStore: JobHeartbeatStore;
  logger: JobLogger;
  jobName: string;
  marker: string;
  kind: string;
  payload: Record<string, unknown>;
  ranAt: Date;
}) {
  const result = await heartbeatStore.recordHeartbeat({
    jobName,
    marker,
    kind,
    payload,
    ranAt
  });

  logger.info(
    {
      jobName,
      marker,
      kind,
      heartbeatId: result.id,
      inserted: result.inserted
    },
    result.inserted
      ? "job heartbeat recorded"
      : "job heartbeat already recorded"
  );
}
