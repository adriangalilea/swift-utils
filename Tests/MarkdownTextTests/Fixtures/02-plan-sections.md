I've started the media library (files only, nothing committed). I've paused the store and tag model on your three answers, and the backup is done and checked. Here is how each open question would work.

## How SQL works per location

A **shard** is a folder holding one SQLite file (`store.db`) plus its caches. Which shard a file belongs to depends only on where the file is:

| Where the file is | Its shard |
|---|---|
| Any folder on the Mac's own disk (`~/Movies`, Downloads…) | the computer's shard, `~/.local/share/library/` |
| An encrypted vault | `<vault>/.library/`, encrypted with the vault |
| An external disk | `<disk>/.library/`, travels with the disk |

- **Opening:** the app opens the computer's shard, plus each vault or disk shard while it's mounted. SQLite can attach several databases to one connection, so one query reads all of them at once.
- **Writing:** a write goes to the shard of the file it's about. Paths inside a vault or disk shard are relative to its root, so a renamed vault still lines up.
- **Locking:** when a vault locks, its shard closes and everything about its files drops out of every answer. Nothing about them is left on the Mac.
- **Duplicates and moves:** a file's id is its content hash. A duplicate is two paths with the same id. A move between shards copies the file's rows into the new shard and then removes them from the old one.

## Where the code goes

I'd split it in three:

1. **A small store module** that opens shards and reads and writes the shared tables, plus the SQL schema.
2. **The library** itself: scanning, the query, the layouts and the views. It uses the store.
3. **Each app:** its own tables and everything else.

## Favorites

Under the tag spec, `favorites` would be a built-in collection, like `pending`:

- Hearting a file is one claim: you, yes, on the whole file.
- It shows in the tag rail with a heart, filters include/exclude like any tag, and its counts work the same.
- A separate flag would be a second mechanism doing what collections already do.

If this reads right, say so and I'll continue with the store. Or tell me what to change.
