---
name: package-playthrough
description: Package a playthrough as evidence for a GitHub issue — miniature SQLite DB and optional name-keyed JSON. Use when filing or debugging playthrough bugs, attaching playthrough dumps, or when asked to dump/export a playthrough.
---

# Package a playthrough for issue debugging

When a playthrough shows a bug, attach a **restoreable miniature primary database** of that story + playthrough — not the whole `development.sqlite3`, and not a row dump that cannot boot.

## Dump (required for issues)

Write under `tmp/` only (default). Never under `doc/evidence/` or any path that would be committed.

```bash
rake 'game:dump_playthrough[PLAYTHROUGH_ID]'
# -> tmp/playthrough-packages/<story>--<protagonist>.sqlite3.gz
```

Produces:

- `*.sqlite3.gz` — gzipped schema + that story's world + that playthrough's progress only
- `*.sqlite3.gz.meta.json` — which playthrough it was taken for

Implementation: `Playthrough::SqlitePackage` (`app/models/playthrough/sqlite_package.rb`).

## Attach to the issue (drag-and-drop — required)

GitHub has no API for issue file attachments. A human must attach the package in the browser:

1. Open the GitHub issue (or PR comment box).
2. Drag-and-drop the `.sqlite3.gz` from `tmp/playthrough-packages/` into the comment (optionally the `.meta.json` too).
3. In the same comment, paste the open instructions:

```bash
gunzip -k path/to/package.sqlite3.gz
DATABASE_URL=sqlite3:path/to/package.sqlite3 \
  bin/rails runner 'p Playthrough.find(ID).current_location.name'
```

Agents: dump the package, print the absolute path, and ask the human to drag-drop it. Do not commit the archive, do not put it under `doc/evidence/`, do not substitute a repo path for the attachment.

## Open a downloaded package

Expand, then point Rails at the sqlite file. Do not merge into an existing DB.

```bash
gunzip -k path/to/package.sqlite3.gz
# or: Playthrough::SqlitePackage.expand!("path/to/package.sqlite3.gz")

DATABASE_URL=sqlite3:path/to/package.sqlite3 \
  bin/rails runner 'p Playthrough.find(ID).current_location.name'
```

## Optional readable companion

Name-keyed JSON (no DB ids) for skimming in an issue without booting Rails. Also stays in `tmp/` — paste excerpts into the issue if useful; do not commit the dump.

```bash
rake 'game:export_playthrough[PLAYTHROUGH_ID]'
# Playthrough::Exporter — tmp/playthrough-exports/ by default
```

## Do not

- Commit playthrough packages (or their JSON companions) into the repo
- Write packages under `doc/evidence/`
- Dump the whole `storage/development.sqlite3` as playthrough evidence
- Build an import-into-existing-database path (out of scope; use `DATABASE_URL`)
- Rely on playthrough integer ids alone in issue write-ups without a package attachment
