// ---------------------------------------------------------------------------
// Protocol Plan core (docs/designs/protocol-schedules-and-reminders.md, D1, D4,
// D6). The TypeScript twin of the app's
// apps/mobile/lib/domain/protocols/protocol_plan.dart and
// protocol_plan_days.dart: the same Schedule Rule and Protocol Period JSON,
// and the same `planDays`, `dayStatuses` and `dueUnfilled`. Both run
// packages/golden-vectors/vectors/m36-protocol-plan.json, so an Agent read and
// the app never disagree on what was planned or how a day reads.
//
// Pure: no database, no clock, no timezone. Dates are `YYYY-MM-DD` local dates
// and times are `HH:MM` wall-clock times; "today" and "now" are inputs. Date
// arithmetic is on UTC epoch days, so a daylight-saving change can never
// repeat or skip a date. Everything here is derived and never stored.
// ---------------------------------------------------------------------------

/** A local calendar date, `YYYY-MM-DD`. */
export type LocalDate = string;
/** A wall-clock time, `HH:MM`. */
export type LocalTime = string;

/** Which days a Schedule Rule is due on (rule JSON, version 1). */
export type ScheduleRuleDays =
  | { kind: "daily" }
  /** ISO 8601 weekdays, 1 = Monday; stored sorted. */
  | { kind: "weekdays"; weekdays: number[] }
  | { kind: "every_n_days"; n: number; anchor: LocalDate; anchor_is_default: boolean };

/**
 * A Schedule Rule as stored in a Schedule Version's `rule` column. The decoded
 * value keeps the stored JSON shape, so encoding is decoding again, which
 * drops any key the shape does not name.
 */
export type ScheduleRule =
  | { v: 1; kind: "timed"; days: ScheduleRuleDays; times: LocalTime[] }
  | { v: 1; kind: "untimed"; days: ScheduleRuleDays; count: number }
  | { v: 1; kind: "as_needed" }
  /** The member has no Schedule (a cleared Schedule inserts this). */
  | { v: 1; kind: "unscheduled" };

/** N days on, M days off, repeating from an anchor (D4). */
export type ProtocolCycle = {
  on_days: number;
  off_days: number;
  anchor: LocalDate;
  anchor_is_default: boolean;
};

/** A Pause: an inclusive date range on a Protocol. */
export type ProtocolPause = { from: LocalDate; to: LocalDate };

/**
 * A Protocol Period as stored in the Protocol's `period` column. A null
 * column means no cycle and no Pause; readers also accept this object with a
 * null cycle and no pauses.
 */
export type ProtocolPeriod = {
  v: 1;
  cycle: ProtocolCycle | null;
  pauses: ProtocolPause[];
};

/** The planned amount a Schedule Version carries; null for rules with none. */
export type PlanAmount = {
  amountValue?: number | null;
  amountEntered?: string | null;
  unit?: string | null;
  route?: string | null;
};

/** One Schedule Version: inserted on every changed save, never edited (D1). */
export type PlanScheduleVersion = PlanAmount & {
  id: string;
  effectiveFrom: LocalDate;
  rule: ScheduleRule;
};

/**
 * One Protocol Member row. It covers its first `effectiveFrom` through its
 * frozen `archivedOn`. Rows tombstoned by undo are left out by the caller.
 */
export type PlanMember = {
  memberId: string;
  compoundId: string;
  archivedOn?: LocalDate | null;
  versions: readonly PlanScheduleVersion[];
};

export type PlanProtocol = {
  protocolId: string;
  startLocalDate: LocalDate;
  /** Inclusive. Null is an ongoing Protocol. */
  endLocalDate?: LocalDate | null;
  period?: ProtocolPeriod | null;
  archivedOn?: LocalDate | null;
  remindersEnabled: boolean;
  members: readonly PlanMember[];
};

export type PlanDayState =
  | "planned"
  | "not_scheduled_today"
  | "as_needed"
  | "no_schedule"
  | "removed"
  | "outside"
  | "paused"
  | "off_cycle";

export type PlannedDose = PlanAmount & { localTime: LocalTime | null };

/** What one Protocol planned for one Compound on one date. */
export type PlanDay = {
  protocolId: string;
  compoundId: string;
  localDate: LocalDate;
  state: PlanDayState;
  /** Non-empty exactly when `state` is `planned`. */
  planned: PlannedDose[];
};

