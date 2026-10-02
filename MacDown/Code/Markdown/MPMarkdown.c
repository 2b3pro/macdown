//
//  MPMarkdown.c
//  MacDown
//
//  Parses with cmark-gfm, then adjusts the document so the HTML keeps the
//  shape MacDown's preview, styles and scripts expect:
//
//  * Headings get sequential ids (toc_0, toc_1, ...) that the table of
//    contents links to.
//  * A paragraph containing only [TOC] is replaced by the table of contents.
//  * Code blocks are wrapped as <div><pre><code class="language-X"> for Prism,
//    Mermaid and Graphviz, with optional line numbers and block information.
//  * Task list items get class="task-list-item" and a checkbox.
//

#include "MPMarkdown.h"
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <cmark-gfm/cmark-gfm.h>
#include <cmark-gfm/cmark-gfm-extension_api.h>
#include <cmark-gfm/cmark-gfm-core-extensions.h>
#include <cmark-gfm/node.h>
#include <cmark-gfm/render.h>
#include <cmark-gfm/html.h>
#include <cmark-gfm/houdini.h>
#include "mp_extensions.h"


#pragma mark - Extension registry

// Every syntax extension MacDown can turn on. Built-in cmark-gfm extensions
// are looked up by name; MacDown's own are created by their factory. To add
// an extension, write it in Extensions/, give it a flag in MPMarkdown.h and
// add a row here. Rows are attached in order, and an earlier extension gets
// the first chance at a character, so math comes first to keep TeX intact.
typedef struct {
    unsigned int flag;
    const char *builtinName;
    cmark_syntax_extension *(*create)(void);
    cmark_syntax_extension *extension;
} MPExtensionEntry;

static MPExtensionEntry MPExtensionRegistry[] = {
    {MPMarkdownExtensionMath, NULL, mp_create_math_extension, NULL},
    {MPMarkdownExtensionTables, "table", NULL, NULL},
    {MPMarkdownExtensionAutolink, "autolink", NULL, NULL},
    {MPMarkdownExtensionStrikethrough, "strikethrough", NULL, NULL},
    {MPMarkdownExtensionUnderline, NULL, mp_create_underline_extension, NULL},
    {MPMarkdownExtensionHighlight, NULL, mp_create_highlight_extension, NULL},
    {MPMarkdownExtensionSuperscript, NULL,
        mp_create_superscript_extension, NULL},
};

static const size_t MPExtensionCount =
    sizeof(MPExtensionRegistry) / sizeof(MPExtensionRegistry[0]);

static cmark_syntax_extension *MPTaskListExtension;

// Renders MacDown's headings and task list items (see MPApplyMacDownHTML).
static cmark_syntax_extension *MPRendererExtension;
static cmark_node_type MP_NODE_HEADING;


#pragma mark - MacDown renderer nodes

// Heading nodes keep their level in cmark's heading data and their table of
// contents index in user_data.
static int MPHeadingIndex(cmark_node *node)
{
    return (int)(intptr_t)cmark_node_get_user_data(node);
}

static const char *MPRendererTypeString(cmark_syntax_extension *extension,
                                        cmark_node *node)
{
    return node->type == MP_NODE_HEADING ? "heading" : "task_list_item";
}

static int MPRendererCanContain(cmark_syntax_extension *extension,
                                cmark_node *node, cmark_node_type child_type)
{
    if (node->type == MP_NODE_HEADING)
        return CMARK_NODE_TYPE_INLINE_P(child_type);
    if (node->type == CMARK_NODE_ITEM)
    {
        return CMARK_NODE_TYPE_BLOCK_P(child_type)
            && child_type != CMARK_NODE_ITEM;
    }
    return 0;
}

static void MPRendererRenderHTML(cmark_syntax_extension *extension,
                                 cmark_html_renderer *renderer,
                                 cmark_node *node, cmark_event_type ev_type,
                                 int options)
{
    cmark_strbuf *html = renderer->html;
    int entering = (ev_type == CMARK_EVENT_ENTER);
    char tag[32];

    if (node->type == MP_NODE_HEADING)
    {
        int level = node->as.heading.level;
        if (entering)
        {
            cmark_html_render_cr(html);
            snprintf(tag, sizeof(tag), "<h%d id=\"toc_%d\">",
                     level, MPHeadingIndex(node));
        }
        else
        {
            snprintf(tag, sizeof(tag), "</h%d>\n", level);
        }
        cmark_strbuf_puts(html, tag);
    }
    else if (node->type == CMARK_NODE_ITEM)
    {
        if (entering)
        {
            cmark_html_render_cr(html);
            cmark_strbuf_puts(html, "<li class=\"task-list-item\">");
        }
        else
        {
            cmark_strbuf_puts(html, "</li>\n");
        }
    }
}

