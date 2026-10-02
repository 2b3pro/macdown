//
//  mp_superscript.c
//  MacDown
//
//  ^word and ^(several words) render as <sup>. This keeps Hoedown's syntax:
//  a bare caret takes everything up to the next whitespace, a caret followed
//  by a parenthesis takes everything up to the closing parenthesis. The
//  superscript text is not parsed further for Markdown.
//

#include <cmark-gfm/parser.h>
#include <cmark-gfm/render.h>
#include <cmark-gfm/html.h>
#include <cmark-gfm/chunk.h>
#include "mp_extensions.h"

static cmark_node_type MP_NODE_SUPERSCRIPT;

static int is_space(unsigned char c)
{
    return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f'
        || c == '\v';
}

static cmark_node *match(cmark_syntax_extension *self, cmark_parser *parser,
                         cmark_node *parent, unsigned char character,
                         cmark_inline_parser *inline_parser)
{
    if (character != '^')
        return NULL;

    cmark_chunk *chunk = cmark_inline_parser_get_chunk(inline_parser);
    bufsize_t start = cmark_inline_parser_get_offset(inline_parser);
    bufsize_t size = chunk->len;
    const unsigned char *data = chunk->data;

    // "[^" starts a footnote reference, which belongs to cmark-gfm.
    if (start > 0 && data[start - 1] == '[')
        return NULL;
    if (start + 1 >= size)
        return NULL;

    bufsize_t content_start, content_end, end;
    if (data[start + 1] == '(')
    {
        content_start = start + 2;
        content_end = content_start;
        while (content_end < size && data[content_end] != ')')
            content_end++;
        if (content_end >= size)
            return NULL;
        end = content_end + 1;
    }
    else
    {
        content_start = start + 1;
        content_end = content_start;
        while (content_end < size && !is_space(data[content_end]))
            content_end++;
        end = content_end;
    }
    if (content_end == content_start)
        return NULL;

    int line = cmark_inline_parser_get_line(inline_parser);
    int column = cmark_inline_parser_get_column(inline_parser);

    cmark_node *sup = cmark_node_new_with_mem(MP_NODE_SUPERSCRIPT, parser->mem);
    cmark_node_set_syntax_extension(sup, self);
    sup->start_line = sup->end_line = line;
    sup->start_column = column;
    sup->end_column = column + (end - start) - 1;

    cmark_node *text = cmark_node_new_with_mem(CMARK_NODE_TEXT, parser->mem);
    text->as.literal = cmark_chunk_dup(chunk, content_start,
                                       content_end - content_start);
    text->start_line = text->end_line = line;
    cmark_node_append_child(sup, text);

    cmark_inline_parser_set_offset(inline_parser, end);
    return sup;
}

static const char *get_type_string(cmark_syntax_extension *extension,
                                   cmark_node *node)
{
    return node->type == MP_NODE_SUPERSCRIPT ? "superscript" : "<unknown>";
}

static int can_contain(cmark_syntax_extension *extension, cmark_node *node,
                       cmark_node_type child_type)
{
    if (node->type != MP_NODE_SUPERSCRIPT)
        return 0;
    return CMARK_NODE_TYPE_INLINE_P(child_type);
}

static void html_render(cmark_syntax_extension *extension,
                        cmark_html_renderer *renderer, cmark_node *node,
                        cmark_event_type ev_type, int options)
{
    if (ev_type == CMARK_EVENT_ENTER)
        cmark_strbuf_puts(renderer->html, "<sup>");
    else
        cmark_strbuf_puts(renderer->html, "</sup>");
}

cmark_syntax_extension *mp_create_superscript_extension(void)
{
    cmark_syntax_extension *ext = cmark_syntax_extension_new("superscript");
    cmark_syntax_extension_set_get_type_string_func(ext, get_type_string);
    cmark_syntax_extension_set_can_contain_func(ext, can_contain);
    cmark_syntax_extension_set_html_render_func(ext, html_render);
    MP_NODE_SUPERSCRIPT = cmark_syntax_extension_add_node(1);

    cmark_syntax_extension_set_match_inline_func(ext, match);

    cmark_mem *mem = cmark_get_default_mem_allocator();
    cmark_llist *chars = cmark_llist_append(mem, NULL, (void *)'^');
    cmark_syntax_extension_set_special_inline_chars(ext, chars);
    return ext;
}