/**
 * A logged Dose as the core sees it. `sequence` is its index among the
 * Compound's Doses on that date, ordered by local time and then id.
 */
export type PlanDose = {
  doseId: string;
  compoundId: string;
  localDate: LocalDate;
  localTime: LocalTime;
  sequence: number;
};

export type DayStatusValue =
  | "not_planned"
  | "paused"
  | "off_cycle"
  | "pending"
  | "logged"
  | "partly_logged"
  | "not_logged";

export type NotPlannedReason =
  | "not_scheduled_today"
  | "as_needed"
  | "no_schedule"
  | "removed"
  | "outside";

export type DayStatusFill = PlanAmount & {
  slot: number;
  protocolId: string;
  plannedLocalTime: LocalTime | null;
  doseId: string | null;
};

/** How one Compound's logged Doses lined up with its plan on one date (D6). */
export type DayStatus = {
  compoundId: string;
  localDate: LocalDate;
  status: DayStatusValue;
  /** Present exactly when `status` is `not_planned`. */
  notPlannedReason?: NotPlannedReason;
  plannedCount: number;
  loggedCount: number;
  extraCount: number;
  fills: DayStatusFill[];
};

export type DueUnfilledDose = PlanAmount & {
  compoundId: string;
  slot: number;
  protocolId: string;
};

// ---------------------------------------------------------------------------
// Codecs. Any `v` other than 1 and any unknown `kind` is rejected, so a newer
// writer's rule is never misread as an older one. So are a value of the wrong
// type, a date that is not a real `YYYY-MM-DD` date and a time that is not
// `HH:MM` in 00:00-23:59, exactly as the Dart twin's decoders reject them; a
// whole number reads as an integer however it was written (`2.0` is 2), as
// JSON.parse already gives it.
//
// The ranges a decoder checks are plannability and the safe ceilings, both from
// PROTOCOL_PLAN_VALIDATION_LIMITS, and it checks them here, so the core never
// has to: every N days with N below 1 or above maxEveryNDays, an untimed count
// below 1 or above maxUntimedCount, a timed rule with no times or more than
// maxTimesPerDay, and a cycle of no days at all or with an on- or off-period
// below 0 or above maxCycleLengthDays are rejected, as the Dart twin's decoders
// reject them. The ceilings keep a synced row that was never validated from
// planning a billion doses, or a day count beyond 2^53, where the twins would
// plan different days. `planDays` runs every Protocol's period and rules
// through these checks once, so a caller that skipped decoding fails the same
// way. Every other range check (an every-N of 1, a cycle with no off-period) is
// the shared validators' job (D7), which read the stored JSON itself, so they
// can judge values these decoders would reject.
// ---------------------------------------------------------------------------

/**
 * The plan validators' limits, and the decoders' ceilings. Kept in lockstep
 * with the Dart `ProtocolPlanValidationLimits` and the validation vector's
 * `limits` block. Times and untimed counts start at 1, and cycle lengths at 1
 * day; `warnTimesPerDay` is the soft-warn boundary (exclusive). `maxPauses`
 * is the `pause_count` limit, a validation limit only: no decoder enforces
 * it, as in the Dart twin. Defined here, not in agent-validation.ts (which
 * re-exports it), because that module imports this one.
 */
export const PROTOCOL_PLAN_VALIDATION_LIMITS = {
  maxTimesPerDay: 12,
  maxUntimedCount: 12,
  minEveryNDays: 2,
  maxEveryNDays: 365,
  maxCycleLengthDays: 3650,
  warnTimesPerDay: 6,
  maxPauses: 100
} as const;

export class ProtocolPlanCodecError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ProtocolPlanCodecError";
  }
}

export function decodeScheduleRule(json: unknown): ScheduleRule {
  const object = requireObject(json, "Schedule Rule");
  requireVersion1(object, "Schedule Rule");
  switch (object.kind) {
    case "timed":
      return {
        v: 1,
        kind: "timed",
        days: decodeScheduleRuleDays(object.days),
        times: requireLocalTimes(object.times, "Schedule Rule times")
      };
    case "untimed":
      return {
        v: 1,
        kind: "untimed",
        days: decodeScheduleRuleDays(object.days),
        count: requireIntegerInRange(
          object.count,
          "Schedule Rule count",
          1,
          PROTOCOL_PLAN_VALIDATION_LIMITS.maxUntimedCount
        )
      };
    case "as_needed":
    case "unscheduled":
      return { v: 1, kind: object.kind };
    default:
      throw new ProtocolPlanCodecError(
        `Unknown Schedule Rule kind: ${String(object.kind)}.`
      );
  }
}