static void MPMarkdownInitialize(void)
{
    cmark_gfm_core_extensions_ensure_registered();
    for (size_t i = 0; i < MPExtensionCount; i++)
    {
        MPExtensionEntry *entry = &MPExtensionRegistry[i];
        if (entry->builtinName)
            entry->extension = cmark_find_syntax_extension(entry->builtinName);
        else
            entry->extension = entry->create();
    }
    MPTaskListExtension = cmark_find_syntax_extension("tasklist");

    cmark_syntax_extension *ext = cmark_syntax_extension_new("macdown");
    cmark_syntax_extension_set_get_type_string_func(ext, MPRendererTypeString);
    cmark_syntax_extension_set_can_contain_func(ext, MPRendererCanContain);
    cmark_syntax_extension_set_html_render_func(ext, MPRendererRenderHTML);
    MP_NODE_HEADING = cmark_syntax_extension_add_node(0);
    MPRendererExtension = ext;
}


#pragma mark - Node lists

typedef struct {
    cmark_node **nodes;
    size_t count;
    size_t capacity;
} MPNodeList;

static void MPNodeListAppend(MPNodeList *list, cmark_node *node)
{
    if (list->count == list->capacity)
    {
        list->capacity = list->capacity ? list->capacity * 2 : 16;
        list->nodes = realloc(list->nodes,
                              list->capacity * sizeof(cmark_node *));
    }
    list->nodes[list->count++] = node;
}


#pragma mark - Code blocks

static void MPReplaceWithHTMLBlock(cmark_node *node, const char *html)
{
    cmark_node *block = cmark_node_new(CMARK_NODE_HTML_BLOCK);
    cmark_node_set_literal(block, html);
    cmark_node_insert_before(node, block);
    cmark_node_free(node);
}

static void MPRenderCodeBlock(cmark_node *node, const MPMarkdownOptions *options)
{
    cmark_mem *mem = cmark_get_default_mem_allocator();
    unsigned int flags = options->renderFlags;

    // The language is the first word of the info string. With block
    // information on, "lang:info" splits into the language and a label.
    const char *info = cmark_node_get_fence_info(node);
    size_t infoLength = 0;
    while (info && info[infoLength] && info[infoLength] != ' '
           && info[infoLength] != '\t')
        infoLength++;

    size_t languageLength = infoLength;
    const char *information = NULL;
    size_t informationLength = 0;
    if (info && (flags & MPMarkdownRenderCodeBlockInformation))
    {
        const char *colon = memchr(info, ':', infoLength);
        if (colon)
        {
            languageLength = (size_t)(colon - info);
            information = colon + 1;
            informationLength = infoLength - languageLength - 1;
        }
    }

    char *language = strndup(info ? info : "", languageLength);
    if (languageLength && options->languageCallback)
    {
        char *mapped = options->languageCallback(language, options->context);
        if (mapped)
        {
            free(language);
            language = mapped;
        }
    }

    cmark_strbuf html = CMARK_BUF_INIT(mem);
    cmark_strbuf_puts(&html, "<div><pre");
    if (flags & MPMarkdownRenderLineNumbers)
        cmark_strbuf_puts(&html, " class=\"line-numbers\"");
    if (informationLength)
    {
        cmark_strbuf_puts(&html, " data-information=\"");
        houdini_escape_html0(&html, (const uint8_t *)information,
                             (bufsize_t)informationLength, 0);
        cmark_strbuf_puts(&html, "\"");
    }
    cmark_strbuf_puts(&html, "><code class=\"language-");
    if (language[0])
    {
        houdini_escape_html0(&html, (const uint8_t *)language,
                             (bufsize_t)strlen(language), 0);
    }
    else
    {
        cmark_strbuf_puts(&html, "none");
    }
    cmark_strbuf_puts(&html, "\">");

    // Drop the final newline so Prism does not add an empty last line.
    const char *code = cmark_node_get_literal(node);
    size_t codeLength = code ? strlen(code) : 0;
    if (codeLength && code[codeLength - 1] == '\n')
        codeLength--;
    houdini_escape_html0(&html, (const uint8_t *)code, (bufsize_t)codeLength, 0);
    cmark_strbuf_puts(&html, "</code></pre></div>\n");

    MPReplaceWithHTMLBlock(node, (const char *)html.ptr);
    cmark_strbuf_free(&html);
    free(language);
}


