//
//  MPMarkdown.h
//  MacDown
//
//  Markdown to HTML, shared by the app and the Quick Look extension. Parsing
//  is CommonMark + GitHub Flavored Markdown (cmark-gfm); MacDown's optional
//  syntax lives in Extensions/.
//

#ifndef MacDown_MPMarkdown_h
#define MacDown_MPMarkdown_h

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Syntax extensions, toggled in Preferences > Markdown.
enum {
    MPMarkdownExtensionTables           = 1 << 0,
    MPMarkdownExtensionFootnotes        = 1 << 1,
    MPMarkdownExtensionAutolink         = 1 << 2,
    MPMarkdownExtensionStrikethrough    = 1 << 3,
    MPMarkdownExtensionUnderline        = 1 << 4,
    MPMarkdownExtensionHighlight        = 1 << 5,
    MPMarkdownExtensionSuperscript      = 1 << 6,
    MPMarkdownExtensionMath             = 1 << 7,
    MPMarkdownExtensionMathInlineDollar = 1 << 8,
};

// Output options, toggled in Preferences > Rendering.
enum {
    MPMarkdownRenderTaskList             = 1 << 0,
    MPMarkdownRenderHardWrap             = 1 << 1,
    MPMarkdownRenderLineNumbers          = 1 << 2,
    MPMarkdownRenderCodeBlockInformation = 1 << 3,
    MPMarkdownRenderSmartyPants          = 1 << 4,
    MPMarkdownRenderTOC                  = 1 << 5,
};

// Called with the language of every fenced code block. Return a malloc'd
// replacement name (for aliases), or NULL to keep the language as written.
typedef char *(*MPMarkdownLanguageCallback)(const char *language,
                                            void *context);

typedef struct {
    unsigned int extensions;    // MPMarkdownExtension* bits
    unsigned int renderFlags;   // MPMarkdownRender* bits
    MPMarkdownLanguageCallback languageCallback;  // optional
    void *context;              // passed to languageCallback
} MPMarkdownOptions;

// Renders a UTF-8 Markdown string to an HTML fragment. The caller frees the
// result with free().
char *MPMarkdownRenderHTML(const char *markdown, size_t length,
                           const MPMarkdownOptions *options);

#ifdef __cplusplus
}
#endif

#endif