/**
 * The stored JSON of a rule: decoding builds a fresh object of only the known
 * keys, in stored order, so a key a caller added is never persisted, and a
 * rule the core cannot plan on is never written.
 */
export function encodeScheduleRule(rule: ScheduleRule): Record<string, unknown> {
  return decodeScheduleRule(rule);
}

export function decodeProtocolPeriod(json: unknown): ProtocolPeriod | null {
  if (json === null || json === undefined) {
    return null;
  }
  const object = requireObject(json, "Protocol Period");
  requireVersion1(object, "Protocol Period");
  return {
    v: 1,
    // A missing `cycle` key reads as null, as the Dart twin reads it.
    cycle:
      object.cycle === null || object.cycle === undefined
        ? null
        : decodeProtocolCycle(object.cycle),
    pauses: requireArray(object.pauses, "Protocol Period pauses").map((pause) => {
      const pauseObject = requireObject(pause, "Pause");
      return {
        from: requireLocalDate(pauseObject.from, "Pause from"),
        to: requireLocalDate(pauseObject.to, "Pause to")
      };
    })
  };
}

/** The stored JSON of a period, normalized as `encodeScheduleRule` normalizes a rule. */
export function encodeProtocolPeriod(
  period: ProtocolPeriod | null
): Record<string, unknown> | null {
  return decodeProtocolPeriod(period);
}

function decodeScheduleRuleDays(json: unknown): ScheduleRuleDays {
  const object = requireObject(json, "Schedule Rule days");
  switch (object.kind) {
    case "daily":
      return { kind: "daily" };
    case "weekdays":
      return {
        kind: "weekdays",
        weekdays: requireArray(object.weekdays, "Schedule Rule weekdays").map(
          (weekday) => requireInteger(weekday, "Schedule Rule weekday")
        )
      };
    case "every_n_days":
      return {
        kind: "every_n_days",
        n: requireIntegerInRange(
          object.n,
          "Schedule Rule n",
          1,
          PROTOCOL_PLAN_VALIDATION_LIMITS.maxEveryNDays
        ),
        anchor: requireLocalDate(object.anchor, "Schedule Rule anchor"),
        anchor_is_default: requireBoolean(
          object.anchor_is_default,
          "Schedule Rule anchor_is_default"
        )
      };
    default:
      throw new ProtocolPlanCodecError(
        `Unknown Schedule Rule days kind: ${String(object.kind)}.`
      );
  }
}

function decodeProtocolCycle(json: unknown): ProtocolCycle {
  const object = requireObject(json, "Protocol cycle");
  const maximum = PROTOCOL_PLAN_VALIDATION_LIMITS.maxCycleLengthDays;
  const onDays = requireIntegerInRange(object.on_days, "Protocol cycle on_days", 0, maximum);
  const offDays = requireIntegerInRange(object.off_days, "Protocol cycle off_days", 0, maximum);
  if (onDays + offDays < 1) {
    throw new ProtocolPlanCodecError("A Protocol cycle must be at least 1 day long.");
  }
  return {
    on_days: onDays,
    off_days: offDays,
    anchor: requireLocalDate(object.anchor, "Protocol cycle anchor"),
    anchor_is_default: requireBoolean(
      object.anchor_is_default,
      "Protocol cycle anchor_is_default"
    )
  };
}

/** Whether `json` is a JSON object: not null, not an array. */
export function isJsonObject(json: unknown): json is Record<string, unknown> {
  return typeof json === "object" && json !== null && !Array.isArray(json);
}

/**
 * Whether `json` is a whole number. JSON cannot tell 3.0 from 3, so neither
 * does this, nor the Dart twin's `planWholeNumber`.
 */
export function isWholeNumber(json: unknown): json is number {
  return typeof json === "number" && Number.isInteger(json);
}

