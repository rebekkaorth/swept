# Security Policy

Swept deletes files, so a bug that makes it remove the wrong thing is a security issue.

## Reporting a vulnerability

Please **don't open a public issue**. Report it privately instead:
[Report a vulnerability](https://github.com/rebekkaorth/Swept/security/advisories/new)
(GitHub ▸ Security ▸ Advisories).

Include, if you can:
- Your macOS version and Swept version (Swept ▸ About Swept).
- What Swept offered to delete or deleted, and the path involved.
- Steps to reproduce.

You'll get an answer within a week. Fixes for dangerous bugs ship as a new release
as soon as possible.

## What counts

- Swept deleting, or offering to delete, anything outside its allowlist
  (see `Swept/Engine/ScanSources.swift`) or inside a reveal-only store
  (Mail, Messages, Photos, Keychains, iCloud Drive, …).
- Swept following a symlink out of an allowed folder.
- Any network access. Swept is meant to make none.

## Supported versions

Only the latest release gets fixes.
