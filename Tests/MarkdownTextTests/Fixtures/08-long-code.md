A long line must scroll sideways, never wrap mid-token:

```ts
export async function prepareMarkdown(source: string, { measure, tags }: PrepareOptions = {}): Promise<PreparedMarkdown> { return walk(fromMarkdown(source, { extensions: [...SYNTAX.extensions] })) }
```

A diff, colored by its lines:

```diff
@@ -12,7 +12,7 @@ let package = Package(
-        .package(url: "https://github.com/raspu/Highlightr", from: "2.3.0")
+        .package(url: "https://github.com/raspu/Highlightr", from: "2.3.0"),
+        .package(url: "https://github.com/swiftlang/swift-cmark", exact: "0.9.0"),
```

JSON, and a fence in a language the grammars do not know:

```json
{ "identity": "swift-cmark", "kind": "remoteSourceControl", "state": { "revision": "5d9bdaa4228b381639fff09403e39a04926e2dbe", "version": "0.9.0" } }
```

```nonsense-lang
this stays character-exact whatever the grammar thinks
```

    an indented block, no language at all
