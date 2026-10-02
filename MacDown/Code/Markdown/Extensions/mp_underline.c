//
//  mp_underline.c
//  MacDown
//
//  _text_ (single underscore) renders as <u> instead of <em>. *text* is still
//  emphasis, and __text__ is still strong. CommonMark parses underscores in
//  the core, so cmark-gfm is patched to flag single-underscore emphasis (see
//  Dependency/cmark-gfm/MACDOWN.md); this extension converts flagged nodes
//  after parsing.
//

#include <cmark-gfm/node.h>
#include <cmark-gfm/render.h>
#include <cmark-gfm/html.h>
#include "mp_extensions.h"

static cmark_node_type MP_NODE_UNDERLINE;

static cmark_node *postprocess(cmark_syntax_extension *self,
                               cmark_parser *parser, cmark_node *root)
{
    cmark_iter *iter = cmark_iter_new(root);
    cmark_event_type ev;
    while ((ev = cmark_iter_next(iter)) != CMARK_EVENT_DONE)
    {
        cmark_node *node = cmark_iter_get_node(iter);
        if (ev != CMARK_EVENT_ENTER || node->type != CMARK_NODE_EMPH)
            continue;
        if (!(node->flags & CMARK_NODE__UNDERSCORE_EMPH))
            continue;
        if (cmark_node_set_type(node, MP_NODE_UNDERLINE))
            cmark_node_set_syntax_extension(node, self);
    }
    cmark_iter_free(iter);
    return root;
}

static const char *get_type_string(cmark_syntax_extension *extension,
                                   cmark_node *node)
{
    return node->type == MP_NODE_UNDERLINE ? "underline" : "<unknown>";
}

static int can_contain(cmark_syntax_extension *extension, cmark_node *node,
                       cmark_node_type child_type)
{
    if (node->type != MP_NODE_UNDERLINE)
        return 0;
    return CMARK_NODE_TYPE_INLINE_P(child_type);
}

static void html_render(cmark_syntax_extension *extension,
                        cmark_html_renderer *renderer, cmark_node *node,
                        cmark_event_type ev_type, int options)
{
    if (ev_type == CMARK_EVENT_ENTER)
        cmark_strbuf_puts(renderer->html, "<u>");
    else
        cmark_strbuf_puts(renderer->html, "</u>");
}

cmark_syntax_extension *mp_create_underline_extension(void)
{
    cmark_syntax_extension *ext = cmark_syntax_extension_new("underline");
    cmark_syntax_extension_set_get_type_string_func(ext, get_type_string);
    cmark_syntax_extension_set_can_contain_func(ext, can_contain);
    cmark_syntax_extension_set_html_render_func(ext, html_render);
    cmark_syntax_extension_set_postprocess_func(ext, postprocess);
    MP_NODE_UNDERLINE = cmark_syntax_extension_add_node(1);
    return ext;
}
