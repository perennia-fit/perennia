# Changelog

Notable changes to Perennia. This is the single user-facing history for the app
and the server together — they share a version.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html). While
the project is pre-1.0, the API is not yet stable and minor versions may break it.

## [Unreleased]

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
