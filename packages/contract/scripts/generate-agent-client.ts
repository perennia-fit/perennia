import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

type JsonObject = Record<string, unknown>;

type OpenApiSchema = JsonObject & {
  $ref?: string;
  anyOf?: OpenApiSchema[];
  allOf?: OpenApiSchema[];
  const?: unknown;
  enum?: unknown[];
  items?: OpenApiSchema;
  nullable?: boolean;
  properties?: Record<string, OpenApiSchema>;
  required?: string[];
  type?: string | string[];
};

type OpenApiParameter = {
  in?: string;
  name: string;
  required?: boolean;
  schema?: OpenApiSchema;
};

type OpenApiOperation = {
  operationId?: string;
  parameters?: OpenApiParameter[];
  requestBody?: {
    content?: Record<string, { schema?: OpenApiSchema }>;
  };
  responses?: Record<
    string,
    {
      content?: Record<string, { schema?: OpenApiSchema }>;
    }
  >;
};

type OpenApiDocument = {
  paths?: Record<string, Record<string, OpenApiOperation>>;
  components?: {
    schemas?: Record<string, OpenApiSchema>;
  };
};

type AgentOperation = {
  bodyType: string | null;
  expectedStatus: number;
  method: string;
  operationId: string;
  path: string;
  pathParameters: OpenApiParameter[];
  queryParameters: OpenApiParameter[];
  responseType: string;
};

const scriptDir = dirname(fileURLToPath(import.meta.url));
const contractDir = resolve(scriptDir, "..");
const inputPath = resolve(contractDir, "openapi.json");
const outputPath = resolve(contractDir, "src/agent-client.ts");

const document = JSON.parse(await readFile(inputPath, "utf8")) as OpenApiDocument;
const operations = collectAgentOperations(document);

if (operations.length === 0) {
  throw new Error("OpenAPI document does not contain agent operations.");
}

const schemaNames = collectAgentSchemaNames(document, operations);
const source = `// GENERATED CODE - DO NOT MODIFY BY HAND.
// Generated from packages/contract/openapi.json by packages/contract/scripts/generate-agent-client.ts.

export type JsonPrimitive = string | number | boolean | null;
export type JsonValue = JsonPrimitive | JsonValue[] | { [key: string]: JsonValue };

export type AgentClientFetch = (
  url: string,
  init: {
    method: string;
    headers: Record<string, string>;
    body?: string;
    signal?: unknown;
  }
) => Promise<{
  ok: boolean;
  status: number;
  text(): Promise<string>;
}>;

export type AgentClientOptions = {
  baseUrl: string | URL;
  bearerToken: string;
  fetch?: AgentClientFetch;
};

export type AgentClientRequestOptions = {
  signal?: unknown;
};

${[...schemaNames]
  .sort()
  .map((name) => generateSchemaType(name, requiredSchema(document, name)))
  .join("\n\n")}

${operations
  .map((operation) => generateInputType(operation))
  .filter((typeSource) => typeSource.length > 0)
  .join("\n\n")}

export const AGENT_CLIENT_OPERATION_IDS = ${JSON.stringify(
  operations.map((operation) => operation.operationId).sort(),
  null,
  2
)} as const;

export class AgentApiError extends Error {
  constructor({
    body,
    status
  }: {
    body: string;
    status: number;
  }) {
    super(\`Agent API request failed with status \${status}.\`);
    this.name = "AgentApiError";
    this.body = body;
    this.status = status;
  }

  readonly body: string;
  readonly status: number;
}

export class PerenniaAgentClient {
  static readonly openApiSource = "packages/contract/openapi.json";

  constructor(options: AgentClientOptions) {
    this.baseUrl = new URL(options.baseUrl);
    this.bearerToken = options.bearerToken;
    const fetchImplementation =
      options.fetch ??
      (globalThis.fetch as unknown as AgentClientFetch | undefined);

    if (fetchImplementation === undefined) {
      throw new Error("PerenniaAgentClient requires a fetch implementation.");
    }
    this.fetchImplementation = fetchImplementation;
  }

  private readonly baseUrl: URL;
  private readonly bearerToken: string;
  private readonly fetchImplementation: AgentClientFetch;

${operations.map(generateClientMethod).join("\n\n")}

  private async request<TResponse>({
    body,
    expectedStatus,
    method,
    path,
    query,
    signal
  }: {
    body?: unknown;
    expectedStatus: number;
    method: string;
    path: string;
    query?: Record<string, unknown>;
    signal?: unknown;
  }): Promise<TResponse> {
    const url = new URL(path, this.baseUrl);
    for (const [key, value] of Object.entries(query ?? {})) {
      if (value === undefined || value === null) {
        continue;
      }
      url.searchParams.set(key, String(value));
    }

    const headers: Record<string, string> = {
      accept: "application/json",
      authorization: \`Bearer \${this.bearerToken}\`
    };
    let encodedBody: string | undefined;
    if (body !== undefined) {
      headers["content-type"] = "application/json";
      encodedBody = JSON.stringify(body);
    }

    const response = await this.fetchImplementation(url.toString(), {
      method,
      headers,
      body: encodedBody,
      signal
    });
    const responseBody = await response.text();

    if (response.status !== expectedStatus) {
      throw new AgentApiError({ body: responseBody, status: response.status });
    }

    return (responseBody.length === 0
      ? undefined
      : JSON.parse(responseBody)) as TResponse;
  }
}
`;

