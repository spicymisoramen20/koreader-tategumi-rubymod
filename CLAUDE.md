# KOReader Vertical Text (vertical-rl) Implementation

## Soft Fork Policy

This project is a soft fork of koreader/koreader + koreader/koreader-base +
crengine, maintained as m-tky/koreader-tategumi, m-tky/koreader-base, and
m-tky/crengine. Keep changes small, preserve upstream style, and make rebasing
onto upstream updates easy.

- Keep fixes targeted; avoid unrelated cleanup.
- Remove debug `fprintf(stderr, ...)` and similar instrumentation before commit.
- The `ltext_vert_*` / `lvrend_*` / `s_ruby_*` counters used by specs are
  allowed; do not add new ad-hoc counters.
- Issues and PRs go to the m-tky repos only.
- Write code, comments, commit messages, issues, PRs, and docs in English.
- Do not use screenshot pixel measurements for geometry; confirm via runtime
  logs instead.

## Project Goal

Implement Japanese vertical-rl text rendering in KOReader/crengine.
Target: tategumi (縦書き) for Japanese novels in EPUB format.

## Build & Test

```bash
# Build
nix develop --command ./kodev build -d emulator

# Run emulator
nix develop --command ./kodev run emulator

# Run all unit tests
nix develop --command make -j1 testfront

# Run vertical text tests only
nix develop --command ./kodev test front -f "Vertical text"
```

Test fixture: `spec/front/unit/data/fixtures/vertical_text/simple_ja_noruby.epub`

## Architecture: Y=X Coordinate Swap

The vertical implementation reuses the horizontal pipeline by swapping X and Y
roles. Column progression lives in the Y-axis fields, so page splitting and most
layout code continue to work with minimal fork-only glue.

- `FlowState` tracks vertical column advance in `c_x` / `c_y`.
- `renderBlockElementEnhanced` feeds inline-start margin into `fmt.setX()` and
  block-direction progress into `fmt.setY()`.
- `lvlogical.h` maps CSS physical arrays to logical vertical-rl directions.
- `LFormattedText::Draw` swaps coordinates back at entry, then draws columns
  right-to-left and glyphs top-to-bottom.
- Ruby/inline-box layout uses the inline box's `getY()` as a vertical offset,
  with the ruby group drawn at the accumulated column advance.
- Latin and ruby-depth fixes live in `lvtextfm.cpp`; check the nearby comments
  and the `vertical_ruby_column_spec.lua` regression when changing them.

### Glyph placement in vertical mode (lvfntman.cpp + lvfntman_vert.{h,cpp})

LuaTeX-ja-style vertical typography per JLReq.

- Pre-shape substitution maps punctuation to vertical presentation forms when
  the font supports them. Dashes/leaders stay on `vrt2`.
- Half-em compaction applies to the bracket/comma/period/halfwidth-kana classes.
- JLReq glue/kern values come from the vertical class matrix.
- Final glyph placement combines vmtx/vBY with in-slot Y alignment.
- The class table and matrix live in `lvfntman_vert.{h,cpp}`; the shaping and
  draw hooks live in `lvfntman.cpp`.

#### Character classes (lvfntman_vert.{h,cpp}: `getJLReqVertClass`)

Ten classes mirror jfm-ujisv.lua's class table; verified line-by-line against
`luatexja/src/jfm-ujisv.lua`:

| Class                    | Chars                                          | width  | align  |
|--------------------------|------------------------------------------------|--------|--------|
| `CJK_BODY` [0]           | ideographs, hiragana, katakana, Hangul, ー〜～ | em     | middle |
| `OPEN_BRACKET` [1]       | ‘ “ 〈 《 「 『 【 〔 〖 〘 〝 （ ［ ｛ ｟        | em/2  | right  |
| `CLOSE_BRACKET_COMMA` [2]| ’ ” 〉 》 」 』 】 〕 〗 〙 〟 ） ］ ｝ ｠ 、 ，| em/2  | left   |
| `MIDDLE_DOT` [3]         | ・ ： ； ·                                     | em/2  | middle |
| `PERIOD` [4]             | 。 ．                                          | em/2  | left   |
| `DASH` [5]               | — ― ‥ … 〳 〴 〵                                | em     | left   |
| `EXCLAM_QUEST` [6]       | ？ ！ ‼ ⁇ ⁈ ⁉                                  | em     | left   |
| `HALF_KANA` [7]          | U+FF61..U+FF9F (halfwidth katakana)            | em/2  | left   |
| `VERT_MARK`              | — fork-only, signalled by `LFNT_HINT_VERTICAL_MARK` (ー — ‥ … 〜 ～ ―) | em | middle |
| `OTHER`                  | Latin/numerals/etc.                            | em     | middle |

