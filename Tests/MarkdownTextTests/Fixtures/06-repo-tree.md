**Consolidation: I agree, and here's the shape I'd give it.**

One private repo, **media-library**, owning the whole definition:

```
media-library/
  docs/       TIME, TAGS, EDITS, and GALLERY's data half: the one set of specs
  schema/     the SQL schema + shared test cases: the one definition of the data
  Sources/    Swift: the store, the in-memory library, its views
              (absorbs the Gallery and PrepareMedia products, and the Annotation types)
  web/        TS: the same store read from TypeScript, the gallery query, and the lab
```

- **Everything else depends on it, and it depends on nothing AI:**
  - **loom** and **lore**: use the Swift side.
  - **swift-senses**: shrinks to the AI readers (faces, text, animals, listen, say). They write claims through the store and follow its schema; they never define it.
  - **ui**: keeps only generic visual components (gallery grid, rail, tag chip, timeline) that take plain data and know nothing about the store.
- **"At worst two places"** is then exactly media-library (everything about media data) plus ui (the reusable look).

One thing to know: this moves the lab and the specs out of swift-senses, which its agent is working in, so I'd tell it first and move them in one step.