function requireObject(json: unknown, what: string): Record<string, unknown> {
  if (!isJsonObject(json)) {
    throw new ProtocolPlanCodecError(`${what} must be a JSON object.`);
  }
  return json;
}

function requireVersion1(object: Record<string, unknown>, what: string) {
  if (object.v !== 1) {
    throw new ProtocolPlanCodecError(
      `${what} version ${String(object.v)} is not supported.`
    );
  }
}

function requireArray(json: unknown, what: string): unknown[] {
  if (!Array.isArray(json)) {
    throw new ProtocolPlanCodecError(`${what} must be an array.`);
  }
  return json;
}

function requireString(json: unknown, what: string): string {
  if (typeof json !== "string") {
    throw new ProtocolPlanCodecError(`${what} must be a string.`);
  }
  return json;
}

function requireLocalDate(json: unknown, what: string): LocalDate {
  const localDate = requireString(json, what);
  if (!isValidLocalDate(localDate)) {
    throw new ProtocolPlanCodecError(`${what} must be a real YYYY-MM-DD date.`);
  }
  return localDate;
}

function requireLocalTime(json: unknown, what: string): LocalTime {
  const localTime = requireString(json, what);
  if (!isPlanLocalTime(localTime)) {
    throw new ProtocolPlanCodecError(`${what} must be HH:MM, from 00:00 to 23:59.`);
  }
  return localTime;
}

/** A timed rule's times: at least one, the least the core can plan on, up to the ceiling. */
function requireLocalTimes(json: unknown, what: string): LocalTime[] {
  const times = requireArray(json, what).map((time) => requireLocalTime(time, `${what} entry`));
  const maximum = PROTOCOL_PLAN_VALIDATION_LIMITS.maxTimesPerDay;
  if (times.length === 0 || times.length > maximum) {
    throw new ProtocolPlanCodecError(`${what} must hold 1 to ${maximum} times.`);
  }
  return times;
}

function requireInteger(json: unknown, what: string): number {
  if (!isWholeNumber(json)) {
    throw new ProtocolPlanCodecError(`${what} must be an integer.`);
  }
  return json;
}

/** An integer from `minimum` to `maximum`, inclusive. */
function requireIntegerInRange(
  json: unknown,
  what: string,
  minimum: number,
  maximum: number
): number {
  const value = requireInteger(json, what);
  if (value < minimum || value > maximum) {
    throw new ProtocolPlanCodecError(`${what} must be ${minimum} to ${maximum}.`);
  }
  return value;
}

function requireBoolean(json: unknown, what: string): boolean {
  if (typeof json !== "boolean") {
    throw new ProtocolPlanCodecError(`${what} must be a boolean.`);
  }
  return json;
}

// ---------------------------------------------------------------------------
// Local-date arithmetic on UTC epoch days.
// ---------------------------------------------------------------------------

export const MS_PER_DAY = 24 * 60 * 60 * 1000;
const LOCAL_DATE_PATTERN = /^(\d{4})-(\d{2})-(\d{2})$/;
const LOCAL_TIME_PATTERN = /^([01]\d|2[0-3]):[0-5]\d$/;

/** Whether `value` is an `HH:MM` wall-clock time in 00:00-23:59. */
export function isPlanLocalTime(value: string): boolean {
  return LOCAL_TIME_PATTERN.test(value);
}

/**
 * The UTC epoch day of a `YYYY-MM-DD` date, or null when it is not a real
 * calendar date (`2026-02-30`, `2026-13-01`, another format).
 */
function localDateEpochDay(localDate: string): number | null {
  const match = LOCAL_DATE_PATTERN.exec(localDate);
  if (match === null) {
    return null;
  }
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  // Not Date.UTC, which reads years 0-99 as 1900-1999; the Dart twin's
  // DateTime.utc takes every four-digit year as written.
  const roundTrip = new Date(0);
  roundTrip.setUTCFullYear(year, month - 1, day);
  const epochMs = roundTrip.getTime();
  if (
    roundTrip.getUTCFullYear() !== year ||
    roundTrip.getUTCMonth() !== month - 1 ||
    roundTrip.getUTCDate() !== day
  ) {
    return null;
  }
  return epochMs / MS_PER_DAY;
}

export function isValidLocalDate(localDate: string): boolean {
  return localDateEpochDay(localDate) !== null;
}