#### Glue/Kern matrix (lvfntman_vert.cpp `getJLReqGlueKernEighths`)

Per-class-pair JLReq inter-character spacing, in eighths of em.  Major entries:

| prev \ next  | BODY | OPEN | CLOSE | MIDDLE | PERIOD | DASH | EXCL | HKANA |
|--------------|------|------|-------|--------|--------|------|------|-------|
| BODY         | 0    | 4    | 0     | 2      | 0      | 0    | 0    | 0     |
| OPEN         | 0    | 0    | 0     | 2      | 0      | 0    | 0    | 0     |
| CLOSE/、     | 4    | 4    | 0     | 2      | 0      | 4    | 4    | 4     |
| MIDDLE       | 2    | 2    | 2     | 4      | 2      | 2    | 2    | 2     |
| PERIOD       | 4    | 4    | 0     | 6      | 0      | 4    | 4    | 4     |
| DASH         | 0    | 4    | 0     | 2      | 0      | 0    | 0    | 0     |
| EXCL         | 8    | 4    | 0     | 6      | 0      | 0    | 0    | 8     |
| HKANA        | 0    | 4    | 0     | 2      | 0      | 0    | 0    | 0     |

(eighths of em — multiply by em / 8 for px)

#### Upstream interaction fixes

Three upstream-side guards needed for our JFM compaction to take effect:

1. `getFlexibleCJKWidthAdjustment` (lvtextfm.cpp:2798) returns wa8=8 (= no
   reduction) in vertical mode.  Without this, upstream's wa8 multiplier
   would further halve our already-half-em advance to em/4 for line-start
   brackets.
2. `vert_layout_min_x` post-pass (lvtextfm.cpp:3680) skips its
   `eff_w = max(word->width, font_size)` clamp when the word's first char
   is a half-em JFM class.  Without this, layout would round word->width
   back up to em.
3. `vert_min_next_x` Draw tracker (lvtextfm.cpp:7454) has the same skip.
   Without this, the Draw renderer would advance the next char by em
   instead of by word->width.

HarfBuzz TTB writes `x_offset = -vertOriginX`, `y_offset = -vertOriginY` into
`glyph_pos[]` (compensation for an LTR-style pen).  The fork places the pen at the
vertical origin directly and reads vBX/vBY from its own cache, so HarfBuzz's offsets
must NOT be added on top — that would double-displace the glyph.

### Coordinate conversion (lvdocview.cpp, cre.cpp)

`windowToDocPoint` (screen → doc):
```cpp
pt.y = page_y + (page_right - screen_x);   // doc_y = horizontal advance
pt.x = screen_y;                            // doc_x = vertical position
```

`docToWindowPoint` (doc → screen):
```cpp
screen_x = page_right - (doc_y - page_y_val);
screen_y = doc_x;
pt.x = screen_x;
pt.y = doc_x;
```

`docToWindowRect` normalizes left/right after conversion (increasing doc_y → decreasing screen_x).
Off-screen rejection: returns false if `screen_x < page_left - 50 || screen_x > page_right + 50`.

`isVerticalText()` heuristic (lvdocview.cpp):
```cpp
bool LVDocView::isVerticalText() const {
    if (m_pages.length() == 0) return false;
    int page_h = m_pages[0]->height;
    return (page_h > 0 && page_h <= m_dx + 32);
}
```

## Implemented Features

### Frontend (Lua)

