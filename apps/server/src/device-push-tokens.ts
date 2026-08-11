import { randomUUID } from "node:crypto";

import { createRoute, z } from "@hono/zod-openapi";
import { and, eq, ne } from "drizzle-orm";

import type { ServerDatabase } from "./db/client.js";
import * as schema from "./db/schema.js";
import {
  SyncUnauthorizedResponseSchema,
  SyncUnavailableResponseSchema
} from "./sync.js";

export const DEVICE_PUSH_PLATFORM_ANDROID = "android";
export const DEVICE_PUSH_PLATFORM_IOS = "ios";
export const DEVICE_PUSH_PLATFORMS = [
  DEVICE_PUSH_PLATFORM_ANDROID,
  DEVICE_PUSH_PLATFORM_IOS
] as const;

export const DevicePushPlatformSchema = z
  .enum(DEVICE_PUSH_PLATFORMS)
  .openapi("DevicePushPlatform");

export const DevicePushTokenRegistrationRequestSchema = z
  .object({
    deviceId: z.string().min(1).openapi({
      description: "Stable id for the signed-in device replica."
    }),
    platform: DevicePushPlatformSchema.openapi({
      description: "Push platform backing the token."
    }),
    token: z.string().min(1).openapi({
      description: "FCM or APNs token issued to this app install."
    })
  })
  .openapi("DevicePushTokenRegistrationRequest");

export const DevicePushTokenRegistrationResponseSchema = z
  .object({
    registered: z.literal(true).openapi({
      description: "True once the token has been recorded for the account."
    })
  })
  .openapi("DevicePushTokenRegistrationResponse");

export const devicePushTokenRegistrationRoute = createRoute({
  method: "post",
  path: "/sync/device-push-token",
  operationId: "registerDevicePushToken",
  tags: ["Sync"],
  summary: "Register this device's silent-push token for sync nudges.",
  security: [{ bearerAuth: [] }],
  request: {
    body: {
      required: true,
      content: {
        "application/json": {
          schema: DevicePushTokenRegistrationRequestSchema
        }
      }
    }
  },
  responses: {
    200: {
      description: "The device push token was registered.",
      content: {
        "application/json": {
          schema: DevicePushTokenRegistrationResponseSchema
        }
      }
    },
    401: {
      description: "The request is missing a valid session bearer token.",
      content: {
        "application/json": {
          schema: SyncUnauthorizedResponseSchema
        }
      }
    },
    503: {
      description: "Push-token storage is not configured for this app instance.",
      content: {
        "application/json": {
          schema: SyncUnavailableResponseSchema
        }
      }
    }
  }
});

export type DevicePushPlatform = (typeof DEVICE_PUSH_PLATFORMS)[number];

export type RegisteredDevicePushToken = {
  id: string;
  userId: string;
  deviceId: string;
  platform: DevicePushPlatform;
  token: string;
};

export type DevicePushTokenRegistrationInput = {
  userId: string;
  deviceId: string;
  platform: DevicePushPlatform;
  token: string;
};

export type ListDevicePushTokensInput = {
  userId: string;
  excludeDeviceId?: string;
};

export type DevicePushTokenStore = {
  registerDevicePushToken(
    input: DevicePushTokenRegistrationInput
  ): Promise<void>;
  listDevicePushTokensForUser(
    input: ListDevicePushTokensInput
  ): Promise<RegisteredDevicePushToken[]>;
  removeDevicePushToken?(input: {
    userId: string;
    tokenId: string;
  }): Promise<void>;
};

export function createDrizzleDevicePushTokenStore(
  db: ServerDatabase
): DevicePushTokenStore {
  return {
    async registerDevicePushToken(input) {
      const now = new Date();

      await db
        .insert(schema.devicePushTokens)
        .values({
          id: randomUUID(),
          userId: input.userId,
          deviceId: input.deviceId,
          platform: input.platform,
          token: input.token,
          updatedAt: now
        })
        .onConflictDoUpdate({
          target: [
            schema.devicePushTokens.userId,
            schema.devicePushTokens.deviceId,
            schema.devicePushTokens.platform
          ],
          set: {
            token: input.token,
            updatedAt: now
          }
        });
    },
    async listDevicePushTokensForUser(input) {
      const rows = await db
        .select({
          id: schema.devicePushTokens.id,
          userId: schema.devicePushTokens.userId,
          deviceId: schema.devicePushTokens.deviceId,
          platform: schema.devicePushTokens.platform,
          token: schema.devicePushTokens.token
        })
        .from(schema.devicePushTokens)
        .where(
          input.excludeDeviceId === undefined
            ? eq(schema.devicePushTokens.userId, input.userId)
            : and(
                eq(schema.devicePushTokens.userId, input.userId),
                ne(schema.devicePushTokens.deviceId, input.excludeDeviceId)
              )
        );

      return rows.map((row) => ({
        ...row,
        platform: DevicePushPlatformSchema.parse(row.platform)
      }));
    },
    async removeDevicePushToken(input) {
      await db
        .delete(schema.devicePushTokens)
        .where(
          and(
            eq(schema.devicePushTokens.id, input.tokenId),
            eq(schema.devicePushTokens.userId, input.userId)
          )
        );
    }
  };
}