#pragma mark - Task lists

static void MPRenderTaskListItem(cmark_node *item)
{
    int checked = cmark_gfm_extensions_get_tasklist_item_checked(item);
    cmark_node_set_syntax_extension(item, MPRendererExtension);

    const char *checkbox = checked
        ? "<input type=\"checkbox\" checked> " : "<input type=\"checkbox\"> ";
    cmark_node *first = cmark_node_first_child(item);
    if (first && cmark_node_get_type(first) == CMARK_NODE_PARAGRAPH)
    {
        cmark_node *input = cmark_node_new(CMARK_NODE_HTML_INLINE);
        cmark_node_set_literal(input, checkbox);
        cmark_node_prepend_child(first, input);
    }
    else
    {
        cmark_node *input = cmark_node_new(CMARK_NODE_HTML_BLOCK);
        cmark_node_set_literal(input, checkbox);
        cmark_node_prepend_child(item, input);
    }
}


#pragma mark - Table of contents

// A paragraph whose text is exactly "[TOC]" (any case, surrounding spaces
// allowed) marks where the table of contents goes.
static int MPIsTOCPlaceholder(cmark_node *paragraph)
{
    char text[16];
    size_t length = 0;
    for (cmark_node *child = cmark_node_first_child(paragraph); child;
         child = cmark_node_next(child))
    {
        if (cmark_node_get_type(child) != CMARK_NODE_TEXT)
            return 0;
        const char *literal = cmark_node_get_literal(child);
        size_t n = strlen(literal);
        if (length + n >= sizeof(text))
            return 0;
        memcpy(text + length, literal, n);
        length += n;
    }
    text[length] = '\0';

    char *start = text;
    while (*start == ' ' || *start == '\t')
        start++;
    char *end = text + length;
    while (end > start && (end[-1] == ' ' || end[-1] == '\t'))
        end--;
    *end = '\0';
    return strcasecmp(start, "[TOC]") == 0;
}

// Heading content without links, so the TOC does not nest <a> elements.
static void MPAppendTOCContent(cmark_strbuf *toc, cmark_node *parent,
                               int cmarkOptions, cmark_llist *extensions)
{
    for (cmark_node *child = cmark_node_first_child(parent); child;
         child = cmark_node_next(child))
    {
        if (cmark_node_get_type(child) == CMARK_NODE_LINK)
        {
            MPAppendTOCContent(toc, child, cmarkOptions, extensions);
            continue;
        }
        char *html = cmark_render_html(child, cmarkOptions, extensions);
        cmark_strbuf_puts(toc, html);
        free(html);
    }
}

// Nested lists of links to every heading, levels relative to the first.
static char *MPCreateTOC(MPNodeList *headings, const int *levels,
                         int cmarkOptions, cmark_llist *extensions)
{
    cmark_strbuf toc = CMARK_BUF_INIT(cmark_get_default_mem_allocator());
    int current = 0;
    int offset = 0;
    char anchor[48];

    for (size_t i = 0; i < headings->count; i++)
    {
        int level = levels[i];
        if (current == 0)
            offset = level - 1;
        level -= offset;
        if (level < 1)
            level = 1;

        if (level > current)
        {
            while (level > current)
            {
                cmark_strbuf_puts(&toc, current == 0
                    ? "<ul class=\"toc\">\n<li>\n" : "<ul>\n<li>\n");
                current++;
            }
        }
        else if (level < current)
        {
            cmark_strbuf_puts(&toc, "</li>\n");
            while (level < current)
            {
                cmark_strbuf_puts(&toc, "</ul>\n</li>\n");
                current--;
            }
            cmark_strbuf_puts(&toc, "<li>\n");
        }
        else
        {
            cmark_strbuf_puts(&toc, "</li>\n<li>\n");
        }

        snprintf(anchor, sizeof(anchor), "<a href=\"#toc_%zu\">", i);
        cmark_strbuf_puts(&toc, anchor);
        MPAppendTOCContent(&toc, headings->nodes[i], cmarkOptions, extensions);
        cmark_strbuf_puts(&toc, "</a>\n");
    }
    while (current > 0)
    {
        cmark_strbuf_puts(&toc, "</li>\n</ul>\n");
        current--;
    }
    return (char *)cmark_strbuf_detach(&toc);
}


#pragma mark - Document pass

