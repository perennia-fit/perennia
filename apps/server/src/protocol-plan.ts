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
 * value keeps the stored JSON shape, so encoding is the identity.
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
// Codecs. They check the JSON's shape and version, never its values: a time of
// "25:00" decodes, and the shared validator rejects it (D7). Any `v` other
// than 1 and any unknown `kind` is rejected, so a newer writer's rule is never
// misread as an older one.
// ---------------------------------------------------------------------------

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
        times: requireArray(object.times, "Schedule Rule times").map((time) =>
          requireString(time, "Schedule Rule time")
        )
      };
    case "untimed":
      return {
        v: 1,
        kind: "untimed",
        days: decodeScheduleRuleDays(object.days),
        count: requireInteger(object.count, "Schedule Rule count")
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

export function encodeScheduleRule(rule: ScheduleRule): Record<string, unknown> {
  switch (rule.kind) {
    case "timed":
      return { v: 1, kind: "timed", days: encodeScheduleRuleDays(rule.days), times: [...rule.times] };
    case "untimed":
      return { v: 1, kind: "untimed", days: encodeScheduleRuleDays(rule.days), count: rule.count };
    case "as_needed":
    case "unscheduled":
      return { v: 1, kind: rule.kind };
  }
}

export function decodeProtocolPeriod(json: unknown): ProtocolPeriod | null {
  if (json === null || json === undefined) {
    return null;
  }
  const object = requireObject(json, "Protocol Period");
  requireVersion1(object, "Protocol Period");
  return {
    v: 1,
    cycle: object.cycle === null ? null : decodeProtocolCycle(object.cycle),
    pauses: requireArray(object.pauses, "Protocol Period pauses").map((pause) => {
      const pauseObject = requireObject(pause, "Pause");
      return {
        from: requireString(pauseObject.from, "Pause from"),
        to: requireString(pauseObject.to, "Pause to")
      };
    })
  };
}

export function encodeProtocolPeriod(
  period: ProtocolPeriod | null
): Record<string, unknown> | null {
  if (period === null) {
    return null;
  }
  return {
    v: 1,
    cycle: period.cycle === null ? null : { ...period.cycle },
    pauses: period.pauses.map((pause) => ({ from: pause.from, to: pause.to }))
  };
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
        n: requireInteger(object.n, "Schedule Rule n"),
        anchor: requireString(object.anchor, "Schedule Rule anchor"),
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

function encodeScheduleRuleDays(days: ScheduleRuleDays): Record<string, unknown> {
  switch (days.kind) {
    case "daily":
      return { kind: "daily" };
    case "weekdays":
      return { kind: "weekdays", weekdays: [...days.weekdays] };
    case "every_n_days":
      return {
        kind: "every_n_days",
        n: days.n,
        anchor: days.anchor,
        anchor_is_default: days.anchor_is_default
      };
  }
}

function decodeProtocolCycle(json: unknown): ProtocolCycle {
  const object = requireObject(json, "Protocol cycle");
  return {
    on_days: requireInteger(object.on_days, "Protocol cycle on_days"),
    off_days: requireInteger(object.off_days, "Protocol cycle off_days"),
    anchor: requireString(object.anchor, "Protocol cycle anchor"),
    anchor_is_default: requireBoolean(
      object.anchor_is_default,
      "Protocol cycle anchor_is_default"
    )
  };
}

function requireObject(json: unknown, what: string): Record<string, unknown> {
  if (typeof json !== "object" || json === null || Array.isArray(json)) {
    throw new ProtocolPlanCodecError(`${what} must be a JSON object.`);
  }
  return json as Record<string, unknown>;
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

function requireInteger(json: unknown, what: string): number {
  if (typeof json !== "number" || !Number.isInteger(json)) {
    throw new ProtocolPlanCodecError(`${what} must be an integer.`);
  }
  return json;
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

const MS_PER_DAY = 24 * 60 * 60 * 1000;
const LOCAL_DATE_PATTERN = /^(\d{4})-(\d{2})-(\d{2})$/;

/**
 * The UTC epoch day of a `YYYY-MM-DD` date, or null when it is not a real
 * calendar date (`2026-02-30`, `2026-13-01`, another format).
 */
export function localDateEpochDay(localDate: string): number | null {
  const match = LOCAL_DATE_PATTERN.exec(localDate);
  if (match === null) {
    return null;
  }
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const epochMs = Date.UTC(year, month - 1, day);
  const roundTrip = new Date(epochMs);
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

function epochDay(localDate: LocalDate): number {
  const day = localDateEpochDay(localDate);
  if (day === null) {
    throw new RangeError(`Not a local date: ${localDate}.`);
  }
  return day;
}

function localDateFromEpochDay(day: number): LocalDate {
  return new Date(day * MS_PER_DAY).toISOString().slice(0, 10);
}

/** Whole days from `from` to `to`; negative when `to` is earlier. */
function localDaysBetween(from: LocalDate, to: LocalDate): number {
  return epochDay(to) - epochDay(from);
}

/** ISO 8601 weekday, 1 = Monday through 7 = Sunday. */
function localDateIsoWeekday(localDate: LocalDate): number {
  // Epoch day 0 (1970-01-01) was a Thursday, ISO weekday 4.
  return floorMod(epochDay(localDate) + 3, 7) + 1;
}

/** A modulo that is never negative, so dates before an anchor count too. */
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
  const sortedProtocols = [...protocols].sort((left, right) =>
    compareIds(left.protocolId, right.protocolId)
  );
  const compoundIdsByProtocol = sortedProtocols.map((protocol) =>
    [...new Set(protocol.members.map((member) => member.compoundId))].sort(compareIds)
  );

  const days: PlanDay[] = [];
  const lastDay = epochDay(to);
  for (let day = epochDay(from); day <= lastDay; day += 1) {
    const localDate = localDateFromEpochDay(day);
    sortedProtocols.forEach((protocol, index) => {
      for (const compoundId of compoundIdsByProtocol[index]!) {
        days.push(planDayFor(protocol, compoundId, localDate));
      }
    });
  }
  return days;
}

/** D4's order: outside, paused, off cycle, removed, then the Schedule. */
function planDayFor(
  protocol: PlanProtocol,
  compoundId: string,
  localDate: LocalDate
): PlanDay {
  const unplanned = (state: PlanDayState): PlanDay => ({
    protocolId: protocol.protocolId,
    compoundId,
    localDate,
    state,
    planned: []
  });

  const endLocalDate = protocol.endLocalDate ?? null;
  if (
    localDate < protocol.startLocalDate ||
    (endLocalDate !== null && localDate > endLocalDate)
  ) {
    return unplanned("outside");
  }

  const period = protocol.period ?? null;
  if (
    period !== null &&
    period.pauses.some((pause) => pause.from <= localDate && localDate <= pause.to)
  ) {
    return unplanned("paused");
  }

  const cycle = period?.cycle ?? null;
  if (
    cycle !== null &&
    floorMod(localDaysBetween(cycle.anchor, localDate), cycle.on_days + cycle.off_days) >=
      cycle.on_days
  ) {
    return unplanned("off_cycle");
  }

  const protocolArchivedOn = protocol.archivedOn ?? null;
  if (protocolArchivedOn !== null && localDate > protocolArchivedOn) {
    return unplanned("removed");
  }

  const member = coveringMember(protocol.members, compoundId, localDate);
  if (member === null) {
    return unplanned("removed");
  }

  const version = applyingVersion(member.versions, localDate);
  if (version === null || version.rule.kind === "unscheduled") {
    return unplanned("no_schedule");
  }
  const rule = version.rule;
  if (rule.kind === "as_needed") {
    return unplanned("as_needed");
  }
  if (!ruleDaysInclude(rule.days, localDate)) {
    return unplanned("not_scheduled_today");
  }

  const amount = planAmount(version);
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
 * The member row of `compoundId` covering `localDate`: from its first
 * version's `effectiveFrom` through its `archivedOn` (the archive day itself
 * is still covered). When two rows cover one date (removed and re-added the
 * same day), the larger `memberId` wins. A row with no versions has no first
 * date, so it covers every date up to its archive and plans nothing.
 */
function coveringMember(
  members: readonly PlanMember[],
  compoundId: string,
  localDate: LocalDate
): PlanMember | null {
  let covering: PlanMember | null = null;
  for (const member of members) {
    if (member.compoundId !== compoundId) {
      continue;
    }
    const archivedOn = member.archivedOn ?? null;
    if (archivedOn !== null && localDate > archivedOn) {
      continue;
    }
    const firstEffectiveFrom = member.versions.reduce<LocalDate | null>(
      (earliest, version) =>
        earliest === null || version.effectiveFrom < earliest
          ? version.effectiveFrom
          : earliest,
      null
    );
    if (firstEffectiveFrom !== null && localDate < firstEffectiveFrom) {
      continue;
    }
    if (covering === null || compareIds(member.memberId, covering.memberId) > 0) {
      covering = member;
    }
  }
  return covering;
}

/**
 * The version with the latest `effectiveFrom` on or before `localDate`; on a
 * shared date the larger id (UUIDv7, so the latest edit) wins, on every device
 * and the server alike (D1).
 */
function applyingVersion(
  versions: readonly PlanScheduleVersion[],
  localDate: LocalDate
): PlanScheduleVersion | null {
  let applying: PlanScheduleVersion | null = null;
  for (const version of versions) {
    if (version.effectiveFrom > localDate) {
      continue;
    }
    if (
      applying === null ||
      version.effectiveFrom > applying.effectiveFrom ||
      (version.effectiveFrom === applying.effectiveFrom &&
        compareIds(version.id, applying.id) > 0)
    ) {
      applying = version;
    }
  }
  return applying;
}

function ruleDaysInclude(days: ScheduleRuleDays, localDate: LocalDate): boolean {
  switch (days.kind) {
    case "daily":
      return true;
    case "weekdays":
      return days.weekdays.includes(localDateIsoWeekday(localDate));
    case "every_n_days":
      return floorMod(localDaysBetween(days.anchor, localDate), days.n) === 0;
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

type Slot = DayStatusFill & { position: number };

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
  const groups = new Map<string, { compoundId: string; localDate: LocalDate; days: PlanDay[] }>();
  for (const planDay of planDays) {
    if (planDay.localDate > today) {
      continue;
    }
    const key = groupKey(planDay.compoundId, planDay.localDate);
    const group = groups.get(key);
    if (group === undefined) {
      groups.set(key, {
        compoundId: planDay.compoundId,
        localDate: planDay.localDate,
        days: [planDay]
      });
    } else {
      group.days.push(planDay);
    }
  }

  const dosesByGroup = new Map<string, PlanDose[]>();
  for (const dose of doses) {
    const key = groupKey(dose.compoundId, dose.localDate);
    const groupDoses = dosesByGroup.get(key);
    if (groupDoses === undefined) {
      dosesByGroup.set(key, [dose]);
    } else {
      groupDoses.push(dose);
    }
  }

  return [...groups.entries()]
    .sort(([, left], [, right]) =>
      left.localDate === right.localDate
        ? compareIds(left.compoundId, right.compoundId)
        : compareIds(left.localDate, right.localDate)
    )
    .map(([key, group]) =>
      dayStatusFor(group.compoundId, group.localDate, group.days, dosesByGroup.get(key) ?? [], today)
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
        position
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
      if (slot.doseId !== null || slot.plannedLocalTime === null) {
        continue;
      }
      // Slots are in slot order, so a strict `<` keeps the earlier on a tie.
      const distance = Math.abs(minutesOfDay(slot.plannedLocalTime) - doseMinutes);
      if (distance < targetDistance) {
        target = slot;
        targetDistance = distance;
      }
    }
    target ??=
      slots.find((slot) => slot.doseId === null && slot.plannedLocalTime === null) ?? null;
    if (target === null) {
      extraCount += 1;
    } else {
      target.doseId = dose.doseId;
    }
  }

  const plannedCount = slots.length;
  const loggedCount = slots.filter((slot) => slot.doseId !== null).length;
  const fills = slots.map(({ position: _position, ...fill }) => fill);
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
  if (left.plannedLocalTime !== right.plannedLocalTime) {
    if (left.plannedLocalTime === null) {
      return 1;
    }
    if (right.plannedLocalTime === null) {
      return -1;
    }
    return compareIds(left.plannedLocalTime, right.plannedLocalTime);
  }
  return compareIds(left.protocolId, right.protocolId) || left.position - right.position;
}

function minutesOfDay(localTime: LocalTime): number {
  const [hours, minutes] = localTime.split(":");
  return Number(hours) * 60 + Number(minutes);
}

function groupKey(compoundId: string, localDate: LocalDate): string {
  return `${localDate}\u0000${compoundId}`;
}

/**
 * Code-unit order, the same as Dart's `String.compareTo`, so ids, dates and
 * `HH:MM` times sort identically in both languages.
 */
function compareIds(left: string, right: string): number {
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
  const due: DueUnfilledDose[] = [];
  const todays = dayStatuses
    .filter((dayStatus) => dayStatus.localDate === today)
    .sort((left, right) => compareIds(left.compoundId, right.compoundId));
  for (const dayStatus of todays) {
    const fills = [...dayStatus.fills].sort((left, right) => left.slot - right.slot);
    for (const fill of fills) {
      if (
        fill.doseId === null &&
        (fill.plannedLocalTime === null || fill.plannedLocalTime <= nowLocalTime)
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
