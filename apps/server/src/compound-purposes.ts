// Compound Purposes: the starter set and the name and id rules, the twin of
// apps/mobile/lib/domain/protocols/compound_purposes.dart. The golden vectors
// m40-compound-purposes hold the two together
// (docs/designs/compound-purposes.md, D3 and D8). The seed tag table has no copy
// here: tags reach the server as stored data, through sync.

export type StarterPurpose = {
  readonly id: string;
  readonly name: string;
  readonly sortOrder: number;
};

export const STARTER_PURPOSES: readonly StarterPurpose[] = [
  { id: "019200ff-0000-7000-8000-000000000101", name: "Sleep", sortOrder: 0 },
  { id: "019200ff-0000-7000-8000-000000000102", name: "Body composition", sortOrder: 1 },
  { id: "019200ff-0000-7000-8000-000000000103", name: "Performance", sortOrder: 2 },
  { id: "019200ff-0000-7000-8000-000000000104", name: "Recovery", sortOrder: 3 },
  { id: "019200ff-0000-7000-8000-000000000105", name: "Cognition", sortOrder: 4 },
  { id: "019200ff-0000-7000-8000-000000000106", name: "General health", sortOrder: 5 }
];

export type PurposeNameErrorCode = "purpose_name_required" | "duplicate_purpose_name";

// A Purpose name validatePurposeName hard-rejected. There is no soft tier.
export class PurposeNameError extends Error {
  readonly code: PurposeNameErrorCode;
  readonly purposeName: string;

  constructor(code: PurposeNameErrorCode, purposeName: string) {
    super(`${code}: ${purposeName}`);
    this.name = "PurposeNameError";
    this.code = code;
    this.purposeName = purposeName;
  }
}

// What two Purpose names are compared by: trimmed and case-insensitive.
export function purposeNameKey(name: string): string {
  return name.trim().toLowerCase();
}

// Collapses repeated ids, keeping the first occurrence and the order. Never
// sorts: the list keeps the order the user tagged in.
export function normalizePurposeIds(ids: Iterable<string>): string[] {
  return [...new Set(ids)];
}

// Returns the name trimmed, the form it is stored in, or throws
// PurposeNameError. Callers pass only active names, without the Purpose being
// renamed, so an archived Purpose's name is free to reuse.
export function validatePurposeName(
  name: string,
  activeNamesExcludingSelf: Iterable<string>
): string {
  const trimmed = name.trim();
  if (trimmed.length === 0) {
    throw new PurposeNameError("purpose_name_required", name);
  }
  const key = purposeNameKey(trimmed);
  for (const other of activeNamesExcludingSelf) {
    if (purposeNameKey(other) === key) {
      throw new PurposeNameError("duplicate_purpose_name", name);
    }
  }
  return trimmed;
}
