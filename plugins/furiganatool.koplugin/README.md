# Furigana Toggle — KOReader prototype

This prototype implements the agreed per-book control model:

- **Visible** — publisher/KOReader ruby rendering is untouched.
- **Off** — `<rt>` / `<rp>` annotations are removed from layout with CSS, so ruby space is not reserved.
- **Toggle** — ruby annotation space is reserved but readings start hidden. Individual readings are intended to toggle on a single tap and remain in their current state until leaving that page.

## What is implemented now

- KOReader plugin structure.
- Per-book mode persisted via `ui.doc_settings`.
- Three radio controls: Visible / Off / Toggle.
- CSS injection without overwriting the user's existing book-specific style tweak.
- Page-local transient `revealed` state container.
- A full-screen single-tap hook that returns `false` unless the ruby backend successfully handles the tap, preserving normal KOReader behavior otherwise.
- Engine-specific behavior isolated in `ruby_backend.lua`.

## What still needs CREngine support

Current KOReader Lua does not expose enough tag-aware DOM information to robustly answer:

1. Which `<ruby>` element is under this exact screen coordinate?
2. Make only that `<rt>` visible/hidden without reflowing the page.

The intended minimal engine API is conceptually:

```cpp
RubyInfo getRubyAtPosition(int x, int y);
bool setRubyVisibilityOverride(string xpointer, bool visible);
void clearRubyVisibilityOverrides();
```

The Lua adapter is already shaped around those operations.

## First test before touching C++

Test the CSS modes on a Japanese EPUB containing standard `<ruby><rt>` markup.

1. **Visible** should look exactly like stock KOReader.
2. **Off** should remove readings *and* reclaim annotation spacing.
3. **Toggle** should hide readings while preserving ruby spacing.

If CREngine does not preserve layout for `visibility:hidden`, the correct implementation is to keep ruby layout normal and suppress `<rt>` painting in CREngine Toggle mode instead of trying more CSS hacks.

## Tap priority

The plugin asks to run before ordinary forward/backward page-turn tap zones, but it returns `false` unless `RubyBackend:toggleAtScreenPosition()` actually toggles a ruby. This is intentional: taps on non-ruby text should fall through to KOReader.

Before final integration, link/highlight/menu priority should be tested against KOReader's existing `ReaderHighlight` touch-zone ordering.
