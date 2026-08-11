import { createApp } from "./app.js";
import { AUTH_BASE_PATH, createAuthOpenApiDocument } from "./auth/index.js";

const silentLogger = {
  info() {
    // OpenAPI generation should not emit request logs.
  }
};

export async function createOpenApiDocument() {
  const appDocument = createApp({ logger: silentLogger }).getOpenAPI31Document({
    openapi: "3.1.0",
    info: {
      title: "Perennia API",
      version: "0.0.0"
    }
  });
  const authDocument = filterAuthOpenApiDocument(await createAuthOpenApiDocument());

  return mergeOpenApiDocuments(
    appDocument as unknown as Record<string, unknown>,
    authDocument
  );
}

const emailPasswordAuthContractPaths = new Set([
  "/sign-up/email",
  "/sign-in/email",
  "/sign-in/social",
  "/callback/{id}",
  "/callback/:id",
  "/link-social",
  "/send-verification-email",
  "/verify-email",
  "/request-password-reset",
  "/reset-password",
  "/reset-password/{token}",
  "/get-session",
  "/sign-out"
]);

function filterAuthOpenApiDocument(document: Record<string, unknown>) {
  const paths = readObject(document.paths);

  return {
    ...document,
    paths: Object.fromEntries(
      Object.entries(paths).filter(([path]) =>
        emailPasswordAuthContractPaths.has(path)
      )
    )
  };
}

function mergeOpenApiDocuments(
  appDocument: Record<string, unknown>,
  authDocument: Record<string, unknown>
) {
  return {
    ...appDocument,
    paths: {
      ...readObject(appDocument.paths),
      ...prefixPaths(readObject(authDocument.paths), AUTH_BASE_PATH)
    },
    components: mergeComponents(appDocument.components, authDocument.components)
  };
}

function prefixPaths(paths: Record<string, unknown>, prefix: string) {
  return Object.fromEntries(
    Object.entries(paths).map(([path, value]) => [
      `${prefix}${path.startsWith("/") ? path : `/${path}`}`,
      value
    ])
  );
}

function mergeComponents(appComponents: unknown, authComponents: unknown) {
  const appComponentObject = readObject(appComponents);
  const authComponentObject = readObject(authComponents);
  const appSchemas = readObject(appComponentObject.schemas);
  const authSchemas = readObject(authComponentObject.schemas);
  const appSecuritySchemes = readObject(appComponentObject.securitySchemes);
  const authSecuritySchemes = readObject(authComponentObject.securitySchemes);

  return {
    ...appComponentObject,
    ...authComponentObject,
    schemas: {
      ...appSchemas,
      ...authSchemas
    },
    securitySchemes: {
      ...appSecuritySchemes,
      ...authSecuritySchemes
    }
  };
}

function readObject(value: unknown): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return {};
  }

  return value as Record<string, unknown>;
}
