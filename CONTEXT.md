# Perennia — Ubiquitous Language

Glossary of canonical terms. Definitions only — no implementation details.

## Local-only Mode
Operating state in which the user has no account. All data lives exclusively on the
device and nothing is transmitted anywhere.

## Synced Mode
Operating state after sign-in. The user's training data is replicated between their
device(s) and a service — the Official Service or a Self-Hosted Deployment — and
that service holds the authoritative copy.

## Sync Run
One serialized attempt by a device replica to push all pending authored changes and
pull and apply remote changes until both sides are caught up. Every automatic and
manual sync trigger requests a Sync Run from the same owner.

## Official Service
The hosted deployment operated by the product's maintainers: identity, sync, and the
managed conveniences (managed integrations, licensed reference libraries, the managed
agent). The store-distributed app connects to it by default.

## Self-Hosted Deployment
A user-operated instance of the open-source server. Fully capable for core tracking
and agent access; the app connects to it by explicit user choice, and no data flows
from it to the maintainers.

## Agent
A third-party AI acting on behalf of a user with the user's authorization — e.g.
logging a workout the user dictated to an assistant. Agents interact with the service,
never with a device directly.

## Integration
A connection to an external fitness platform (e.g. a tracker vendor) that imports or
exports training data on the user's behalf. Integrations interact with the service,
never with a device directly.

## Import Adapter
A user-mediated path that brings the user's own external data into Perennia at the edge —
file import, an on-device health hub, or a self-hosted fetcher — writing through the
normal local user path, like manual entry or backup restore. Distinct from an
Integration: it runs as user-operated tooling on the user's own device or server with
their own credentials, not as a service-side connection.

## Exercise Type
The measurement template of an exercise: the set of Dimensions its entry form asks
for. Any combination is valid, including none at all (completion-only). A template
for future input only; never a constraint on already-recorded history. Distinct from
Category.

## Dimension
One kind of measurable value a set can record — load, reps, duration, distance.
Drawn from a small curated registry; users combine dimensions freely but do not
invent new ones.

## Load Mode
Per-exercise meaning of the load value: *added* (extra weight on top of the body or
bar) or *assisted* (help that reduces effective load). Frozen per exercise; with
assisted load, less is progress.

## Record Profile
Per-exercise choice of which metric is the headline record and which direction is
better. Defaulted from the Exercise Type's dimensions; user-overridable. Selects the
headline only — all applicable records are always tracked.

## Annotation
An optional per-set qualifier describing how the set was performed (comment, side,
RPE). Never defines the exercise's type, never required, never the headline record.
Boundary rule: if it changes what records mean it is a Dimension, not an Annotation.

## Interval
A single work bout within interval training. An Interval is recorded as an ordinary
Set — "20 intervals" means 20 sets. Never expressed through the reps dimension.

## Round
One pass through all stations (exercises) of a circuit/superset group. Never
expressed through the reps dimension.

## Category
A grouping label for exercises (typically a muscle group, or a modality family such as
Running or Cycling for cardio). Freely changeable; has no effect on recorded history.
Distinct from Exercise Type.

## Equipment
A structured, optional descriptor of the tool or apparatus normally used for an
Exercise, such as Barbell, Dumbbell, Bench, or Bodyweight. Equipment helps filtering
and defaults, but never constrains logged history. Perennia ships a curated registry for
common values and may preserve imported unknown ids as labels when needed; users can
still log any Exercise without Equipment.

## Platform Library
The curated catalog of exercises provided by the platform. Read-only to users.

## User Library
A user's own created or customized exercises. Owned and editable by the user.

## Shadowing
When a User Library exercise bears the same name as a Platform Library exercise, the
user's version takes precedence and the platform one is hidden for that user. Always
visibly indicated and reversible.

## Active / Archived
Lifecycle states of exercises and categories. Archived items are hidden from pickers
and lists but their recorded history remains. "Active" means simply "not archived" —
it is unrelated to routine membership.

## Workout
A single training *session* with a start instant and optional end. A user (or an Agent
or Integration on their behalf) may have several Workouts in one day.

## Workout Exercise
One ordered occurrence of an Exercise within a Workout. It carries session-specific
placement and notes, and may belong to an Exercise Group. Distinct from both the
reusable Exercise catalogue entry and the Sets performed for it.

## Exercise Group
A named, ordered grouping of Workout Exercises within one Workout, used for
supersets, circuits, and other grouped execution. The group describes structure;
performed work remains ordinary Sets.

## Exercise Group Member
The ordered association placing one Workout Exercise in an Exercise Group. It is
membership and position only, never a Set or a copy of an Exercise.

