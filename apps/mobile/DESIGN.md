---
version: alpha
name: OpenWorkoutLogger
colors:
  primary: "#1FB6CC"
  on-primary: "#06262B"
  save: "#2FAE8F"
  on-save: "#06262B"
  destructive: "#C9333A"
  on-destructive: "#FFFFFF"
  record: "#E2B53E"
  on-record: "#06262B"
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
    textColor: "{colors.on-save}"
    typography: "{typography.label}"
    rounded: "{rounded.md}"
    height: "{spacing.row-height}"
  button-destructive:
    backgroundColor: "{colors.destructive}"
    textColor: "{colors.on-destructive}"
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

# Design System: OpenWorkoutLogger

This file follows the Stitch design-md shape. The YAML front matter is normative;
the prose explains intent.

OpenWorkoutLogger is a dense, utilitarian logbook for the gym floor. Dark theme is
the design anchor, light theme is a first-class mirror, and the app should spend
space on readable numerals and large touch targets rather than decoration.

Use the tokens above for all colors, text styles, radii, and spacing. Flutter code
maps these tokens through `ThemeData`, `AppColors`, `AppTextStyles`, and `AppDimens`;
widgets should consume those APIs instead of hardcoding values.

The primary accent is Signal Cyan. Save and confirm actions use Rested Teal with
dark ink, destructive actions use Bar Red with white ink, and personal-record
markers use Trophy Gold with dark ink whenever text sits on the marker. Category
colors are always paired with text or another non-color signal.
