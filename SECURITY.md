# Security policy

## Reporting a vulnerability

**Please do not open a public issue for a security problem.**

Report it privately through GitHub's
[private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability):
go to the **Security** tab of this repository and choose **Report a vulnerability**. That
opens a private advisory visible only to the maintainers.

Please include enough detail to reproduce the issue — affected component, version or
commit, and the steps involved.

We aim to acknowledge a report within a week. This is a small project, so please be patient
if the first response takes a little longer.

## What is in scope

This repository covers the mobile app, the sync server, the agent API and MCP surface, the
shared contract packages, and the edge sidecars. Vulnerabilities in any of those are in
scope, including:

- authentication and session handling
- cross-tenant data access in sync or the agent API — every read and write must be scoped to
  the authenticated user
- agent API key issuance, scoping, or revocation
- credential handling for integrations
- anything that would expose protocol data, which is treated as the most sensitive tier

Reports against a self-hosted deployment's own infrastructure — your server, your database,
your reverse proxy — are out of scope here, though we would still like to hear about them if
the cause is our code or our deployment documentation.

## Disclosure

We will work with you on a fix and a disclosure timeline. We will credit you in the advisory
unless you would rather stay anonymous.
