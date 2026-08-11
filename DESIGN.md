---
version: alpha
name: Perennia
colors:
  primary: "#1FB6CC"
  on-primary: "#06262B"
  save: "#2FAE8F"
  destructive: "#E5484D"
  record: "#E2B53E"
  background-dark: "#14181B"
  surface-dark: "#1E2428"
  chrome-dark: "#101316"
  text-primary-dark: "#ECF1F4"
  text-secondary-dark: "#9AA7AE"
  background-light: "#F2F4F5"
  surface-light: "#FFFFFF"
  chrome-light: "#FFFFFF"
  text-primary-light: "#1A2126"
  text-secondary-light: "#5B6770"
  divider-dark: "#2C343A"
  divider-light: "#E3E8EA"
  category-chest: "#E06C5A"
  category-back: "#4A8FE0"
  category-legs: "#5FB05C"
  category-shoulders: "#E0A23F"
  category-arms: "#A06CD5"
  category-core: "#3FBFB0"
  category-cardio: "#E0608F"
  category-other: "#8A969E"
typography:
  numeral-hero:
    fontFamily: Roboto
    fontSize: 34px
    fontWeight: 600
    lineHeight: 1.1
    fontFeature: tnum
  numeral-row:
    fontFamily: Roboto
    fontSize: 18px
    fontWeight: 600
    lineHeight: 1.3
    fontFeature: tnum
  h1:
    fontFamily: Roboto
    fontSize: 22px
    fontWeight: 600
    lineHeight: 1.25
  h2:
    fontFamily: Roboto
    fontSize: 17px
    fontWeight: 600
    lineHeight: 1.3
  body:
    fontFamily: Roboto
    fontSize: 15px
    fontWeight: 400
    lineHeight: 1.45
  label:
    fontFamily: Roboto
    fontSize: 13px
    fontWeight: 500
    lineHeight: 1.3
    letterSpacing: 0.04em
  caption:
    fontFamily: Roboto
    fontSize: 12px
    fontWeight: 400
    lineHeight: 1.35
rounded:
  sm: 4px
  md: 8px
  full: 999px
spacing:
  base: 16px
  dense: 12px
  row-height: 48px
  touch-target: 48px
components:
  button-save:
    backgroundColor: "{colors.save}"
    textColor: "#FFFFFF"
    typography: "{typography.label}"
    rounded: "{rounded.md}"
    height: "{spacing.row-height}"
  button-destructive:
    backgroundColor: "{colors.destructive}"
    textColor: "#FFFFFF"
    typography: "{typography.label}"
    rounded: "{rounded.md}"
    height: "{spacing.row-height}"
  exercise-card:
    backgroundColor: "{colors.surface-dark}"
    rounded: "{rounded.md}"
    padding: "{spacing.base}"
  set-row:
    height: "{spacing.row-height}"
    typography: "{typography.numeral-row}"
  stepper-button:
    rounded: "{rounded.md}"
    size: "{spacing.touch-target}"
---

# Design System: Perennia

