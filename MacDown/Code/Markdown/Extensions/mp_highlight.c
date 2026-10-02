//
//  mp_highlight.c
//  MacDown
//
//  ==text== renders as <mark>text</mark>. Modeled on cmark-gfm's strikethrough
//  extension: '=' runs are pushed as delimiters, so highlight nests with
//  emphasis the same way ~~strikethrough~~ does.
//

#include <string.h>
#include <cmark-gfm/parser.h>
#include <cmark-gfm/render.h>
#include <cmark-gfm/html.h>
#include "mp_extensions.h"

static cmark_node_type MP_NODE_HIGHLIGHT;

static cmark_node *match(cmark_syntax_extension *self, cmark_parser *parser,
                         cmark_node *parent, unsigned char character,
                         cmark_inline_parser *inline_parser)
{
    if (character != '=')
        return NULL;

    int left_flanking, right_flanking, punct_before, punct_after;
    char buffer[101];
    int delims = cmark_inline_parser_scan_delimiters(
        inline_parser, sizeof(buffer) - 1, '=', &left_flanking,
        &right_flanking, &punct_before, &punct_after);

    memset(buffer, '=', delims);
    buffer[delims] = 0;

    cmark_node *res = cmark_node_new_with_mem(CMARK_NODE_TEXT, parser->mem);
    cmark_node_set_literal(res, buffer);
    res->start_line = res->end_line =
        cmark_inline_parser_get_line(inline_parser);
    res->start_column = cmark_inline_parser_get_column(inline_parser) - delims;

    // Only a run of exactly two can open or close a highlight.
    if ((left_flanking || right_flanking) && delims == 2)
    {
        cmark_inline_parser_push_delimiter(
            inline_parser, character, left_flanking, right_flanking, res);
    }
    return res;
}

static delimiter *insert(cmark_syntax_extension *self, cmark_parser *parser,
                         cmark_inline_parser *inline_parser,
                         delimiter *opener, delimiter *closer)
{
    delimiter *res = closer->next;
    cmark_node *highlight = opener->inl_text;

    if (opener->inl_text->as.literal.len != closer->inl_text->as.literal.len)
        goto done;
    if (!cmark_node_set_type(highlight, MP_NODE_HIGHLIGHT))
        goto done;
    cmark_node_set_syntax_extension(highlight, self);

    cmark_node *tmp = cmark_node_next(opener->inl_text);
    while (tmp && tmp != closer->inl_text)
    {
        cmark_node *next = cmark_node_next(tmp);
        cmark_node_append_child(highlight, tmp);
        tmp = next;
    }
    highlight->end_column = closer->inl_text->start_column
        + closer->inl_text->as.literal.len - 1;
    cmark_node_free(closer->inl_text);

done:
    for (delimiter *d = closer; d != NULL && d != opener;)
    {
        delimiter *previous = d->previous;
        cmark_inline_parser_remove_delimiter(inline_parser, d);
        d = previous;
    }
    cmark_inline_parser_remove_delimiter(inline_parser, opener);
    return res;
}

static const char *get_type_string(cmark_syntax_extension *extension,
                                   cmark_node *node)
{
    return node->type == MP_NODE_HIGHLIGHT ? "highlight" : "<unknown>";
}

static int can_contain(cmark_syntax_extension *extension, cmark_node *node,
                       cmark_node_type child_type)
{
    if (node->type != MP_NODE_HIGHLIGHT)
        return 0;
    return CMARK_NODE_TYPE_INLINE_P(child_type);
}

static void html_render(cmark_syntax_extension *extension,
                        cmark_html_renderer *renderer, cmark_node *node,
                        cmark_event_type ev_type, int options)
{
    if (ev_type == CMARK_EVENT_ENTER)
        cmark_strbuf_puts(renderer->html, "<mark>");
    else
        cmark_strbuf_puts(renderer->html, "</mark>");
}

static void commonmark_render(cmark_syntax_extension *extension,
                              cmark_renderer *renderer, cmark_node *node,
                              cmark_event_type ev_type, int options)
{
    renderer->out(renderer, node, "==", false, LITERAL);
}

cmark_syntax_extension *mp_create_highlight_extension(void)
{
    cmark_syntax_extension *ext = cmark_syntax_extension_new("highlight");
    cmark_syntax_extension_set_get_type_string_func(ext, get_type_string);
    cmark_syntax_extension_set_can_contain_func(ext, can_contain);
    cmark_syntax_extension_set_html_render_func(ext, html_render);
    cmark_syntax_extension_set_commonmark_render_func(ext, commonmark_render);
    MP_NODE_HIGHLIGHT = cmark_syntax_extension_add_node(1);

    cmark_syntax_extension_set_match_inline_func(ext, match);
    cmark_syntax_extension_set_inline_from_delim_func(ext, insert);

    cmark_mem *mem = cmark_get_default_mem_allocator();
    cmark_llist *chars = cmark_llist_append(mem, NULL, (void *)'=');
    cmark_syntax_extension_set_special_inline_chars(ext, chars);
    cmark_syntax_extension_set_emphasis(ext, 1);
    return ext;
}