static void MPApplyMacDownHTML(cmark_node *document,
                               const MPMarkdownOptions *options,
                               int cmarkOptions, cmark_llist *extensions)
{
    MPNodeList headings = {0};
    MPNodeList codeBlocks = {0};
    MPNodeList taskItems = {0};
    MPNodeList placeholders = {0};
    int wantsTOC = (options->renderFlags & MPMarkdownRenderTOC) != 0;

    // Collect first; the tree is changed only after iteration finishes.
    cmark_iter *iter = cmark_iter_new(document);
    cmark_event_type ev;
    while ((ev = cmark_iter_next(iter)) != CMARK_EVENT_DONE)
    {
        if (ev != CMARK_EVENT_ENTER)
            continue;
        cmark_node *node = cmark_iter_get_node(iter);
        switch (cmark_node_get_type(node))
        {
            case CMARK_NODE_HEADING:
                MPNodeListAppend(&headings, node);
                break;
            case CMARK_NODE_CODE_BLOCK:
                MPNodeListAppend(&codeBlocks, node);
                break;
            case CMARK_NODE_ITEM:
                if (node->extension == MPTaskListExtension)
                    MPNodeListAppend(&taskItems, node);
                break;
            case CMARK_NODE_PARAGRAPH:
                if (wantsTOC && MPIsTOCPlaceholder(node))
                    MPNodeListAppend(&placeholders, node);
                break;
            default:
                break;
        }
    }
    cmark_iter_free(iter);

    int *levels = calloc(headings.count ? headings.count : 1, sizeof(int));
    for (size_t i = 0; i < headings.count; i++)
    {
        cmark_node *heading = headings.nodes[i];
        levels[i] = cmark_node_get_heading_level(heading);
        if (cmark_node_set_type(heading, MP_NODE_HEADING))
        {
            cmark_node_set_syntax_extension(heading, MPRendererExtension);
            cmark_node_set_user_data(heading, (void *)(intptr_t)i);
        }
    }

    for (size_t i = 0; i < codeBlocks.count; i++)
        MPRenderCodeBlock(codeBlocks.nodes[i], options);
    for (size_t i = 0; i < taskItems.count; i++)
        MPRenderTaskListItem(taskItems.nodes[i]);

    if (placeholders.count)
    {
        char *toc = MPCreateTOC(&headings, levels, cmarkOptions, extensions);
        for (size_t i = 0; i < placeholders.count; i++)
            MPReplaceWithHTMLBlock(placeholders.nodes[i], toc);
        free(toc);
    }

    free(levels);
    free(headings.nodes);
    free(codeBlocks.nodes);
    free(taskItems.nodes);
    free(placeholders.nodes);
}


#pragma mark - Public

char *MPMarkdownRenderHTML(const char *markdown, size_t length,
                           const MPMarkdownOptions *options)
{
    static pthread_once_t once = PTHREAD_ONCE_INIT;
    pthread_once(&once, MPMarkdownInitialize);

    unsigned int extensions = options->extensions;
    unsigned int flags = options->renderFlags;

    // Raw HTML passes through, as it always has in MacDown.
    int cmarkOptions = CMARK_OPT_UNSAFE;
    if (extensions & MPMarkdownExtensionFootnotes)
        cmarkOptions |= CMARK_OPT_FOOTNOTES;
    if (extensions & MPMarkdownExtensionMathInlineDollar)
        cmarkOptions |= MP_CMARK_OPT_MATH_INLINE_DOLLAR;
    if (flags & MPMarkdownRenderHardWrap)
        cmarkOptions |= CMARK_OPT_HARDBREAKS;
    if (flags & MPMarkdownRenderSmartyPants)
        cmarkOptions |= CMARK_OPT_SMART;

    cmark_parser *parser = cmark_parser_new(cmarkOptions);
    for (size_t i = 0; i < MPExtensionCount; i++)
    {
        MPExtensionEntry *entry = &MPExtensionRegistry[i];
        if ((extensions & entry->flag) && entry->extension)
            cmark_parser_attach_syntax_extension(parser, entry->extension);
    }
    if ((flags & MPMarkdownRenderTaskList) && MPTaskListExtension)
        cmark_parser_attach_syntax_extension(parser, MPTaskListExtension);

    cmark_parser_feed(parser, markdown, length);
    cmark_node *document = cmark_parser_finish(parser);
    cmark_llist *attached = cmark_parser_get_syntax_extensions(parser);

    MPApplyMacDownHTML(document, options, cmarkOptions, attached);
    char *html = cmark_render_html(document, cmarkOptions, attached);

    cmark_node_free(document);
    cmark_parser_free(parser);
    return html;
}