/** The UTC epoch day of `localDate`; throws a RangeError for a non-date. */
export function epochDay(localDate: LocalDate): number {
  const day = localDateEpochDay(localDate);
  if (day === null) {
    throw new RangeError(`Not a local date: ${localDate}.`);
  }
  return day;
}

function localDateFromEpochDay(day: number): LocalDate {
  return new Date(day * MS_PER_DAY).toISOString().slice(0, 10);
}

/** ISO 8601 weekday of an epoch day, 1 = Monday through 7 = Sunday. */
function epochDayIsoWeekday(day: number): number {
  // Epoch day 0 (1970-01-01) was a Thursday, ISO weekday 4.
  return floorMod(day + 3, 7) + 1;
}

/**
 * A modulo that is never negative, so dates before an anchor count too.
 * `planDays` decodes every period and rule it plans on first, so every
 * divisor is a whole number of at least 1 day.
 */
function floorMod(value: number, divisor: number): number {
  return ((value % divisor) + divisor) % divisor;
}

// ---------------------------------------------------------------------------
// planDays (D1, D4).
// ---------------------------------------------------------------------------

/**
 * What each Protocol planned for each of its Compounds on every date from
 * `from` through `to`, inclusive. One PlanDay per Protocol, Compound and
 * date, ordered by date, then Protocol id, then Compound id.
 */
export function planDays(
  protocols: readonly PlanProtocol[],
  from: LocalDate,
  to: LocalDate
): PlanDay[] {
  const plans = protocols
    .map(protocolPlan)
    .sort((left, right) => compareIds(left.protocol.protocolId, right.protocol.protocolId));

  const days: PlanDay[] = [];
  const lastDay = epochDay(to);
  for (let day = epochDay(from); day <= lastDay; day += 1) {
    const localDate = localDateFromEpochDay(day);
    for (const plan of plans) {
      for (const compoundId of plan.compoundIds) {
        days.push(planDayFor(plan, compoundId, localDate, day));
      }
    }
  }
  return days;
}

/**
 * One Protocol as `planDays` reads it on every date, worked out once per call:
 * its optional fields read once, its period and rules decoded (so one built
 * from a cast payload is rejected with the codec's error, never planned on as
 * NaN), its cycle in epoch days, its Compound ids in order, and each
 * Compound's member rows.
 */
type ProtocolPlan = {
  protocol: PlanProtocol;
  endLocalDate: LocalDate | null;
  archivedOn: LocalDate | null;
  pauses: readonly ProtocolPause[];
  cycle: { anchorDay: number; length: number; onDays: number } | null;
  compoundIds: string[];
  /** Each Compound's rows, the larger `memberId` first. */
  rowsByCompound: Map<string, MemberRow[]>;
};

/** One member row, with its versions in `effectiveFrom` order, then id order. */
type MemberRow = {
  memberId: string;
  archivedOn: LocalDate | null;
  versions: VersionPlan[];
};

/** One Schedule Version, with its rule decoded and its amount and every-N anchor worked out once. */
type VersionPlan = {
  version: PlanScheduleVersion;
  amount: Required<PlanAmount>;
  /** The every-N-days anchor as an epoch day; 0 for any other days. */
  anchorDay: number;
};

function protocolPlan(protocol: PlanProtocol): ProtocolPlan {
  const rowsByCompound = new Map<string, MemberRow[]>();
  for (const member of protocol.members) {
    pushToGroup(rowsByCompound, member.compoundId, memberRow(member));
  }
  for (const rows of rowsByCompound.values()) {
    rows.sort((left, right) => compareIds(right.memberId, left.memberId));
  }
  const period = decodeProtocolPeriod(protocol.period ?? null);
  const cycle = period?.cycle ?? null;
  return {
    protocol,
    endLocalDate: protocol.endLocalDate ?? null,
    archivedOn: protocol.archivedOn ?? null,
    pauses: period?.pauses ?? [],
    cycle:
      cycle === null
        ? null
        : {
            anchorDay: epochDay(cycle.anchor),
            length: cycle.on_days + cycle.off_days,
            onDays: cycle.on_days
          },
    compoundIds: [...rowsByCompound.keys()].sort(compareIds),
    rowsByCompound
  };
}

