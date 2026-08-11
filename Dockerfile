# syntax=docker/dockerfile:1

FROM node:22-alpine AS base
WORKDIR /app
RUN corepack enable

FROM base AS deps
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml tsconfig.base.json ./
COPY apps/server/package.json apps/server/package.json
RUN corepack pnpm install --frozen-lockfile --filter @perennia/server...

FROM deps AS build
COPY apps/server apps/server
RUN corepack pnpm --filter @perennia/server build

FROM base AS prod-deps
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY apps/server/package.json apps/server/package.json
RUN corepack pnpm install --frozen-lockfile --prod --filter @perennia/server...

FROM node:22-alpine AS runtime
ENV NODE_ENV=production
ENV PORT=3000
WORKDIR /app
COPY --from=prod-deps /app/node_modules ./node_modules
COPY --from=prod-deps /app/apps/server/node_modules ./apps/server/node_modules
COPY --from=build /app/apps/server/package.json ./apps/server/package.json
COPY --from=build /app/apps/server/dist ./apps/server/dist
COPY --from=build /app/apps/server/drizzle ./apps/server/drizzle
WORKDIR /app/apps/server
EXPOSE 3000
CMD ["node", "dist/index.js"]
