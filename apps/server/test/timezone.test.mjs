import assert from "node:assert/strict";
import test from "node:test";

import {
  localDateAtOffset,
  localDateInTimezone,
  offsetMinutesInTimezone
} from "../src/timezone.ts";

test("localDateAtOffset reads the date at a frozen offset", () => {
  const cases = [
    // Forward across midnight.
    ["2026-03-10T22:30:00Z", 120, "2026-03-11"],
    // Backward across midnight.
    ["2026-03-10T01:30:00Z", -180, "2026-03-09"],
    // The extremes of the accepted offset range.
    ["2026-03-10T10:30:00Z", 840, "2026-03-11"],
    ["2026-03-10T09:59:59Z", 840, "2026-03-10"],
    ["2026-03-10T11:30:00Z", -720, "2026-03-09"],
    ["2026-03-10T12:00:00Z", -720, "2026-03-10"],
    // UTC, either side of midnight.
    ["2026-03-10T23:59:59Z", 0, "2026-03-10"],
    ["2026-03-11T00:00:00Z", 0, "2026-03-11"],
    // Month and year boundaries.
    ["2026-12-31T20:00:00Z", 300, "2027-01-01"],
    ["2026-03-01T02:00:00Z", -180, "2026-02-28"]
  ];
  for (const [instant, offsetMinutes, expected] of cases) {
    assert.equal(
      localDateAtOffset(new Date(instant), offsetMinutes),
      expected,
      `${instant} at ${offsetMinutes}`
    );
  }
});

test("offsetMinutesInTimezone follows a daylight-saving change", () => {
  // Europe/Lisbon moves from UTC+0 to UTC+1 at 01:00Z on 29 March 2026.
  assert.equal(
    offsetMinutesInTimezone(new Date("2026-03-29T00:59:59Z"), "Europe/Lisbon"),
    0
  );
  assert.equal(
    offsetMinutesInTimezone(new Date("2026-03-29T01:00:00Z"), "Europe/Lisbon"),
    60
  );
  // America/New_York moves from UTC-5 to UTC-4 at 07:00Z on 8 March 2026.
  assert.equal(
    offsetMinutesInTimezone(new Date("2026-03-08T06:59:59Z"), "America/New_York"),
    -300
  );
  assert.equal(
    offsetMinutesInTimezone(new Date("2026-03-08T07:00:00Z"), "America/New_York"),
    -240
  );
});

test("an abbreviation is not a zone", () => {
  const instant = new Date("2026-03-10T12:00:00Z");
  assert.equal(localDateInTimezone(instant, "BRT"), null);
  assert.equal(offsetMinutesInTimezone(instant, "BRT"), null);
});