function memberRow(member: PlanMember): MemberRow {
  const versions = member.versions
    .map((stored) => {
      const rule = decodeScheduleRule(stored.rule);
      return {
        version: { ...stored, rule },
        amount: planAmount(stored),
        anchorDay:
          rule.kind !== "as_needed" &&
          rule.kind !== "unscheduled" &&
          rule.days.kind === "every_n_days"
            ? epochDay(rule.days.anchor)
            : 0
      };
    })
    .sort(
      (left, right) =>
        compareIds(left.version.effectiveFrom, right.version.effectiveFrom) ||
        compareIds(left.version.id, right.version.id)
    );
  return { memberId: member.memberId, archivedOn: member.archivedOn ?? null, versions };
}

/**
 * D4's order: outside, paused, off cycle, removed, then the Schedule. `day` is
 * `localDate` as an epoch day, for the cycle and rule-day arithmetic.
 */
function planDayFor(
  plan: ProtocolPlan,
  compoundId: string,
  localDate: LocalDate,
  day: number
): PlanDay {
  const { protocol, endLocalDate, cycle } = plan;
  const unplanned = (state: PlanDayState): PlanDay => ({
    protocolId: protocol.protocolId,
    compoundId,
    localDate,
    state,
    planned: []
  });

  if (
    localDate < protocol.startLocalDate ||
    (endLocalDate !== null && localDate > endLocalDate)
  ) {
    return unplanned("outside");
  }

  if (plan.pauses.some((pause) => pause.from <= localDate && localDate <= pause.to)) {
    return unplanned("paused");
  }

  if (cycle !== null && floorMod(day - cycle.anchorDay, cycle.length) >= cycle.onDays) {
    return unplanned("off_cycle");
  }

  if (plan.archivedOn !== null && localDate > plan.archivedOn) {
    return unplanned("removed");
  }

  const row = coveringRow(plan.rowsByCompound.get(compoundId) ?? [], localDate);
  if (row === null) {
    return unplanned("removed");
  }

  const applying = applyingVersion(row.versions, localDate);
  if (applying === null || applying.version.rule.kind === "unscheduled") {
    return unplanned("no_schedule");
  }
  const rule = applying.version.rule;
  if (rule.kind === "as_needed") {
    return unplanned("as_needed");
  }
  if (!ruleDaysInclude(rule.days, day, applying.anchorDay)) {
    return unplanned("not_scheduled_today");
  }

  const { amount } = applying;
  return {
    protocolId: protocol.protocolId,
    compoundId,
    localDate,
    state: "planned",
    planned:
      rule.kind === "timed"
        ? rule.times.map((localTime) => ({ localTime, ...amount }))
        : Array.from({ length: rule.count }, () => ({ localTime: null, ...amount }))
  };
}

/**
 * The member row covering `localDate`: from its first version's
 * `effectiveFrom` through its `archivedOn` (the archive day itself is still
 * covered). When two rows cover one date (removed and re-added the same day),
 * the larger `memberId` wins, and `rows` come in that order, so the first
 * covering row is the one. A row with no versions has no first date, so it
 * covers every date up to its archive and plans nothing.
 */
function coveringRow(rows: readonly MemberRow[], localDate: LocalDate): MemberRow | null {
  for (const row of rows) {
    if (row.archivedOn !== null && localDate > row.archivedOn) {
      continue;
    }
    const first = row.versions[0];
    if (first === undefined || localDate >= first.version.effectiveFrom) {
      return row;
    }
  }
  return null;
}

/**
 * The version with the latest `effectiveFrom` on or before `localDate`; on a
 * shared date the larger id (UUIDv7, so the latest edit) wins, on every device
 * and the server alike (D1). In version order, that is the last one on or
 * before `localDate`.
 */
function applyingVersion(
  versions: readonly VersionPlan[],
  localDate: LocalDate
): VersionPlan | null {
  for (let index = versions.length - 1; index >= 0; index -= 1) {
    const candidate = versions[index]!;
    if (candidate.version.effectiveFrom <= localDate) {
      return candidate;
    }
  }
  return null;
}

function ruleDaysInclude(days: ScheduleRuleDays, day: number, anchorDay: number): boolean {
  switch (days.kind) {
    case "daily":
      return true;
    case "weekdays":
      return days.weekdays.includes(epochDayIsoWeekday(day));
    case "every_n_days":
      return floorMod(day - anchorDay, days.n) === 0;
  }
}

