# Changelog

Notable changes to Perennia. This is the single user-facing history for the app
and the server together — they share a version.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html). While
the project is pre-1.0, the API is not yet stable and minor versions may break it.

## [Unreleased]

### Changed

- Onboarding explains each screen and shows which step you are on. Experience asks
  which kinds of training you do, with what each covers, before asking your level.
- Training setup offers Gym, Home and Bodyweight only presets and groups the
  equipment. Onboarding starts from Gym, so Done saves a typical gym list.

## [0.3.0] - 2026-11-07

A minor release: one screen for logging meals, rest timer cues and a Finish
summary, editing Compounds and tagging them with Purposes, exercise library
updates for installed apps, and an optional User Profile with first-open
onboarding. It adds three Drift schema versions, three server migrations and new
Agent operations. Upgrade a Self-Hosted Deployment before the app, because a newer
app's pushes fail against an older server, and update every synced device
together. Agent clients should read the `batchWriteAgentMeal` changes below.

### Added

- **Optional first-open onboarding,** skippable from its first screen.
  ([#141](https://github.com/perennia-fit/perennia/pull/141))
- **Profile** under Account & app, with an Agent read and write
  (`readAgentProfile`, `batchWriteAgentProfile`). ([#140](https://github.com/perennia-fit/perennia/pull/140))
- **Log a meal from one screen:** repeat a whole meal from Your meals, add
  foods, or save just the time and add foods later. ([#111](https://github.com/perennia-fit/perennia/pull/111))
- **The rest timer warns you before it ends.** The strip and a tone mark Get
  ready 10 seconds before the end of a longer rest, 3-2-1 plays in the app, and
  after 0:00 the strip shows Rest over with the time since. ([#122](https://github.com/perennia-fit/perennia/pull/122))
- **Edit and archive a Compound,** and create one from the Protocol editor's
  picker. ([#131](https://github.com/perennia-fit/perennia/pull/131))
- **Purposes:** tag a Compound with why you take it, such as Sleep or
  Performance, filter the Compound list and the picker by Purpose, and rename,
  reorder, archive or add Purposes from the Compound list's menu. The six
  built-in Compounds arrive tagged, and any tag you remove stays removed.
  ([#132](https://github.com/perennia-fit/perennia/pull/132))
- **Agents can list Meal Types** (`listAgentMealTypes`,
  `GET /agent/meal-types`, `agent_list_meal_types`): the user's active Meal
  Types in the order the app shows them, to choose a `mealType` from.
  ([#108](https://github.com/perennia-fit/perennia/pull/108))
- **`listAgentMeals` returns each Meal's `timezoneOffsetMinutes` and
  `timePrecision`.** Meals written before this change read `null` and
  `instant`. ([#108](https://github.com/perennia-fit/perennia/pull/108))
- **Agents can read the user's repeated meals** (`listAgentMealHistory`,
  `GET /agent/meals/history`, `agent_list_meal_history`): the sets of Foods
  they log together, most often in the last 90 days first, each with the
  latest Meal that had them. ([#110](https://github.com/perennia-fit/perennia/pull/110))
- **Agents can read and write Purposes** (`listAgentPurposes`,
  `GET /agent/protocols/purposes`, `agent_list_purposes`;
  `batchWriteAgentPurposes`, `POST /agent/protocols/purposes/batch-write`,
  `agent_batch_write_purposes`), and read and write `purposeIds` on Compounds
  and filter them by Purpose. ([#132](https://github.com/perennia-fit/perennia/pull/132))

### Changed

- **Exercise library updates now reach installed apps.** Renames and corrections
  apply in place. An exercise the library merges or removes stays as your own if
  you logged it or have it in a Workout or Template, and disappears otherwise.
  Agents see a kept exercise as yours, with its own Sets. If you sync more than
  one device, update them together: a device on an older build can't update its
  exercise library once it pulls an exercise you kept. ([#136](https://github.com/perennia-fit/perennia/pull/136), [#137](https://github.com/perennia-fit/perennia/pull/137))
- **A cleaner Platform Exercise Library** (1,745 to 1,450 exercises). Near-duplicates
  such as "Squats" alongside "Barbell Squat" merge, non-English names go, and 80
  names are corrected, including every `(male)` or `(female)` label and typos
  like `Shrimp Squad`. Entries that were not real exercises, such as `bicep` and
  `Rest (for timed workouts)`, are removed. The Endurance, Weights and Calisthenics
  staples now offer Running, Skipping - Standard, Overhead Barbell Press and Full
  Plank. ([#113](https://github.com/perennia-fit/perennia/pull/113), [#116](https://github.com/perennia-fit/perennia/pull/116), [#117](https://github.com/perennia-fit/perennia/pull/117), [#144](https://github.com/perennia-fit/perennia/pull/144))
- **Messages have one style.** Every message in the app is now a dark bar with
  rounded corners, in both themes, floating above the screen's bottom bar and
  buttons. Its text and action pass WCAG AA; the Undo label was close to
  invisible in the light theme. ([#119](https://github.com/perennia-fit/perennia/pull/119))
- **Training Screen messages no longer cover the form.** "Set n logged" with
  Undo and every other Training Screen message now show in the rest strip's
  row, and the rest countdown comes back when the message ends. "Background
  timer alerts are off" shows once per app run and never replaces an Undo.
  ([#121](https://github.com/perennia-fit/perennia/pull/121))
- **Finish ends on one summary.** Finish Workout opens a sheet with the
  Workout's duration, sets, exercises and New Bests, an Update row that lists
  template changes in plain words ("Remove Hip Thrust", "Deadlift: sets
  changed"), Copy summary and Done, replacing the "Workout finished" message
  and the update dialog. The Workout menu's Update template dialog uses the
  same words. ([#125](https://github.com/perennia-fit/perennia/pull/125))
- **A meal's time is shown and can be changed,** its meal type is proposed from
  the time, and the Nutrition Day lists meals in time order. ([#111](https://github.com/perennia-fit/perennia/pull/111))
- **The Protocol editor puts Compounds first,** picks them from a searchable
  sheet, and asks before discarding unsaved changes. An added Compound starts
  every day at 9:00. ([#131](https://github.com/perennia-fit/perennia/pull/131))
- **`batchWriteAgentMeal` writes only the Meal fields a request sends.** An
  absent field keeps its stored value, `null` clears `endedAt` or
  `deletedAt`, a request with only entries leaves the Meal untouched, and
  `entries` may be empty. `localDate` is derived when the offset is known,
  from `timezoneOffsetMinutes` or an IANA `timezone`. ([#108](https://github.com/perennia-fit/perennia/pull/108))
- **Archiving a Meal through `batchWriteAgentMeal` must tombstone its Food
  Entries.** A request that sets `meal.deletedAt` sends every active Food Entry
  of that Meal with `deletedAt` set, as the app's delete does, or fails with
  `422` `meal_archived`; so does a tombstone whose `updatedAt` would lose to
  the stored entry. ([#108](https://github.com/perennia-fit/perennia/pull/108))

### Fixed

- **Server crash reports no longer carry request bodies or session cookies.**
  With crash reporting on, a server error could send what was being written, or
  the parsed session cookie, to Sentry. ([#140](https://github.com/perennia-fit/perennia/pull/140), [#145](https://github.com/perennia-fit/perennia/pull/145))
- **A Compound strength an Agent writes no longer stops sync.** An Agent
  stored a Compound's strength, and a Dose's strength snapshot, in a shape the
  app couldn't read, so one such row made every sync pull on a device fail. In
  turn, Agents read every strength the app wrote as `null`. Agents now store
  the app's label (such as `5 mg/capsule`), both sides read rows already
  stored in either shape, and an Agent write of a strength the app can't hold
  (a unit outside the registry, an amount that isn't positive) is refused with
  `compound_strength`. ([#102](https://github.com/perennia-fit/perennia/pull/102))
- **An Agent edit no longer un-stars a Compound.** An Agent that renamed or
  changed a Compound you had starred cleared the star on your devices at the
  next sync. The server now keeps the star when an Agent write leaves it out,
  and a Compound an Agent created can be undone on the device instead of being
  reported as changed since. ([#103](https://github.com/perennia-fit/perennia/pull/103))
- **Confirmations with Undo now go away.** "Set 3 logged · Undo", "Replaced ·
  Undo" and "Workout finished · Share" stayed on screen until the next message,
  covering the logging form and following you to Today, where "Workout
  finished" never got its turn. They now close after 4 seconds, and a Training
  Screen's confirmation closes with the screen. ([#101](https://github.com/perennia-fit/perennia/pull/101))
- **A double tap on Finish Workout finishes it once.** ([#130](https://github.com/perennia-fit/perennia/pull/130))
- **Rest timer sounds off now silences rest timer notifications** on Android 8
  and later. ([#122](https://github.com/perennia-fit/perennia/pull/122))
- **The end of a rest now sounds on Android when the app is in the background.**
  ([#124](https://github.com/perennia-fit/perennia/pull/124))
- **A Meal started on a past day is saved on that day, not today.** ([#110](https://github.com/perennia-fit/perennia/pull/110))
- **Re-importing a file no longer moves a food out of a meal you edited.**
  ([#110](https://github.com/perennia-fit/perennia/pull/110))
- **A Protocol whose Compound was archived can be saved again.** ([#131](https://github.com/perennia-fit/perennia/pull/131))
- **A second device's seed no longer overrides a built-in Compound renamed after
  24 October 2026.** ([#132](https://github.com/perennia-fit/perennia/pull/132), [#133](https://github.com/perennia-fit/perennia/pull/133))
- **A backup with an unreadable value on a library exercise no longer stops the
  app seeding.** The next launch repairs the exercise from the library.
  ([#139](https://github.com/perennia-fit/perennia/pull/139))
- **A malformed id list in a synced row no longer fails Agent reads.** A raw array
  holding an entry that can't be turned into a string now reads as an empty list.
  ([#135](https://github.com/perennia-fit/perennia/pull/135))
- **An Agent write no longer un-archives a Meal, drops Food Entry import
  keys, or moves an entry to another Meal.** ([#108](https://github.com/perennia-fit/perennia/pull/108))
- **`batchWriteAgentMeal` rejects a malformed timestamp with a 400.**
  `startedAt`, `endedAt`, `deletedAt` and an entry's `updatedAt` and `deletedAt`
  must be ISO-8601 with `Z` or a UTC offset. ([#118](https://github.com/perennia-fit/perennia/pull/118))
- **An Agent undo is refused when other writes added foods to the Meal it
  created.** The undo returns `skipped_dependent` and applies nothing.
  ([#108](https://github.com/perennia-fit/perennia/pull/108))

## [0.2.0] - 2026-11-03

A minor release: the Progress Overview with new agent reads, logging against
the plan on the Training Screen, Skips and delete for Protocols, and a color for
each Focus. It adds two Drift schema versions, a server migration and new Agent
operations. Update the server and every device: a device still on 0.1.0 shows a
skipped dose as not yet logged.

### Added

- **Progress Overview.** The Progress tab opens on one scroll of summary cards
  over 4 weeks, 12 weeks or a year: This week, Trained days, Time by Focus, Key
  exercises, New bests, Body and Protocols. The Body card draws each Body
  Tracker measurement's Trend, smoothed over about 10 days, with its change
  over the period. ([#86](https://github.com/perennia-fit/perennia/pull/86),
  [#90](https://github.com/perennia-fit/perennia/pull/90),
  [#92](https://github.com/perennia-fit/perennia/pull/92))
- **Progress reads for agents.** `listAgentTrainingDays`
  (`GET /agent/progress/training-days`, `agent_list_training_days`) and
  `listAgentNewBests` (`GET /agent/progress/new-bests`,
  `agent_list_new_bests`) are new; exercise analytics gain `progressSeries`;
  and `GET /agent/metrics/readings` (`agent_list_metric_readings`) takes
  `includeTrend`, which adds each reading's `trendValue`.
  ([#86](https://github.com/perennia-fit/perennia/pull/86),
  [#90](https://github.com/perennia-fit/perennia/pull/90),
  [#92](https://github.com/perennia-fit/perennia/pull/92))
- **Delete a Protocol nothing was logged for**, from its editor or through the
  Agent API (`delete-protocols`).
  ([#93](https://github.com/perennia-fit/perennia/pull/93))
- **Skip a planned dose**, today or on a past day: it reads Skipped instead of
  Pending or Not logged, and the Agent API can do the same
  (`log-protocol-skips`). Update every device: older versions show skipped
  doses as not yet logged.
  ([#95](https://github.com/perennia-fit/perennia/pull/95))
- **Replace an exercise inside a Workout**, from the Training Screen's menu or
  the ⋮ button on a Workout card. The new exercise takes the old one's place in
  the order and in its superset, with the remaining planned sets at the same
  rests and the values you last did it with. Sets you already did stay with
  the old exercise, and **Undo** puts everything back.
  ([#99](https://github.com/perennia-fit/perennia/pull/99))
- **A color for each Focus.** The Focus manager's row menu has **Color**, with
  seven labelled swatches, and each row shows its Focus's color. A Focus you
  never recolor keeps a default color, and Time by Focus uses these colors.
  ([#83](https://github.com/perennia-fit/perennia/pull/83))

### Changed

- **Archiving a Protocol** stops asking for that day's doses you haven't
  logged, and asks for confirmation first.
  ([#93](https://github.com/perennia-fit/perennia/pull/93))
- **Logging against the plan.** The Training Screen logs the next planned set
  with one **Log set *n* of *m*** button pinned in thumb reach, in place of the
  checkbox, pencil and Save. A changed weight carries to the later sets that
  planned the same weight, a superset moves to the next exercise in the group,
  and each set's rest is set in **Rest after** and remembered for next time. Set
  rows show done, next and planned; a planned set is removed by swiping it away,
  and **Not done** turns a logged set back into a planned one. The rest timer is
  a strip above Log set with −15 s and +15 s.
  ([#94](https://github.com/perennia-fit/perennia/pull/94))
- **Progress against the plan.** A Workout started from a Template takes the
  Template's name as its title. Its exercise cards and the Navigation Panel read
  "*performed*/*total* sets" while sets are still planned and **Done** once
  none are, the first card of a group shows "Round *r* of *R*", and **Now**
  marks the exercise to do next. A Today tile counts "*performed* of *total*
  sets", and a day whose Workout has no logged set yet still reads "No workout
  started". ([#96](https://github.com/perennia-fit/perennia/pull/96))
- **Look before starting.** Tapping an Up next card or a workout in the
  Routines sheet opens a preview of its exercises, each Prescription and its
  supersets, with **Start workout**; the ▶ button beside it starts straight
  away, and a quick double tap on an Up next card's ▶ starts one workout, not
  two. The Routines sheet's eye icon is gone.
  ([#98](https://github.com/perennia-fit/perennia/pull/98))

### Fixed

- The Track prefill comes from the sets you last did, not from planned sets
  left behind in an unfinished workout.
  ([#88](https://github.com/perennia-fit/perennia/pull/88))
- Tapping a number field on the Training Screen selects its value, so typing
  replaces it: tapping a 0 and typing 26 used to save 026.
  ([#88](https://github.com/perennia-fit/perennia/pull/88))
- A set with a planned rest of 0 s no longer breaks the rest timer when you
  complete it. ([#88](https://github.com/perennia-fit/perennia/pull/88))
- Up next no longer fails when one Routine's Cadence can't be read; that
  Routine is skipped. ([#87](https://github.com/perennia-fit/perennia/pull/87))
- Moving across a daylight saving change in Nutrition no longer repeats or
  skips a date. ([#87](https://github.com/perennia-fit/perennia/pull/87))
- With large text on a narrow phone, the Today app bar and the Workout header
  no longer cut off their content, and the Workout's **Finish Workout**,
  **Resume Workout** and **Notes** buttons meet AA contrast in the light theme.
  ([#97](https://github.com/perennia-fit/perennia/pull/97))

## [0.1.0] - 2026-11-01

A minor release: new features in the add-food picker, a reworked way to start
planned workouts, Protocols on Today, and a new agent read.

### Added

- **One food search.** The add-food picker searches Your foods, USDA and Open
  Food Facts together, with a source badge on every row and optional source
  chips. Before you type, it lists your own Foods, most logged in the last 90
  days first, each with the Portion you last used, so a repeat Food takes two
  taps. ([#84](https://github.com/perennia-fit/perennia/pull/84))
- **Food History for agents.** `listAgentFoodHistory`
  (`GET /agent/foods/history`) and the MCP tool `agent_list_food_history` return
  the Foods a user logs, in the same order as the picker.
  ([#84](https://github.com/perennia-fit/perennia/pull/84))
- **Protocols on Today.** Protocols have a place on Today, and the Supplements
  domain is now called Protocols throughout the app.
  ([#80](https://github.com/perennia-fit/perennia/pull/80))
- **Plan notes during a workout.** A Workout started from a Template shows that
  Template's notes, read-only and collapsible.
  ([#78](https://github.com/perennia-fit/perennia/pull/78))

### Changed

- **Starting a planned workout** goes through one path from Today instead of
  five overlapping sheets, and the copy says "workout" instead of "Workout
  Template". ([#79](https://github.com/perennia-fit/perennia/pull/79))
- **Open Food Facts search** is part of the one picker search; the separate
  Recent and Open Food Facts views are gone.
  ([#84](https://github.com/perennia-fit/perennia/pull/84))

### Fixed

- Starting a Template with no exercises now says so and asks before starting
  an empty workout, instead of opening one silently.
  ([#78](https://github.com/perennia-fit/perennia/pull/78))

## [0.0.1] - 2026-10-29

The first tagged release: an early build for installing by hand on Android, cut
before any store listing. It describes what the app and server do at this tag
rather than reconstructing history from before it.

### Added

- The offline-first logger for Android and iOS, fully usable with no account:
  Workouts, Training Days, set entry for any mix of load, reps, duration, and
  distance, personal records, history, graphs, and the calendar.
- Nutrition, Supplements and Protocols, and Body Tracker logging alongside
  Training.
- Workout Templates and Routines, with materialize and capture.
- Portable archive export and merge-only import.
- Optional account sign-in (email, Google, Apple) with silent last-writer-wins
  sync to a Perennia server.
- The server: REST API, sync, and the agent surface (REST under `/agent` and an
  MCP server at `/mcp`), published as a Docker image.
- `/healthz` reports the release version the server was built from.