## Training Day
The grouping of all Workouts sharing the same local date, as experienced by the user
where they trained. A presentation concept — the Home Screen and Calendar show
Training Days; data always belongs to a Workout.

## Open Session
The Workout of the current Training Day that has not been ended. New exercises and
sets default into the Open Session.

## Workout Template
A named, reusable plan for one Workout: the exercises, their order and groupings,
and their prescribed sets for a single session, plus standing notes — on the
template as a whole and on each exercise entry — for hints such as equipment
choice, substitutions, or cues. Plan notes are guidance, distinct from a performed
Workout's own comments; neither is ever copied into the other. First-class and
freestanding — a Workout Template may be referenced by any number of Routines, or
by none.
Referencing is never copying: an edit to a template is seen everywhere it is
referenced; divergence is expressed by duplicating. A mutable plan; performing it
produces an ordinary Workout, and editing or archiving a template never alters
logged Workouts or Sets.

## Prescription
One planned set-block within a Workout Template's exercise entry: the intended
values — fixed, or copy-previous (whatever the last session was) — with a repeat
count and optional planned rest. "5 × (5 @ 100 kg, rest 180 s)" is one
Prescription. A template for intended work only; the performed record is always
ordinary Sets. (Retires the working name "predefined set".)

## Routine
A named, ordered collection of Workout Template references, optionally carrying a
Cadence. With a Cadence it is a recurring plan; without one it is simply a
collection the user fetches workouts from. A mutable plan; editing a Routine never
alters logged Workouts or Sets.

## Cadence
The optional rhythm of a Routine: the assignment of its Workout Templates onto day
slots, either weekly (weekday slots) or rotating (positions in an N-day window). A
slot may hold several templates (a multi-session day) or none (a rest day). The
empty slot is the statement — there is no rest-day entity and nothing is logged for
one. A weekly Cadence is bound to the calendar; a rotating Cadence is bound to
progress — its current position follows from the latest Workout the user
materialized from the Routine, derived on demand and never stored, so the rotation
waits when the user skips days.

## Template Link
The association recording that a Workout was materialized from a Workout Template —
and, when it was loaded through a Routine's Cadence, which Routine and slot it
fulfilled. It connects fact to plan without merging their data: a plain reference,
never a snapshot, surviving template renames and archives. A Workout has at most
one Template Link (materializing a template always begins a new Workout); a
manually assembled Workout has none. Provenance only, never adherence —
planned-versus-performed comparison is derived through the link, never recorded on
it.

