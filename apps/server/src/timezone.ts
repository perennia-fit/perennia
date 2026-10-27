// ---------------------------------------------------------------------------
// IANA timezone helpers shared by the Agent write paths
// (docs/designs/protocol-schedules-and-reminders.md, D2 and file 30). One
// `Intl.DateTimeFormat` configuration per zone answers both questions: the
// local calendar date of an instant, and its UTC offset at that instant. Both
// return null for a zone Intl does not know (an abbreviation such as "BRT" is
// not a zone) or for an invalid Date, and each caller decides its own fallback.
// ---------------------------------------------------------------------------

/**
 * Formatters by the zone string a caller passed. Only zones Intl accepts are
 * cached, and the cache is bounded: the strings come from requests, so an
 * unbounded cache keyed by them would grow for the life of the process. Real
 * zones number a few hundred; past the bound the cache starts over.
 */
const formatters = new Map<string, Intl.DateTimeFormat>();
const MAX_CACHED_FORMATTERS = 1024;

/** The cached formatter for `timeZone`, or null when Intl rejects the zone. */
function formatterFor(timeZone: string): Intl.DateTimeFormat | null {
  const cached = formatters.get(timeZone);
  if (cached !== undefined) {
    return cached;
  }
  let formatter: Intl.DateTimeFormat;
  try {
    formatter = new Intl.DateTimeFormat("en-CA", {
      timeZone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
      hourCycle: "h23"
    });
  } catch {
    return null;
  }
  if (formatters.size >= MAX_CACHED_FORMATTERS) {
    formatters.clear();
  }
  formatters.set(timeZone, formatter);
  return formatter;
}

type WallClockParts = {
  year: string;
  month: string;
  day: string;
  hour: string;
  minute: string;
  second: string;
};

function wallClockParts(instant: Date, timeZone: string): WallClockParts | null {
  if (Number.isNaN(instant.getTime())) {
    return null;
  }
  const formatter = formatterFor(timeZone);
  if (formatter === null) {
    return null;
  }
  const parts = formatter.formatToParts(instant);
  const part = (type: Intl.DateTimeFormatPartTypes) =>
    parts.find((candidate) => candidate.type === type)?.value;
  const year = part("year");
  const month = part("month");
  const day = part("day");
  const hour = part("hour");
  const minute = part("minute");
  const second = part("second");
  if (
    year === undefined ||
    month === undefined ||
    day === undefined ||
    hour === undefined ||
    minute === undefined ||
    second === undefined
  ) {
    return null;
  }
  return { year, month, day, hour, minute, second };
}

/** The `YYYY-MM-DD` date `instant` falls on in `timeZone`, or null. */
export function localDateInTimezone(instant: Date, timeZone: string): string | null {
  const parts = wallClockParts(instant, timeZone);
  return parts === null ? null : `${parts.year}-${parts.month}-${parts.day}`;
}

/**
 * The UTC offset of `timeZone` at `instant`, in whole minutes east of UTC
 * (UTC-3 is -180), or null. It is the zone's wall clock read as if it were UTC,
 * minus the instant, so a daylight-saving change applies on the side of the
 * change the instant is on.
 */
export function offsetMinutesInTimezone(instant: Date, timeZone: string): number | null {
  const parts = wallClockParts(instant, timeZone);
  if (parts === null) {
    return null;
  }
  const wallClockAsUtc = Date.UTC(
    Number(parts.year),
    Number(parts.month) - 1,
    Number(parts.day),
    Number(parts.hour),
    Number(parts.minute),
    Number(parts.second)
  );
  // Compared at whole seconds, as the formatter reads them.
  const instantSeconds = Math.floor(instant.getTime() / 1000) * 1000;
  return Math.round((wallClockAsUtc - instantSeconds) / 60_000);
}
