//
//  mp_extensions.h
//  MacDown
//
//  MacDown's own cmark-gfm syntax extensions. Each one lives in its own file
//  and is registered in MPMarkdown.c. See README.md in this directory for how
//  to write a new one.
//

#ifndef MacDown_mp_extensions_h
#define MacDown_mp_extensions_h

#include <cmark-gfm/cmark-gfm.h>
#include <cmark-gfm/cmark-gfm-extension_api.h>

// Parser option bits owned by MacDown's extensions. cmark-gfm leaves the high
// bits of the options word unused, and passes the whole word through to
// extensions, so these travel with the parser like the built-in options.

// The math extension also accepts single-dollar inline math ($...$).
#define MP_CMARK_OPT_MATH_INLINE_DOLLAR (1 << 28)

// ==text== renders as <mark>text</mark>.
cmark_syntax_extension *mp_create_highlight_extension(void);

// ^word and ^(some words) render as <sup>.
cmark_syntax_extension *mp_create_superscript_extension(void);

// _text_ (single underscore) renders as <u> instead of <em>.
cmark_syntax_extension *mp_create_underline_extension(void);

// $$...$$, \\(...\\), \\[...\\] (and $...$ with MP_CMARK_OPT_MATH_INLINE_DOLLAR)
// are kept verbatim for MathJax instead of being parsed as Markdown.
cmark_syntax_extension *mp_create_math_extension(void);

#endif