| Feature | Location |
|---------|----------|
| Text selection: `onHold` uses Lua sboxes for vertical rolling docs | `readerhighlight.lua` |
| Underline highlight: vertical line on right edge of column | `readerview.lua` |
| Strikeout highlight: vertical line through column center | `readerview.lua` |
| Vertical footer: progress bar fills right→left, TOC ticks mirrored | `readerfooter.lua` |
| Glyph rotation: ー 〜 ― etc. use vertical forms (`+vert`, `+vrt2`, `+vkrn` all enabled, matching LuaTeX-ja `auto_enable_vrt2`) or 90° CW rotation when no +vert form. `+vrt2` lets consecutive dashes/leaders (——, ‥, …) chain into one continuous composite glyph | `lvfntman.cpp` |
| Kinsoku (禁則) + cascading 追い出し (oidashi): 行頭/行末 line-break prohibition with a 35-char 行頭禁則 table (closing brackets, 、。, ー々ヽヾゝゞ〻, small kana, ゛゜) and a wrap-back loop (max 5) for chained 」」 / 「「 | `lvtextfm_vert.cpp` `isVertLineStartProhibitedExt` |
| kanjiskip/xkanjiskip vertical justification: 0.25em inserted at CJK↔non-CJK boundaries; LAYOUT (`word->x`) and Draw (`vert_min_next_x`) trackers kept in lockstep | `lvtextfm_vert.cpp` |
| LuaTeX-ja JFM vertical typography (jfm-ujisv.lua port, m-tky/koreader-tategumi#15): 10-class classifier (Phase 1+2), pre-shape codepoint substitution to U+FE10..FE48 (Phase 5a, dashes excluded for +vrt2), half-em compaction for [1][2][3][4][7] (Phase 3), vmtx + cwa in-slot Y (Phase 4), inter-class glue/kern matrix (Phase 5) | `lvfntman.cpp`, `lvfntman_vert.{h,cpp}`, `lvtextfm.cpp`, `lvtextfm_vert.cpp` |
| Multi-em column-break fix: 2+ char ruby boxes, 2em dash composites, and kana-repeat marks break before the column bottom instead of overflowing/clipping (Draw-position check applies to non-CJK multi-em glyphs, not CJK only) | `lvtextfm_vert.cpp` |
| Ruby-following char highlight alignment: LAYOUT inline-box advance uses same `letter_spacing` value as Draw, so the char after a ruby group no longer drifts ½em below its glyph | `lvtextfm_vert.cpp` |
| Column bottom clipping fix: glyphs at column end no longer clipped | `lvtextfm.cpp` |
| sbox screen_y offset (P5): `windowToDocPoint`/`docToWindowPoint` account for `clip.top` | `lvdocview.cpp` |
| Character overlap fix (上にめり込む): `vert_min_next_x` correctly prevents overlap | `lvtextfm.cpp` |
| Enclosed Alphanumerics (U+2460-24FF / ①②③) classified as CJK so they render upright in their em column via the JFM vertical path. Without this they fell into `word_is_latin_in_vertical` (render+rotate); the rotated buffer is `font_h` wide so the rightmost column overflows by `(font_h − em) / 2` px, clipping the glyph on high-DPI devices (PW2 etc.) | `include/lvstring.h` |
| Float / inline-block image wrapping: vertical mode reuses `BlockFloatFootprint` with swapped semantics, so columns intersecting a floated image start after the image's in-column exclusion instead of drawing text underneath it or reserving a full in-flow column band | `lvrend.cpp`, `lvtextfm.cpp`, `lvtextfm_vert.cpp`, `vertical_float_image_spec.lua` |

**Note on whitespace**: some EPUBs have U+0020 spaces adjacent to ruby groups (e.g. `と Nachbild《…》 という`). These render as narrow gaps proportional to the space glyph's advance width (≈ ¼ em). This is expected — the space is in the EPUB source.

## Open Issues

### P6 — Per-element writing mode (low priority)

- Mixed horizontal/vertical blocks within one document

## Key File Locations

```
base/                                           crengine submodule
  cre.cpp                                       KOReader↔crengine bridge
  thirdparty/kpvcrlib/crengine/crengine/
    include/lvlogical.h                         CSS logical property index helpers
    include/lvtextfm_fork.h                     Fork-only decls + VerticalDrawState struct
    include/lvfntman_vert.h                     JFM class enum, vert metrics cache decls
    src/lvrend.cpp                              Block rendering, FlowState
    src/lvtextfm_vert.cpp                       Vertical paragraph layout, kinsoku/oidashi/xkanjiskip (fork-only, #included by lvtextfm.cpp)
    src/lvtextfm.cpp                            measureText, ruby inline box
    src/lvfntman_vert.cpp                       JFM class tables, vform, slot width, glyph rotation (fork-only; absorbed former lvfntman_vert_slot.cpp)
    src/lvdocview_vert.cpp                      vertPageRight, isVerticalText (fork-only, #included by lvdocview.cpp)
    src/lvdocview.cpp                           windowToDocPoint, docToWindowPoint
    src/lvfntman.cpp                            HarfBuzz font shaping, +vert/+vrt2/+vkrn features, glyph rotation
    src/lvtinydom.cpp                           DOM, getAbsRect, getRect, getSegmentRects
frontend/document/credocument.lua               Lua wrappers: getWordFromPosition, getTextFromPositions
spec/unit/vertical_text_spec.lua                Formal regression tests
spec/unit/vertical_option_c_spec.lua            Option C: uniform column y_base test
spec/unit/ruby_annot_y_spec.lua                 Ruby cell placement regression
```

## Submodule Chain — commit correspondence

When making C++ changes (crengine), all three repos must be committed and
pushed in order. **The CI fetches each submodule by SHA; if any SHA is not
reachable from the remote's default branch the build will fail.**

```
koreader-tategumi  (github.com/m-tky/koreader-tategumi)
  └─ base          (github.com/m-tky/koreader-base)
       └─ crengine (github.com/m-tky/crengine)
```

### Workflow for crengine changes

Use `scripts/push-chain.sh` to push commits through the chain automatically:

```bash
# Push crengine → base → koreader (full chain)
./scripts/push-chain.sh

# Push from base upward (crengine already pushed)
./scripts/push-chain.sh base

# Push koreader only
./scripts/push-chain.sh koreader

# Preview what would be pushed without doing anything
./scripts/push-chain.sh --dry-run
```

The script handles detached HEAD and diverged branches by cherry-picking onto
`mytky/master`, and automatically fixes stale submodule SHAs (the common failure
mode where a local commit SHA appears in a submodule pointer but was never pushed).

### Release timing

- Check the recent `git log` first and judge the full change batch, not just the
  latest fix.
- Group adjacent fixes into one release when they touch the same user-facing
  area.
- For rendering changes, a `3-4 day` soak is a good default unless the bug is
  actively blocking users.

Manual equivalent (if needed):

```bash
# 1. Commit in crengine, push to m-tky/crengine
cd base/thirdparty/kpvcrlib/crengine
git commit -am "..."
git push mytky HEAD:master   # or cherry-pick onto mytky/master if detached

# 2. Update base pointer, push to m-tky/koreader-base
cd ../../..                  # = base/
git add thirdparty/kpvcrlib/crengine
git commit -m "crengine: ..."
git push mytky HEAD:master   # or cherry-pick onto mytky/master if detached

# 3. Update main repo pointer, push, retag
cd ..                        # = koreader/
git add base
git commit -m "base: ..."
git push origin master
git tag -d vYYYY.MM.P && git push origin :refs/tags/vYYYY.MM.P
git tag -a vYYYY.MM.P -m "..." && git push origin vYYYY.MM.P
```

### Pitfall: detached HEAD in base/crengine

Both `base` and `crengine` are often in detached HEAD state.
Commits made in detached HEAD are NOT on any remote branch.
`push-chain.sh` handles this automatically. Manually:

```bash
git checkout mytky/master -b tmp-push
git cherry-pick <sha>
git push mytky tmp-push:master
```

## Test EPUBs

`test/fixtures/vertical_text/sanshiro.epub` (三四郎, Natsume Soseki) — main test EPUB with ruby annotations.
`test/fixtures/vertical_text/simple_ja_noruby.epub` — formal unit tests (no ruby, simpler structure).

`sanshiro.epub` has its own `writing-mode: vertical-rl` CSS; no style tweak needed.
Other EPUBs require: `body { writing-mode: vertical-rl !important; }` via style tweak.
