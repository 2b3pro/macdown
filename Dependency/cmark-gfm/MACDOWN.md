# cmark-gfm in MacDown

This directory vendors [cmark-gfm](https://github.com/github/cmark-gfm) at tag
`0.29.0.gfm.13` (commit `587a12bb54d95ac37241377e6ddc93ea0e45439b`). It is
built as a local CocoaPods pod (`cmark-gfm.podspec`) for the MacDown app and
the Quick Look extension.

## What is included

* `src/` and `extensions/`: the upstream sources, minus `main.c`, the build
  files and the re2c inputs (the generated scanners are kept).
* `generated/`: headers that upstream produces with CMake (`config.h`,
  `cmark-gfm_version.h`, `cmark-gfm_export.h`), written by hand for macOS.
* `COPYING`: the upstream license, also in `LICENSE/cmark-gfm.txt`.

## MacDown patches

Each change is marked with a `MacDown:` comment.

1. **`src/node.h`**: adds the internal node flag `CMARK_NODE__UNDERSCORE_EMPH`
   and moves `CMARK_NODE__REGISTER_FIRST` up one bit to make room.
2. **`src/inlines.c`, `S_insert_emph`**: sets that flag on emphasis created
   from a single underscore (`_text_`). MacDown's underline extension turns
   those nodes into `<u>`. Without the extension the flag has no effect.
3. **`src/inlines.c`, `parse_inline`**: offers a backslash to the attached
   extensions before treating it as an escape. MacDown's math extension uses
   this for `\\(...\\)` and `\\[...\\]`. Extensions that don't handle a
   backslash return NULL, which falls through to the normal escape.

## Updating

1. Copy `src/` and `extensions/` from the new upstream tag, leaving out the
   files listed above.
2. Re-apply the three patches (search the old copy for `MacDown:`).
3. Update `generated/cmark-gfm_version.h`, the version in
   `cmark-gfm.podspec`, and this file.
4. Run `pod install`, then the `MPMarkdownTests` unit tests.