function planAmount(amount: PlanAmount): Required<PlanAmount> {
  return {
    amountValue: amount.amountValue ?? null,
    amountEntered: amount.amountEntered ?? null,
    unit: amount.unit ?? null,
    route: amount.route ?? null
  };
}

/** Appends `item` to the group `key` names in `groups`, starting it if new. */
function pushToGroup<T>(groups: Map<string, T[]>, key: string, item: T): void {
  const group = groups.get(key);
  if (group === undefined) {
    groups.set(key, [item]);
  } else {
    group.push(item);
  }
}

// ---------------------------------------------------------------------------
// dayStatuses (D6).
// ---------------------------------------------------------------------------

const NOT_PLANNED_REASON_ORDER: readonly NotPlannedReason[] = [
  "not_scheduled_today",
  "as_needed",
  "no_schedule",
  "removed",
  "outside"
];

type Slot = DayStatusFill & { position: number; minutes: number | null };

/**
 * One Day Status per Compound and date in `planDays`, up to and including
 * `today`, ordered by date and then Compound id. Dates after `today` have no
 * Day Status. Each logged Dose fills the unfilled timed slot nearest its time
 * (the earlier slot on a tie), else the first unfilled untimed slot, else it
 * is an extra. The Protocol a Dose was tagged with never decides what it
 * fills: the tag records provenance, never adherence.
 */
export function dayStatuses(
  planDays: readonly PlanDay[],
  doses: readonly PlanDose[],
  today: LocalDate
): DayStatus[] {
  const daysByGroup = new Map<string, PlanDay[]>();
  for (const planDay of planDays) {
    if (planDay.localDate <= today) {
      pushToGroup(daysByGroup, groupKey(planDay.compoundId, planDay.localDate), planDay);
    }
  }
  const dosesByGroup = new Map<string, PlanDose[]>();
  for (const dose of doses) {
    pushToGroup(dosesByGroup, groupKey(dose.compoundId, dose.localDate), dose);
  }

  // Every group holds at least one PlanDay, which names its Compound and date.
  return [...daysByGroup.entries()]
    .map(([key, days]) => ({ key, days, first: days[0]! }))
    .sort(
      (left, right) =>
        compareIds(left.first.localDate, right.first.localDate) ||
        compareIds(left.first.compoundId, right.first.compoundId)
    )
    .map(({ key, days, first }) =>
      dayStatusFor(first.compoundId, first.localDate, days, dosesByGroup.get(key) ?? [], today)
    );
}

function dayStatusFor(
  compoundId: string,
  localDate: LocalDate,
  days: readonly PlanDay[],
  doses: readonly PlanDose[],
  today: LocalDate
): DayStatus {
  // Step 1: every planned dose of every Protocol, numbered by time (untimed
  // last), then Protocol id, then position within its Protocol's list.
  const slots: Slot[] = days
    .filter((day) => day.state === "planned")
    .flatMap((day) =>
      day.planned.map((planned, position) => ({
        slot: 0,
        protocolId: day.protocolId,
        plannedLocalTime: planned.localTime,
        ...planAmount(planned),
        doseId: null,
        position,
        minutes: planned.localTime === null ? null : minutesOfDay(planned.localTime)
      }))
    )
    .sort(compareSlots);
  slots.forEach((slot, index) => {
    slot.slot = index;
  });

  // Steps 2-3: Doses in local-time order (then sequence, then id), each
  // filling the nearest unfilled timed slot, else the first unfilled untimed.
  let extraCount = 0;
  const orderedDoses = [...doses].sort(
    (left, right) =>
      compareIds(left.localTime, right.localTime) ||
      left.sequence - right.sequence ||
      compareIds(left.doseId, right.doseId)
  );
  for (const dose of orderedDoses) {
    const doseMinutes = minutesOfDay(dose.localTime);
    let target: Slot | null = null;
    let targetDistance = Number.POSITIVE_INFINITY;
    for (const slot of slots) {
      if (slot.doseId !== null || slot.minutes === null) {
        continue;
      }
      // Slots are in slot order, so a strict `<` keeps the earlier on a tie.
      const distance = Math.abs(slot.minutes - doseMinutes);
      if (distance < targetDistance) {
        target = slot;
        targetDistance = distance;
      }
    }
    target ??=
      slots.find((slot) => slot.doseId === null && slot.minutes === null) ?? null;
    if (target === null) {
      extraCount += 1;
    } else {
      target.doseId = dose.doseId;
    }
  }

  const plannedCount = slots.length;
  const loggedCount = slots.filter((slot) => slot.doseId !== null).length;
  const fills = slots.map(({ position: _position, minutes: _minutes, ...fill }) => fill);
  const counts = { plannedCount, loggedCount, extraCount, fills };

  if (plannedCount > 0) {
    let status: DayStatusValue;
    if (loggedCount >= plannedCount) {
      status = "logged";
    } else if (localDate === today) {
      status = "pending";
    } else {
      status = loggedCount > 0 ? "partly_logged" : "not_logged";
    }
    return { compoundId, localDate, status, ...counts };
  }

  const states = new Set(days.map((day) => day.state));
  if (states.has("paused")) {
    return { compoundId, localDate, status: "paused", ...counts };
  }
  if (states.has("off_cycle")) {
    return { compoundId, localDate, status: "off_cycle", ...counts };
  }
  const notPlannedReason = NOT_PLANNED_REASON_ORDER.find((reason) => states.has(reason));
  if (notPlannedReason === undefined) {
    // Every PlanDay of a group has a state, and with nothing planned it is one
    // of the states above, so a group always resolves before here (the Dart
    // twin throws the same way).
    throw new Error("A Compound date with nothing planned has no reason.");
  }
  return { compoundId, localDate, status: "not_planned", notPlannedReason, ...counts };
}

