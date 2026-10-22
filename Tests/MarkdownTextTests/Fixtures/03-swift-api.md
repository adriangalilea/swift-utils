**For a Swift dev, `MiddleTruncate`** (in `Ink`):

```swift
import Ink

MiddleTruncate(address, tail: 6)          // 0x71C7656EC7…8976F, last 6 always shown
MiddleTruncate(path, tail: "/")           // /Users/…/greenhouse-tomatoes.jpg
MiddleTruncate(filename, tail: ".")       // quarterly-report-for….pdf
MiddleTruncate(serverName)                // default: last 4 characters
    .font(.caption.monospaced())          // style it like any Text
```

- **What it's for:** use it instead of `Text(x).lineLimit(1)` whenever the end of the string is what tells values apart: addresses, hashes, IDs, paths, numbered names like `server-1` / `server-2`. `.truncationMode(.tail)` loses that end. `.truncationMode(.middle)` cuts at the exact centre, so how much of the end you keep depends on the width.
- **`tail:`** takes either an integer (that many characters at the end are never cut) or a string (everything from the last occurrence of that separator is kept).
- **Layout:** it takes whatever width its parent gives it, like `Text`. When everything fits it's a single plain `Text` with no seam.
- **The tail is a guarantee:** if the container is narrower than the tail, it overflows rather than cut it. Pick a tail that fits your narrowest layout.
- **Splitting yourself:** `MiddleTruncate.split(text, tail:)` gives you the `(head, tail)` pair if you need it, the same split as the web's `splitTail`. See [the README](https://github.com/adriangalilea/swift-utils#ink).
