# Changelog

Notable changes to Perennia. This is the single user-facing history for the app
and the server together — they share a version.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html). While
the project is pre-1.0, the API is not yet stable and minor versions may break it.

## [Unreleased]

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
