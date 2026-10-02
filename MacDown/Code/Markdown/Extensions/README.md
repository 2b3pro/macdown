# Writing a Markdown extension for MacDown

MacDown parses Markdown with [cmark-gfm](https://github.com/github/cmark-gfm)
(CommonMark plus GitHub Flavored Markdown). Anything beyond that, such as
highlight, superscript, underline or math, is a cmark-gfm *syntax extension*
in this directory. Each one is a single C file that the user can toggle in
**Preferences > Markdown**.

The bundled extensions are small and make good templates:

| File | Syntax | Technique |
|---|---|---|
| `mp_highlight.c` | `==text==` → `<mark>` | Delimiter run, nests like emphasis |
| `mp_superscript.c` | `^word`, `^(words)` → `<sup>` | Matches a character and consumes text |
| `mp_math.c` | `$$…$$`, `\\(…\\)`, `$…$` → MathJax | Keeps raw text away from the parser |
| `mp_underline.c` | `_text_` → `<u>` | Rewrites parsed nodes after parsing |

## The pieces of an extension

1. **A node type.** `cmark_syntax_extension_add_node(1)` for inline content,
   `(0)` for a block. Keep it in a `static cmark_node_type`.
2. **Matching**, using one of these:
   * `set_match_inline_func` plus `set_special_inline_chars` to be called
     when the inline parser reaches one of your characters. Return a node
     and advance with `cmark_inline_parser_set_offset`, or return `NULL` to
     let the next extension (and then cmark) try.
   * `set_inline_from_delim_func` plus `set_emphasis(ext, 1)` for paired
     delimiters that nest with `*` and `_` (see `mp_highlight.c`).
   * `set_postprocess_func` to rewrite the finished document tree.
3. **Rendering.** `set_html_render_func` writes the opening HTML on
   `CMARK_EVENT_ENTER` and the closing HTML on `CMARK_EVENT_EXIT`. Child
   nodes render between the two.
4. **Containment.** `set_can_contain_func` says which child node types your
   node accepts, usually `CMARK_NODE_TYPE_INLINE_P(child_type)`.
5. **A factory** that builds and returns the extension, declared in
   `mp_extensions.h`.

## Registering it

1. Add a flag to the `MPMarkdownExtension…` enum in `../MPMarkdown.h`.
2. Add a row to `MPExtensionRegistry` in `../MPMarkdown.c`. Order matters:
   an earlier row gets the first chance at a character.
3. Add the `.c` file to both the **MacDown** and **MacDownQuickLook**
   targets, so the preview and Finder's Quick Look render it the same way.
4. To make it user-toggleable, add a preference in `MPPreferences`, a
   checkbox in `MPMarkdownPreferencesViewController.xib`, and map the
   preference to your flag in `-[MPPreferences extensionFlags]`
   (`MPDocument.m`) and `MPExtensionFlags()` (`MPQuickLookPreviewProvider.m`).
5. Add rendering tests to `MacDownTests/MPMarkdownTests.m`.

## Things to keep in mind

* cmark-gfm handles `*`, `_`, `` ` ``, `[`, `]`, `<`, `&`, `!` and newlines
  itself, before any extension sees them. A backslash is offered to
  extensions first (a MacDown patch, see `Dependency/cmark-gfm/MACDOWN.md`).
* Text you put in a `CMARK_NODE_TEXT` child is HTML-escaped on output and
  never parsed as Markdown, which is the right home for raw content.
* Extensions are created once and shared by every document, so keep
  per-document state in the nodes, not in globals. Per-render settings can
  travel as a bit in the parser options (see `MP_CMARK_OPT_MATH_INLINE_DOLLAR`).