function compareSlots(left: Slot, right: Slot): number {
  if (left.minutes !== right.minutes) {
    if (left.minutes === null) {
      return 1;
    }
    if (right.minutes === null) {
      return -1;
    }
    return left.minutes - right.minutes;
  }
  return compareIds(left.protocolId, right.protocolId) || left.position - right.position;
}

/**
 * Minutes after local midnight for an `HH:MM` time. Anything else throws a
 * RangeError, as the Dart twin's `planLocalTimeMinutes` throws, so the twins
 * fail alike rather than matching on NaN or comparing "9:05" as a string.
 */
function minutesOfDay(localTime: LocalTime): number {
  if (!isPlanLocalTime(localTime)) {
    throw new RangeError(`Not an HH:MM local time: ${localTime}.`);
  }
  return Number(localTime.slice(0, 2)) * 60 + Number(localTime.slice(3));
}

function groupKey(compoundId: string, localDate: LocalDate): string {
  return `${localDate}\u0000${compoundId}`;
}

/**
 * Code-unit order, the same as Dart's `String.compareTo`, so ids, dates and
 * `HH:MM` times sort identically in both languages.
 */
export function compareIds(left: string, right: string): number {
  if (left === right) {
    return 0;
  }
  return left < right ? -1 : 1;
}

// ---------------------------------------------------------------------------
// dueUnfilled (D6).
// ---------------------------------------------------------------------------

/**
 * Today's unfilled planned doses that are due now: timed at or before
 * `nowLocalTime`, or untimed. "Log all planned" logs exactly these. Rows come
 * in Compound id order (Day Status order), then slot order; other dates
 * contribute nothing.
 */
export function dueUnfilled(
  dayStatuses: readonly DayStatus[],
  today: LocalDate,
  nowLocalTime: LocalTime
): DueUnfilledDose[] {
  const now = minutesOfDay(nowLocalTime);
  const due: DueUnfilledDose[] = [];
  const todays = dayStatuses
    .filter((dayStatus) => dayStatus.localDate === today)
    .sort((left, right) => compareIds(left.compoundId, right.compoundId));
  for (const dayStatus of todays) {
    const fills = [...dayStatus.fills].sort((left, right) => left.slot - right.slot);
    for (const fill of fills) {
      if (
        fill.doseId === null &&
        (fill.plannedLocalTime === null || minutesOfDay(fill.plannedLocalTime) <= now)
      ) {
        due.push({
          compoundId: dayStatus.compoundId,
          slot: fill.slot,
          protocolId: fill.protocolId,
          ...planAmount(fill)
        });
      }
    }
  }
  return due;
}
