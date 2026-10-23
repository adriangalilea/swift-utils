#!/usr/bin/env bash
# A real repository in every state GitKit reads, built from public sources only
# (this package's own history and swift-cmark as a submodule), so its captures can
# ship as fixtures: an agent session since a base commit (two commits, staged and
# unstaged edits, a rename, a deletion, a mode change, a binary file, a new file with
# no final newline, untracked files, a submodule bump), a person's edit outside it,
# a second worktree, and a merge left in conflict.
#
#   scripts/gitkit-scenario.sh [folder]   (default /tmp/gitkit-scenario)
#
# Then `swift run gitkit-capture <folder>/app <out> --agent-base <base>` (the
# script prints the exact line).
set -euo pipefail

root="${1:-/tmp/gitkit-scenario}"
case "$root" in /tmp/*|"${TMPDIR:-/nonexistent}"*) ;; *) echo "gitkit-scenario: only under /tmp" >&2; exit 1 ;; esac
here="$(cd "$(dirname "$0")/.." && pwd)"
cmark="$here/.build/checkouts/swift-cmark"
[ -d "$cmark/.git" ] || { echo "gitkit-scenario: run swift build first (needs $cmark)" >&2; exit 1; }
# Main as the branch was cut, so the scenario is the same whenever it is rebuilt.
start=b3922ae

if [ -e "$root" ]; then
  if command -v trash >/dev/null; then trash "$root"; else rm -rf "$root"; fi
fi
mkdir -p "$root"

export GIT_AUTHOR_NAME="Agent" GIT_AUTHOR_EMAIL="agent@example.com"
export GIT_COMMITTER_NAME="Agent" GIT_COMMITTER_EMAIL="agent@example.com"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
at() { export GIT_AUTHOR_DATE="$1" GIT_COMMITTER_DATE="$1"; }

git clone --quiet "$cmark" "$root/cmark"
git clone --quiet --no-checkout "$here" "$root/app"
cd "$root/app"
git checkout --quiet -B main "$start"
git branch --quiet -u origin/main
git remote set-url origin https://github.com/adriangalilea/swift-utils

# Before the agent: the submodule arrives at an older commit.
at "2026-10-20T09:00:00+02:00"
git -c protocol.file.allow=always submodule --quiet add "$root/cmark" Vendor/cmark
git -C Vendor/cmark checkout --quiet 924936d0
git add Vendor/cmark .gitmodules
git commit --quiet -m "build: vendor cmark as a submodule"
base=$(git rev-parse HEAD)

# The agent's first commit: a default changes and its docs follow.
at "2026-10-23T10:12:00+02:00"
perl -0pi -e 's/public init\(_ text: String, tail: Tail = 4\)/public init(_ text: String, tail: Tail = 6)/; s/a count of characters \(`tail: 6` for a hash\)/a count of characters (`tail: 6`, the default: a short hash)/' Sources/Ink/MiddleTruncate.swift
perl -0pi -e 's/static let ceiling = 32 \* 1024/static let ceiling = 48 * 1024/' Sources/Syntax/Syntax.swift
git commit --quiet -am "feat(ink): a middle cut keeps six characters by default"

# Its second: a rename with an edit, a deletion, a mode change.
at "2026-10-23T10:31:00+02:00"
git mv Sources/Ink/Scrim.swift Sources/Ink/InkScrim.swift
perl -0pi -e 's/\/\/\/ Fade this view.s rendered content at its vertical scroll edges\./\/\/\/ Fade this view\x27s content at its vertical scroll edges, `top` and `bottom` points deep./' Sources/Ink/InkScrim.swift
git rm --quiet Sources/Ink/HUDGlass.swift
chmod +x scripts/grant-example-app.sh
git commit --quiet -am "refactor(ink): the scrim is named for its module; the HUD glass goes"

# Uncommitted, staged: a new file and README's first edit.
cat > Sources/Ink/InkBadge.swift <<'SWIFT'
import SwiftUI

/// A count on a quiet capsule: how many things wait behind a row.
public struct InkBadge: View {
    let count: Int

    public init(_ count: Int) { self.count = count }

    public var body: some View {
        Text(verbatim: "\(count)")
            .font(.caption2.weight(.semibold).monospacedDigit())
            .padding(.horizontal, .inkTight)
            .frame(minWidth: 18, minHeight: 18)
            .background(.inkRaised, in: Capsule())
    }
}
SWIFT
perl -0pi -e 's/Swift utilities for mac apps\./Swift utilities for Mac and iPhone apps./' README.md
printf '\x89PNG\r\n\x1a\n\0\0\0\rIHDR\0\0\0\x10\0\0\0\x10\x08\x06\0\0\0\x1f\xf3\xffa' > Sources/Ink/Resources/badge.png
git add Sources/Ink/InkBadge.swift README.md Sources/Ink/Resources/badge.png

# Uncommitted, not staged: README again, Syntax, a file that ends without a newline.
perl -0pi -e 's/one repo, multiple products, each module links only if imported\./one repo, many products, each module linked only when imported./' README.md
perl -0pi -e 's/    public static func highlight\(_ text: String, as format: CodeFormat, on appearance: Appearance\)\n        -> AttributedString\n    \{/    public static func highlight(_ text: String, as format: CodeFormat, on appearance: Appearance)\n        -> AttributedString\n    {\n        \/\/ Nothing to color: skip the engine and the cache.\n        if text.isEmpty { return AttributedString() }/' Sources/Syntax/Syntax.swift
printf 'swift-utils\n\nThe sibling of ts-utils, py-utils and go-utils.' > Sources/Ink/Resources/ABOUT.txt
git -C Vendor/cmark checkout --quiet 5698f9ff

# Untracked: the agent's notes and a new test.
printf '# Badge\n\n- count on a capsule\n- caption2, monospaced digits\n' > NOTES.md
mkdir -p Tests/InkTests
cat > Tests/InkTests/InkBadgeTests.swift <<'SWIFT'
import Testing

@testable import Ink

struct InkBadgeTests {
    @Test func holdsItsCount() {
        #expect(InkBadge(3).count == 3)
    }
}
SWIFT

# A person's edit, outside the agent's work.
perl -0pi -e 's/# TODO/# TODO (Adrian)/' TODO.md

# A second worktree on a branch of its own.
git worktree add --quiet -b review "$root/app-review" HEAD~1

# A merge left in conflict, in a clone of its own.
git clone --quiet "$root/app" "$root/conflict"
cd "$root/conflict"
at "2026-10-23T11:00:00+02:00"
git checkout --quiet -b left
perl -0pi -e 's/Swift utilities for mac apps\./Swift utilities for every Apple platform./' README.md
git commit --quiet -am "docs: every platform"
git checkout --quiet main
perl -0pi -e 's/Swift utilities for mac apps\./Swift utilities, the studio kit./' README.md
git commit --quiet -am "docs: the studio kit"
git merge --quiet left >/dev/null 2>&1 || true

echo "base $base"
echo "swift run gitkit-capture $root/app <out> --agent-base $base \\"
echo "  --touched Sources/Ink/MiddleTruncate.swift,Sources/Syntax/Syntax.swift,Sources/Ink/InkScrim.swift,Sources/Ink/Scrim.swift,Sources/Ink/HUDGlass.swift,scripts/grant-example-app.sh,Sources/Ink/InkBadge.swift,README.md,Sources/Ink/Resources/badge.png,Sources/Ink/Resources/ABOUT.txt,Vendor/cmark,NOTES.md,Tests/InkTests/InkBadgeTests.swift"
