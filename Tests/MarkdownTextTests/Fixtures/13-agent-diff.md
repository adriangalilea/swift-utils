Done. The middle cut now keeps six characters by default, and its docs say why:

```diff
diff --git a/Sources/Ink/MiddleTruncate.swift b/Sources/Ink/MiddleTruncate.swift
index f1da1a5..f49e861 100644
--- a/Sources/Ink/MiddleTruncate.swift
+++ b/Sources/Ink/MiddleTruncate.swift
@@ -6,7 +6,7 @@ import SwiftUI
 /// `.truncationMode(.middle)` cuts at the exact centre, so how much of the end
 /// survives depends on the width.
 ///
-/// `tail` says what stays whole: a count of characters (`tail: 6` for a hash), or a
+/// `tail` says what stays whole: a count of characters (`tail: 6`, the default: a short hash), or a
 /// separator, everything from its last occurrence (`tail: "/"` keeps a path's file,
 /// `"."` an extension). A separator the text does not hold guarantees no tail: the
 /// text cuts at its end. The tail is a promise: wider than the room, it overflows.
@@ -32,7 +32,7 @@ public struct MiddleTruncate: View {
     let text: String
     let tail: Tail
 
-    public init(_ text: String, tail: Tail = 4) {
+    public init(_ text: String, tail: Tail = 6) {
         self.text = text
         self.tail = tail
     }
```

A fragment without headers reads too:

```diff
-let tail: Tail = 4
+let tail: Tail = 6
```

`swift test` passes.