await mkdir(dirname(outputPath), { recursive: true });
await writeFile(outputPath, source, "utf8");

function collectAgentOperations(document: OpenApiDocument): AgentOperation[] {
  const operations: AgentOperation[] = [];

  for (const [path, methods] of Object.entries(document.paths ?? {}).sort()) {
    if (!path.startsWith("/agent/")) {
      continue;
    }

    for (const [method, operation] of Object.entries(methods).sort()) {
      if (operation.operationId === undefined) {
        throw new Error(`${method.toUpperCase()} ${path} is missing operationId.`);
      }

      const successResponse = resolveSuccessResponse(operation);
      operations.push({
        bodyType: resolveRequestBodyType(operation),
        expectedStatus: successResponse.status,
        method: method.toUpperCase(),
        operationId: operation.operationId,
        path,
        pathParameters: (operation.parameters ?? []).filter(
          (parameter) => parameter.in === "path"
        ),
        queryParameters: (operation.parameters ?? []).filter(
          (parameter) => parameter.in === "query"
        ),
        responseType: successResponse.typeName
      });
    }
  }

  return operations.sort((left, right) =>
    left.operationId.localeCompare(right.operationId)
  );
}

function resolveRequestBodyType(operation: OpenApiOperation) {
  const schema = operation.requestBody?.content?.["application/json"]?.schema;
  return schema === undefined ? null : refName(schema);
}

function resolveSuccessResponse(operation: OpenApiOperation) {
  for (const [statusText, response] of Object.entries(operation.responses ?? {}).sort()) {
    const status = Number.parseInt(statusText, 10);
    const schema = response.content?.["application/json"]?.schema;
    if (status >= 200 && status < 300 && schema !== undefined) {
      return { status, typeName: refName(schema) };
    }
  }

  throw new Error(`${operation.operationId ?? "operation"} has no JSON 2xx response.`);
}

function refName(schema: OpenApiSchema) {
  if (schema.$ref === undefined) {
    throw new Error("Expected schema reference.");
  }

  return schema.$ref.split("/").at(-1) ?? schema.$ref;
}

function collectAgentSchemaNames(
  document: OpenApiDocument,
  operations: AgentOperation[]
) {
  const names = new Set<string>();

  for (const operation of operations) {
    names.add(operation.responseType);
    if (operation.bodyType !== null) {
      names.add(operation.bodyType);
    }
  }

  for (const name of [...names]) {
    collectSchemaReferences(document, requiredSchema(document, name), names);
  }

  return names;
}

function collectSchemaReferences(
  document: OpenApiDocument,
  schema: OpenApiSchema,
  names: Set<string>
) {
  if (schema.$ref !== undefined) {
    const name = refName(schema);
    if (!names.has(name)) {
      names.add(name);
      collectSchemaReferences(document, requiredSchema(document, name), names);
    }
    return;
  }

  for (const item of schema.anyOf ?? []) {
    collectSchemaReferences(document, item, names);
  }
  for (const item of schema.allOf ?? []) {
    collectSchemaReferences(document, item, names);
  }
  if (schema.items !== undefined) {
    collectSchemaReferences(document, schema.items, names);
  }
  for (const property of Object.values(schema.properties ?? {})) {
    collectSchemaReferences(document, property, names);
  }
}

function requiredSchema(document: OpenApiDocument, name: string) {
  const schema = document.components?.schemas?.[name];
  if (schema === undefined) {
    throw new Error(`OpenAPI component schema ${name} not found.`);
  }

  return schema;
}

function generateSchemaType(name: string, schema: OpenApiSchema) {
  return `export type ${name} = ${schemaToType(schema)};`;
}

function schemaToType(schema: OpenApiSchema): string {
  if (schema.$ref !== undefined) {
    return refName(schema);
  }
  if (schema.const !== undefined) {
    return literalType(schema.const);
  }
  if (schema.enum !== undefined) {
    return schema.enum.map(literalType).join(" | ");
  }
  if (schema.anyOf !== undefined) {
    return schema.anyOf.map(schemaToType).join(" | ");
  }
  if (schema.allOf !== undefined) {
    return schema.allOf.map(schemaToType).join(" & ");
  }

  const typeNames = Array.isArray(schema.type) ? schema.type : [schema.type];
  const includesNull = typeNames.includes("null") || schema.nullable === true;
  const nonNullTypes = typeNames.filter(
    (typeName): typeName is string =>
      typeName !== undefined && typeName !== "null"
  );
  const generated =
    nonNullTypes.length === 0
      ? "unknown"
      : nonNullTypes.map((typeName) => schemaTypeToType(schema, typeName)).join(" | ");

  return includesNull ? `${generated} | null` : generated;
}

