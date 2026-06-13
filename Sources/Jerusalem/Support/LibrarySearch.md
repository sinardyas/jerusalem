# `LibrarySearch.swift`

> A tiny pure-function namespace that decides whether a search query matches a piece of text — token-by-token, case-insensitive, order-independent.

**Location:** `Sources/Jerusalem/Support/LibrarySearch.swift`
**Role:** pure-logic namespace

## What it does (plain English)

This is the matching rule behind the library's search box. It's a caseless `enum` — a namespace of pure static functions, like `export const LibrarySearch = { matches() {...} }` in JS. There's no UI and no database here on purpose: the rule is plain enough to unit-test directly, and the views just call into it.

The rule is "all tokens must appear, anywhere, any order." It splits the query on whitespace into tokens, then checks that *every* token appears somewhere in the text (case-insensitively). So `"amazing grace"` matches "Amazing Grace" and also "Grace, How Amazing" — order doesn't matter. An empty query matches everything (an empty search shows the whole library), and a one-word query is just a plain substring search.

## Swift you'll meet in this file

| Swift | JS/TS meaning |
| --- | --- |
| `enum LibrarySearch { static func ... }` | A **caseless enum** as a namespace of static functions — no instances ≈ `export const LibrarySearch = { ... }` |
| `query.split(whereSeparator: \.isWhitespace)` | `query.split(/\s+/)`; `\.isWhitespace` is a **key path** used as the "is separator?" predicate |
| `guard !tokens.isEmpty else { return true }` | Early return: if no tokens, match everything (`if (tokens.length === 0) return true`) |
| `tokens.allSatisfy { ... }` | `tokens.every(token => ...)` — true only if the callback holds for all |
| `text.localizedCaseInsensitiveContains($0)` | Case-insensitive, locale-aware `text.includes(token)`; `$0` is the closure's implicit first arg |

## Code walkthrough

The whole rule is one function:

```swift
static func matches(query: String, in text: String) -> Bool {
    let tokens = query.split(whereSeparator: \.isWhitespace)
    guard !tokens.isEmpty else { return true }
    return tokens.allSatisfy { text.localizedCaseInsensitiveContains($0) }
}
```

**TypeScript equivalent**

```ts
// analogy: a namespace object of pure functions.
export const LibrarySearch = {
  matches(query: string, text: string): boolean {
    const tokens = query.split(/\s+/).filter(Boolean); // split on whitespace
    if (tokens.length === 0) return true;              // empty query => match all
    const haystack = text.toLocaleLowerCase();
    return tokens.every(t => haystack.includes(t.toLocaleLowerCase()));
  },
};
```

Line by line:

- `query.split(whereSeparator: \.isWhitespace)` breaks the query into words, dropping the whitespace. `\.isWhitespace` is a *key path* — a compact reference to the `isWhitespace` property of each character, used here as the "is this a separator?" test.
- `guard !tokens.isEmpty else { return true }` short-circuits: a blank or whitespace-only query produces zero tokens, and the convention is that an empty search matches everything.
- `tokens.allSatisfy { text.localizedCaseInsensitiveContains($0) }` returns true only when *every* token is found in the text. `localizedCaseInsensitiveContains` ignores case and respects the user's locale (so accented characters compare sensibly). `$0` is shorthand for the closure's single argument (the current token).

**Swift syntax:**
- `enum LibrarySearch { static func ... }` — a **caseless `enum`** used purely as a namespace (no instances). `static func` = a function on the type itself, called `LibrarySearch.matches(...)`. The idiomatic TS analog is a plain object of functions.
- `\.isWhitespace` — a **key path**: a first-class reference to a property, here `Character.isWhitespace`, passed where a `(Character) -> Bool` predicate is expected. Roughly `c => c.isWhitespace` written compactly.
- `tokens.allSatisfy { ... }` — `.allSatisfy` is `Array.every`. The `{ ... }` is a **trailing closure** (the callback written after the call); `$0` is its implicit first parameter, so `{ text...contains($0) }` ≈ `t => text.includes(t)`.
- `guard ... else { return true }` — early-exit guard; the `else` block must leave the scope.

There's also a thin convenience overload that just flips the argument order for readability at call sites:

```swift
static func matches(title: String, query: String) -> Bool {
    matches(query: query, in: title)
}
```

**TypeScript equivalent**

```ts
// overload with flipped argument order for readability at call sites
matches_title(title: string, query: string): boolean {
  return LibrarySearch.matches(query, title);
}
```

**Swift syntax:**
- Two functions can share the name `matches` but differ by **argument labels** (`query:in:` vs `title:query:`) — Swift treats them as distinct overloads. There's no implicit `return` keyword here because a single-expression function body returns that expression automatically.

## How it connects

- **Called by** the library/search views to filter items. The views stay thin shells; this enum holds the decidable rule, matching the project convention.
- **Unit-tested** independently — because it has no UI or model dependencies, tests can assert the matching behavior directly (this is the whole reason it's a pure namespace).
- **No dependencies** beyond `Foundation`.

## Gotchas / why it matters

- **All tokens must match (AND, not OR).** Multi-word queries narrow results; they don't broaden them. `"grace john"` requires both words present.
- **Empty query = match all.** Important for the "no search text shows everything" behavior — don't change this without checking the list views.
- **Order-independent, case-insensitive, locale-aware.** This is friendlier than a naive `==` or prefix match, and it's why the logic is extracted and tested rather than inlined into a view.
