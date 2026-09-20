---
name: package-playthrough
description: Package a playthrough as evidence for a GitHub issue — miniature SQLite DB and optional name-keyed JSON. Use when filing or debugging playthrough bugs, attaching playthrough dumps, or when asked to dump/export a playthrough.
---

# Package a playthrough for issue debugging

When a playthrough shows a bug, attach a **restoreable miniature primary database** of that story + playthrough — not the whole `development.sqlite3`, and not a row dump that cannot boot.

## Dump (required for issues)

```bash
rake 'game:dump_playthrough[PLAYTHROUGH_ID]'
# or a path under doc/evidence/:
rake 'game:dump_playthrough[3,doc/evidence/playthrough-3-cold-deck-running/cold-deck-running--kael-veyra.sqlite3]'
```

Produces:

- `*.sqlite3` — schema + that story's world + that playthrough's progress only
- `*.sqlite3.meta.json` — which playthrough it was taken for

Implementation: `Playthrough::SqlitePackage` (`app/models/playthrough/sqlite_package.rb`).

## Open the package

The file **is** a primary database. Point Rails at it; do not merge into an existing DB.

```bash
DATABASE_URL=sqlite3:path/to/package.sqlite3 \
  bin/rails runner 'p Playthrough.find(ID).current_location.name'
```

## Optional readable companion

Name-keyed JSON (no DB ids) for skimming in an issue without booting Rails:

```bash
rake 'game:export_playthrough[PLAYTHROUGH_ID]'
# Playthrough::Exporter — tmp/playthrough-exports/ by default
```

## Attach to the issue

1. Put the `.sqlite3` (+ `.meta.json`) under `doc/evidence/<slug>/` when committing with a PR.
2. Comment on the GitHub issue with the path and the `DATABASE_URL=...` one-liner.
3. Prefer the SQLite package over pasting logs or citing development DB ids.

## Do not

- Dump the whole `storage/development.sqlite3` as playthrough evidence
- Build an import-into-existing-database path (out of scope; use `DATABASE_URL`)
- Rely on playthrough integer ids alone in issue write-ups without a package
