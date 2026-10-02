//
//  mp_math.c
//  MacDown
//
//  Keeps TeX math away from the Markdown parser so MathJax receives it intact.
//  The syntax and output match what MacDown rendered with Hoedown:
//
//    $$...$$     display math when it is alone in its paragraph, inline
//                otherwise (always display with inline-dollar math enabled)
//    \\[...\\]   display math
//    \\(...\\)   inline math
//    $...$       inline math, only with MP_CMARK_OPT_MATH_INLINE_DOLLAR
//
//  Math is written out as \(...\) or \[...\] with HTML escaped, which are
//  MathJax's default delimiters.
//
//  The \\( and \\[ forms start with a backslash, which cmark-gfm normally
//  treats as an escape before extensions run; the vendored copy is patched to
//  offer backslashes to extensions first (see Dependency/cmark-gfm/MACDOWN.md).
//

#include <string.h>
#include <cmark-gfm/parser.h>
#include <cmark-gfm/render.h>
#include <cmark-gfm/html.h>
#include <cmark-gfm/chunk.h>
#include "mp_extensions.h"

static cmark_node_type MP_NODE_MATH_INLINE;
static cmark_node_type MP_NODE_MATH_DISPLAY;

static int is_space(unsigned char c)
{
    return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f'
        || c == '\v';
}

// Whether the character at index i is escaped by an odd number of
// backslashes before it.
static int is_escaped(const unsigned char *data, bufsize_t i)
{
    bufsize_t backslashes = 0;
    while (i > 0 && data[i - 1] == '\\')
    {
        backslashes++;
        i--;
    }
    return backslashes % 2 == 1;
}

static int is_blank(const unsigned char *data, bufsize_t from, bufsize_t to)
{
    for (bufsize_t i = from; i < to; i++)
    {
        if (!is_space(data[i]))
            return 0;
    }
    return 1;
}

// Finds the closing delimiter at or after `from`. Returns its index, or -1.
static bufsize_t find_closing(const unsigned char *data, bufsize_t from,
                              bufsize_t size, const char *delim,
                              bufsize_t delim_size)
{
    for (bufsize_t i = from; i + delim_size <= size; i++)
    {
        if (data[i] != (unsigned char)delim[0])
            continue;
        if (memcmp(data + i, delim, delim_size) == 0 && !is_escaped(data, i))
            return i;
    }
    return -1;
}

static cmark_node *match(cmark_syntax_extension *self, cmark_parser *parser,
                         cmark_node *parent, unsigned char character,
                         cmark_inline_parser *inline_parser)
{
    if (character != '$' && character != '\\')
        return NULL;

    cmark_chunk *chunk = cmark_inline_parser_get_chunk(inline_parser);
    bufsize_t start = cmark_inline_parser_get_offset(inline_parser);
    bufsize_t size = chunk->len;
    const unsigned char *data = chunk->data;

    const char *closing = NULL;
    bufsize_t delim_size = 0;
    int display = 0;
    int inline_dollar = parser->options & MP_CMARK_OPT_MATH_INLINE_DOLLAR;

    if (character == '\\')
    {
        if (start + 2 >= size || data[start + 1] != '\\')
            return NULL;
        if (data[start + 2] == '(')
        {
            closing = "\\\\)";
        }
        else if (data[start + 2] == '[')
        {
            closing = "\\\\]";
            display = 1;
        }
        else
        {
            return NULL;
        }
        delim_size = 3;
    }
    else if (start + 1 < size && data[start + 1] == '$')
    {
        closing = "$$";
        delim_size = 2;
    }
    else if (inline_dollar)
    {
        closing = "$";
        delim_size = 1;
    }
    else
    {
        return NULL;
    }

    bufsize_t content_start = start + delim_size;
    bufsize_t content_end =
        find_closing(data, content_start, size, closing, delim_size);
    if (content_end < 0)
        return NULL;
    bufsize_t end = content_end + delim_size;

    if (delim_size == 2)
    {
        // Hoedown's rule: $$ is display math when nothing else shares the
        // paragraph, unless inline-dollar math makes $$ unambiguous.
        display = inline_dollar
            || (is_blank(data, 0, start) && is_blank(data, end, size));
    }

    int line = cmark_inline_parser_get_line(inline_parser);
    int column = cmark_inline_parser_get_column(inline_parser);

    cmark_node *math = cmark_node_new_with_mem(
        display ? MP_NODE_MATH_DISPLAY : MP_NODE_MATH_INLINE, parser->mem);
    cmark_node_set_syntax_extension(math, self);
    math->start_line = math->end_line = line;
    math->start_column = column;
    math->end_column = column + (end - start) - 1;

    // The TeX source is kept as a single text node, so the HTML renderer
    // escapes it but nothing parses it as Markdown.
    cmark_node *text = cmark_node_new_with_mem(CMARK_NODE_TEXT, parser->mem);
    text->as.literal = cmark_chunk_dup(chunk, content_start,
                                       content_end - content_start);
    text->start_line = text->end_line = line;
    cmark_node_append_child(math, text);

    cmark_inline_parser_set_offset(inline_parser, end);
    return math;
}

static const char *get_type_string(cmark_syntax_extension *extension,
                                   cmark_node *node)
{
    if (node->type == MP_NODE_MATH_DISPLAY)
        return "math_display";
    if (node->type == MP_NODE_MATH_INLINE)
        return "math_inline";
    return "<unknown>";
}

static int can_contain(cmark_syntax_extension *extension, cmark_node *node,
                       cmark_node_type child_type)
{
    if (node->type != MP_NODE_MATH_INLINE && node->type != MP_NODE_MATH_DISPLAY)
        return 0;
    return child_type == CMARK_NODE_TEXT;
}

static void html_render(cmark_syntax_extension *extension,
                        cmark_html_renderer *renderer, cmark_node *node,
                        cmark_event_type ev_type, int options)
{
    int display = (node->type == MP_NODE_MATH_DISPLAY);
    if (ev_type == CMARK_EVENT_ENTER)
        cmark_strbuf_puts(renderer->html, display ? "\\[" : "\\(");
    else
        cmark_strbuf_puts(renderer->html, display ? "\\]" : "\\)");
}

cmark_syntax_extension *mp_create_math_extension(void)
{
    cmark_syntax_extension *ext = cmark_syntax_extension_new("math");
    cmark_syntax_extension_set_get_type_string_func(ext, get_type_string);
    cmark_syntax_extension_set_can_contain_func(ext, can_contain);
    cmark_syntax_extension_set_html_render_func(ext, html_render);
    MP_NODE_MATH_INLINE = cmark_syntax_extension_add_node(1);
    MP_NODE_MATH_DISPLAY = cmark_syntax_extension_add_node(1);

    cmark_syntax_extension_set_match_inline_func(ext, match);

    cmark_mem *mem = cmark_get_default_mem_allocator();
    cmark_llist *chars = cmark_llist_append(mem, NULL, (void *)'$');
    chars = cmark_llist_append(mem, chars, (void *)'\\');
    cmark_syntax_extension_set_special_inline_chars(ext, chars);
    return ext;
}