function schemaTypeToType(schema: OpenApiSchema, typeName: string): string {
  switch (typeName) {
    case "array":
      return `Array<${schemaToType(schema.items ?? {})}>`;
    case "boolean":
      return "boolean";
    case "integer":
    case "number":
      return "number";
    case "object":
      return objectSchemaToType(schema);
    case "string":
      return "string";
    default:
      return "unknown";
  }
}

function objectSchemaToType(schema: OpenApiSchema): string {
  const properties = Object.entries(schema.properties ?? {});
  if (properties.length === 0) {
    return "Record<string, unknown>";
  }

  const required = new Set(schema.required ?? []);
  return `{
${properties
  .map(([name, property]) => {
    const optional = required.has(name) ? "" : "?";
    return `  ${JSON.stringify(name)}${optional}: ${schemaToType(property)};`;
  })
  .join("\n")}
}`;
}

function generateInputType(operation: AgentOperation) {
  if (
    operation.bodyType !== null &&
    operation.pathParameters.length === 0 &&
    operation.queryParameters.length === 0
  ) {
    return "";
  }

  const properties = [
    ...operation.pathParameters.map((parameter) => ({
      name: parameter.name,
      optional: false,
      type: schemaToType(parameter.schema ?? {})
    })),
    ...operation.queryParameters.map((parameter) => ({
      name: parameter.name,
      optional: parameter.required !== true,
      type: schemaToType(parameter.schema ?? {})
    })),
    ...(operation.bodyType === null
      ? []
      : [{ name: "body", optional: false, type: operation.bodyType }])
  ];

  if (properties.length === 0) {
    return "";
  }

  return `export type ${inputTypeName(operation)} = {
${properties
  .map(
    (property) =>
      `  ${JSON.stringify(property.name)}${property.optional ? "?" : ""}: ${
        property.type
      };`
  )
  .join("\n")}
};`;
}

function generateClientMethod(operation: AgentOperation) {
  const methodName = operation.operationId;
  const parameters = methodParameters(operation);
  const pathExpression = pathExpressionFor(operation);
  const queryExpression = queryExpressionFor(operation);
  const bodyExpression = bodyExpressionFor(operation);

  return `  async ${methodName}(${parameters}): Promise<${operation.responseType}> {
    return this.request<${operation.responseType}>({
      method: "${operation.method}",
      path: ${pathExpression},
      expectedStatus: ${operation.expectedStatus}${queryExpression}${bodyExpression},
      signal: options.signal
    });
  }`;
}

function methodParameters(operation: AgentOperation) {
  if (
    operation.bodyType !== null &&
    operation.pathParameters.length === 0 &&
    operation.queryParameters.length === 0
  ) {
    return `body: ${operation.bodyType}, options: AgentClientRequestOptions = {}`;
  }

  if (
    operation.bodyType === null &&
    operation.pathParameters.length === 0 &&
    operation.queryParameters.length === 0
  ) {
    return "options: AgentClientRequestOptions = {}";
  }

  const inputDefault =
    operation.pathParameters.length === 0 &&
    operation.bodyType === null &&
    operation.queryParameters.every((parameter) => parameter.required !== true)
      ? " = {}"
      : "";
  return `input: ${inputTypeName(operation)}${inputDefault}, options: AgentClientRequestOptions = {}`;
}

function inputTypeName(operation: AgentOperation) {
  return `${capitalize(operation.operationId)}Input`;
}

function pathExpressionFor(operation: AgentOperation) {
  if (operation.pathParameters.length === 0) {
    return JSON.stringify(operation.path);
  }

  let expression = operation.path;
  for (const parameter of operation.pathParameters) {
    expression = expression.replace(
      `{${parameter.name}}`,
      `\${encodeURIComponent(String(input[${JSON.stringify(parameter.name)}]))}`
    );
  }

  return `\`${expression}\``;
}

function queryExpressionFor(operation: AgentOperation) {
  if (operation.queryParameters.length === 0) {
    return "";
  }

  const entries = operation.queryParameters
    .map((parameter) => `${JSON.stringify(parameter.name)}: input.${parameter.name}`)
    .join(", ");
  return `,
      query: { ${entries} }`;
}

function bodyExpressionFor(operation: AgentOperation) {
  if (operation.bodyType === null) {
    return "";
  }

  const value =
    operation.pathParameters.length === 0 && operation.queryParameters.length === 0
      ? "body"
      : "input.body";

  return `,
      body: ${value}`;
}

function capitalize(value: string) {
  return `${value.charAt(0).toUpperCase()}${value.slice(1)}`;
}

function literalType(value: unknown) {
  return value === null ? "null" : JSON.stringify(value);
}
