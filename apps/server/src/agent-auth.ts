import {
  DEFAULT_AGENT_API_KEY_RATE_LIMIT_MAX,
  DEFAULT_AGENT_API_KEY_RATE_LIMIT_WINDOW_MS,
  type AuthenticatedAgent,
  type AgentApiKeyStore
} from "./agent-api-keys.js";
import type { RateLimitBackend, RateLimitDecision } from "./rate-limit.js";

export type AgentAuthLogger = {
  error?(payload: Record<string, unknown>, message: string): void;
};

export type AgentOperationAuthResult =
  | {
      status: "authenticated";
      agent: AuthenticatedAgent;
      rateLimitDecision?: RateLimitDecision;
    }
  | {
      status: "rate_limited";
      decision: RateLimitDecision;
    }
  | {
      status: "unauthorized";
    };

export async function authenticateAgentOperation({
  secret,
  agentApiKeyStore,
  rateLimitBackend,
  logger
}: {
  secret: string;
  agentApiKeyStore: AgentApiKeyStore;
  rateLimitBackend: RateLimitBackend | undefined;
  logger: AgentAuthLogger;
}): Promise<AgentOperationAuthResult> {
  const agent = await agentApiKeyStore.authenticateAgentApiKey(secret);
  if (agent === null) {
    return { status: "unauthorized" };
  }

  if (rateLimitBackend === undefined || agent.rateLimitEnabled === false) {
    return { status: "authenticated", agent };
  }

  try {
    const decision = await rateLimitBackend.recordHit({
      key: `agent-api-key:${agent.keyId}`,
      limit: positiveIntegerOrDefault(
        agent.rateLimitMax,
        DEFAULT_AGENT_API_KEY_RATE_LIMIT_MAX
      ),
      windowMs: positiveIntegerOrDefault(
        agent.rateLimitTimeWindow,
        DEFAULT_AGENT_API_KEY_RATE_LIMIT_WINDOW_MS
      )
    });

    if (!decision.allowed) {
      return { status: "rate_limited", decision };
    }

    return { status: "authenticated", agent, rateLimitDecision: decision };
  } catch (error) {
    logger.error?.({ error, keyId: agent.keyId }, "agent rate-limit failed open");
    return { status: "authenticated", agent };
  }
}

function positiveIntegerOrDefault(
  value: number | null | undefined,
  fallback: number
): number {
  return value !== null &&
    value !== undefined &&
    Number.isInteger(value) &&
    value > 0
    ? value
    : fallback;
}
