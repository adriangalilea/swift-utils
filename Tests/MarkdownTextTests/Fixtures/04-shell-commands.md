`git part` is built, installed the way other `_core` tools are, and committed. Nothing is pushed.

The proof is `pnpm example` in `_core/infra/git-part`. It builds a throwaway repo and runs 14 cases, each checked against what git's index actually holds, and all pass. Typecheck is clean.

**How I use it now:**
```
git part                                   # every changed file, one numbered line per change
git part CHANGELOG.md                      # one file in full, added lines numbered as on disk
git part add CHANGELOG.md -m "### middle-truncate"   # changes holding the text (or /regex/)
git part add registry.json public/r/registry.json -m '"middle-truncate"'   # a file and its generated copy
git part add demo.tsx -l 27-35             # part of one block of added lines
git part reset CHANGELOG.md -m "### data-view"       # unstage part, keep the rest staged
```

**Why it's safe:**
- **No patches at all.** It writes the exact content the index should hold. It reads files through git's own conversion (line endings, LFS), so the numbers and bytes are the index's.
- **All or nothing:** a call either does everything it was asked or writes nothing. It refuses when:
  - a match finds nothing, or a line range holds no added line;
  - a named file would get nothing;
  - only half of a replaced block was picked;
  - the file is binary, a symlink, a submodule, or in a merge conflict.
- **Self-check on every run:** it rebuilds each file from git's changes and stops if the result doesn't match byte for byte.

**What the proof caught:**
- **One real bug, fixed.** `git rm --cached` refuses to drop a partly staged new file. The tool and its printed undo now use the lower-level `git update-index --force-remove`.
- **`git part --help` gets caught by git**, which looks for a man page. `git part help` works, and the skill says so.