This file follows the Stitch design-md specification
(https://stitch.withgoogle.com/docs/design-md/overview/). The YAML front matter is
normative; the prose explains intent. The ergonomics are modeled on FitNotes-style
logging (https://www.fitnotesapp.com/help_overview/) — we keep its density and
low-friction flow, with our own visual identity. Never copy FitNotes assets.

## Overview

Perennia is a tool you use mid-set with chalk on your hands. The atmosphere
is **utilitarian, dense, and data-first**: a quiet dark chrome that recedes, flat
content cards that carry nothing but numbers, and a single cool accent that marks
exactly one thing — the next useful action. Nothing celebrates itself except a
personal record.

The emotional target is *calm competence*: the app should feel like a well-organized
logbook, not a coach, a feed, or a game. Whitespace is spent on touch targets and
numeral legibility, never on decoration. Dark theme is the default and the design
anchor (gyms are visually noisy; the app should not be); the light theme is a
first-class mirror, not an afterthought.

## Colors

One accent, three verdict colors, and a muted stage for them to stand on.

- **Signal Cyan** (`#1FB6CC`) — the primary accent: selected tabs, active set-row
  highlight, date-navigation arrows, links, focused inputs, comment-present icons.
  If two things on one screen are cyan, one of them is wrong.
- **Rested Teal** (`#2FAE8F`) — the Save/confirm action. Distinct from the accent so
  "commit a set" never competes visually with navigation.
- **Bar Red** (`#E5484D`) — destructive actions only (Delete, hard-delete flows).
  Never used for emphasis or warnings.
- **Trophy Gold** (`#E2B53E`) — personal records: the trophy marker on a set row and
  in history. The only celebratory color in the system.
- **Dark stage** — near-black chrome (`#101316`) for app bar and date strip, deep
  charcoal background (`#14181B`), lifted graphite cards (`#1E2428`), off-white
  primary text (`#ECF1F4`), cool gray secondary text (`#9AA7AE`).
- **Light stage** — pale cool gray background (`#F2F4F5`), white cards, near-black
  text (`#1A2126`).
- **Category palette** — eight muted-but-distinct hues (see tokens) used for
  calendar dots, category labels, and superset group edge bars. Categories are
  user-recolorable; these are defaults. Color is never the only signal — a category
  color is always adjacent to its name or another textual cue.

All foreground/background pairs must pass WCAG AA in both themes.

## Typography

System-utilitarian: Roboto on Android, SF Pro on iOS (the tokens say Roboto; map to
the platform equivalent). No display or brand font — the numbers are the brand.

- **Numerals are the hierarchy.** The value being entered (`numeral-hero`, 34px
  semibold) is the largest thing on the Training Screen; set-row values
  (`numeral-row`, 18px semibold) outweigh their unit labels. All numerals use
  tabular figures so columns of sets align.
- Units and field labels (`label`, 13px, slight letter-spacing, uppercase for field
  labels like "WEIGHT (kg)") sit small and secondary next to their values.
- Exercise names are `h2`; screen titles `h1`. Body prose (`body`, 15px) appears
  only on secondary surfaces — settings, notes, dialogs.
- Comfortable line heights, no condensed faces, no thin weights below 400 — arm's
  length readability wins every trade-off.

## Layout

- **Vertical list of cards** is the master pattern: the Home Screen is a scroll of
  exercise cards; each card is a heading plus right-aligned set rows
  (value unit · reps), echoing a paper logbook column.
- **8px grid**: `base` 16px padding inside cards and screen gutters, `dense` 12px
  between rows, 48px (`row-height`) minimum row and touch-target size.
- **Edge-anchored navigation**: root screens use the bottom `Today | Progress | Library`
  bar; Today keeps the app bar and date strip above its `Training | Nutrition` toggle.
  Workout/Training/detail screens hide the root bar; the session drawer still enters
  from the left edge. Primary actions live in the bottom half where the thumb is.
- **Superset group bar**: a 4px category-colored bar flush against the card's
  leading edge spans all member exercises — grouping is shown by alignment and the
  shared bar, not by nesting or borders.
- Density is a feature: prefer one more visible set row over more padding. Empty
  states are a single centered message and one CTA, never an illustration.

## Elevation & Depth

Essentially flat. Hierarchy comes from surface tone, not shadow: chrome darkest,
background dark, cards one step lighter (in light theme: white cards on gray).
Hairline dividers (`divider-*` tokens) separate rows inside a card. Shadows are
reserved for genuinely floating layers — the navigation drawer, dialogs, and menus
get a soft, low-spread shadow; cards on the page get none. No glassmorphism, no
gradients, no parallax.

## Shapes

Subtly rounded and squared-off: `md` (8px) on cards, buttons, and input fields —
enough to feel current, square enough to feel like an instrument. `sm` (4px) for
small chips like the per-set comment marker. `full` (pill) only for filter chips and
the dimension-toggle chips in exercise editing. Calendar day-dots and category
swatches are circles. The one exception is Today's extended **Log** FAB, whose shape is
the platform-standard floating action affordance. Save/Update buttons remain rectangles
with `md` corners, never FABs.

## Components

- **Set entry (Training Screen, Track tab):** per dimension, a label row
  ("WEIGHT (kg)") above a horizontal cluster of [−] stepper, hero numeral field,
  [+] stepper. Steppers are `touch-target`-sized squares using the exercise's
  configured increment. Below the fields sit two equal-width buttons:
  **Save** (`button-save`) and **Clear** (neutral outline). When an existing set is
  selected, the row highlights in translucent Signal Cyan and the buttons become
  **Update** (teal) and **Delete** (`button-destructive`).
- **Set row:** index number · comment icon (gray when empty, Signal Cyan when
  present) · value+unit · reps, on a 48px row; a Trophy Gold marker when the set is
  a personal record; a trailing checkbox when mark-sets-complete is enabled.
- **Exercise card (Home Screen):** `h2` exercise name, hairline divider, then set
  rows; tap anywhere → Training Screen.
- **Root navigation:** three labelled destinations — Today, Progress, Library — with
  selected state in Signal Cyan. Each retains its own view state; the bar is absent from
  logging, editor, and detail routes.
- **Today Log action:** one extended FAB opening a bottom sheet of authored daily writes
  (Workout, Food, Supplement). Body measurements remain contextual to Progress → Body.
- **Tabs (Track | History | Graph):** text tabs in the chrome, active tab in Signal
  Cyan with a 2px underline; inactive tabs secondary-text gray.
- **Navigation drawer:** an opaque surface listing the session's exercises with set
  counts, current exercise highlighted; pinned utility rows at the bottom
  (Add Exercise, Add To Group, Home).
- **Inputs/forms (secondary screens):** filled fields on surface color with a 1px
  divider-color stroke, `md` corners, Signal Cyan focus stroke; no floating labels.
- **Calendar:** month grid, up to four category-colored 6px dots per day, today
  ringed in Signal Cyan.

## Do's and Don'ts

- **Do** keep the logging path instant: no spinners, skeletons, or network waits
  between tapping Save and seeing the set in the list.
- **Do** prefill set fields from the previous session — the empty field is the
  exception, not the rule.
- **Do** use Signal Cyan for exactly one action or state per screen.
- **Don't** use red for anything except destruction, or gold for anything except
  records.
- **Don't** rely on color alone — every category color is paired with text; PR gold
  comes with the trophy glyph.
- **Don't** add illustrations, mascots, streak flames, confetti, or motivational
  copy. A personal record gets a gold trophy; that is the ceiling of celebration.
- **Don't** hardcode hex values, radii, or spacing in widgets — map these tokens
  into the Flutter `ThemeData`/theme extensions and consume them from there.
- **Don't** copy FitNotes' colors, icons, or assets; we inherit its ergonomics, not
  its skin.