## Materialize
To create a Workout from a Workout Template: Prescriptions expand (repeat
unrolled, copy-previous resolved from the exercise's history), a Template Link is
recorded, and the resulting Workout is ordinary fact the user edits freely.
Materializing always begins a new Workout. Code and API say materialize; UI copy
may say "Start."

## External Activity
An activity captured by an external tracker (e.g. a run recorded on a watch) and
imported into Perennia. An immutable, provenance-stamped record of what the tracker
observed — the authoritative source copy — never edited in Perennia. It may back a Workout
through an Activity Link so the activity appears in the user's Training Day, without
its data being merged into that Workout.

## Metric
A measurable signal about the user's body or physiology, tracked over time — body
composition (weight, body fat), heart rate, sleep, HRV, calories, and the like. The
umbrella over what the Body Tracker historically held and what trackers now supply
automatically: a single domain whose readings differ only by provenance (tracked,
manual, or agent). Distinct from training data (a Set): a Metric is the body's state
or response, never what the user prescribed or logged. Automation is the default
source; manual entry is the fallback for metrics no tracker captures or when no
Integration is connected. Logged nutrition intake (a Food Entry) is *not* a
Metric — it is authored data, like a Set; nutrition totals such as energy or
protein consumed are derived analytics, never Metric Readings. A logged Dose (the
Protocols domain) is likewise authored, not a Metric; a protocol's Effect is derived.

## Monitoring Data
The subset of Metrics captured automatically from an external tracker — heart rate,
calories, GPS track, cadence, power, and the like, often as dense time series.
Immutable and provenance-stamped; never conflated with a Set's Dimensions.

## Activity Link
The association recording that a Workout and an External Activity describe the same
session. It connects the two without merging their data, enabling combined analysis —
for example, Monitoring Data shown alongside the Workout's logged Sets.

## Nutrient
One of a curated set of measurable nutrition values a Food carries — energy,
protein, carbohydrate, fat, fibre, sodium, vitamins, minerals, and the like. Drawn
from a fixed registry; users do not invent nutrients. The food-domain analog of a
Dimension. A nutrient value may be *unknown* (not reported by its source), which is
distinct from zero.

## Food
A single catalogued food item, carrying its nutrition facts per 100 g/ml, an
optional serving and package size, and whether it is liquid. It is the input
template for logging — never a constraint on already-logged history. Either
externally-sourced read-only reference data or a User Food (see Food Source).

## Food Source
The origin of a Food's reference data, drawn from a curated registry — USDA, Open
Food Facts, and User (created in-app) at first, extended as further sources land (a
commercial provider, or an imported source such as another app's export); an
unrecognized import records a generic *Imported* origin, preserving the specific
provider. Externally-sourced Foods are read-only; a User Food is editable; customizing
a read-only Food forks a copy into the user's own User Food. Distinct from Provenance,
which records who performed a log action, not where the food data came from.

## User Food
A user's own created or customized Food, owned and editable by the user. The
food-domain analog of the User Library.

## Recipe
A User Food composed of other Foods in given Portions, with a serving count; its
nutrition is derived from its ingredients. Logged like any Food — a Food Entry
snapshots its resolved nutrition facts at log time.

## Portion
A quantity of a Food as entered when logging — a value plus a unit drawn from a
small curated set (grams, millilitres, ounces, fluid ounces, serving, package).
Household measures (a tablespoon, a slice, a medium banana) are expressed as a
Food's defined serving, not as separate units. Stored as entered; the equivalent
mass and the resulting nutrients are derived, never stored.

## Meal
A single eating occasion with a start instant and optional end — the
nutrition-domain analog of a Workout. Several Meals, including more than one of the
same Meal Type, may occur in one day.

## Meal Type
A user-configurable label classifying a Meal (Breakfast, Lunch, Dinner, Snack, or
the user's own such as Pre-workout), with a display order. A grouping and
presentation concept; freely changeable, with no effect on logged history.

## Nutrition Day
The grouping of all Meals sharing the same local date — a presentation concept,
mirroring Training Day. Data always belongs to a Meal, never to the day.

## Food Entry
A single logged item within a Meal — the nutrition-domain analog of a Set. It
records what was consumed self-describingly: either a reference to a Food together
with a Portion, capturing a snapshot of the Food's nutrition facts as they were at
log time, or a Quick Entry. Editing or removing the catalogue Food never alters an
existing Food Entry.

## Quick Entry
A Food Entry that records a name and nutrient values directly, without referencing
a Food or a Portion — the low-friction path for when only the totals are known.

## Compound
An item a user takes and tracks — a supplement, vitamin, hormone, peptide, medication,
or the like. A user-owned catalogue entry carrying a name and a default unit and route,
and an optional strength or concentration. The app ships only a few over-the-counter
examples and never categorizes a Compound by what it is. The "what" of the Protocols
domain — the analog of an Exercise or Food.

## Dose
A single recorded administration of a Compound — an amount and unit, a route, and a
time, with the **timezone captured so its local date is frozen** (as a Workout does) —
recorded self-describingly as a snapshot of the Compound at log time. The authored event
of the Protocols domain — the analog of a Set or Food Entry; authored intake, never a
Metric. A standalone timestamped event, optionally tagged to a Protocol, grouped into
Protocol Days.

## Protocol
A named, time-bounded course of one or more Compounds, each with an optional Schedule — a
regimen the user follows (a supplement stack, a hormone course, a self-experiment). The
plan of the Protocols domain — the analog of a Routine. A mutable template; editing it
never alters logged Doses.

## Schedule
The planned dose, frequency, and route for a Compound within a Protocol. A template for
intended dosing only; the actual record is the logged Doses.

## Protocol Day
The grouping of all Doses sharing the same local date — a presentation concept, mirroring
Training Day and Nutrition Day. Each Dose's local date is frozen at log time (via its
captured timezone), so travel or a device-timezone change never regroups past doses. Data
always belongs to a Dose, never to the day.

## Effect
The relationship between a Protocol or Compound and the user's outcomes over time — a
derived analysis joining the dose timeline against Metrics and performance (deltas,
dose-response, overlays). Computed on demand, never stored; descriptive, never a causal
or medical claim.

## Activity Log
The append-only history of every change made to a user's data, by any actor (the
user, an Agent, sync). Each entry records who, what, and the before/after values.

## Batch
All changes produced by one request or action, grouped as a single Activity Log
entry and undoable as a unit.

## Sync Nudge
A best-effort signal from the service telling a user's device that new data is
available and it should refresh soon. Never required for correctness.
