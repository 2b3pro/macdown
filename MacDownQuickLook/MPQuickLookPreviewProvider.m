//
//  MPQuickLookPreviewProvider.m
//  MacDownQuickLook
//
//  Data-based Quick Look preview (macOS 12+). Produces a self-contained HTML
//  document: Markdown body rendered by Hoedown with MacDown's renderer patches,
//  wrapped in the user's selected MacDown style. Quick Look does not execute
//  JavaScript in HTML previews, so Prism, MathJax and Mermaid are not included.
//

#import "MPQuickLookPreviewProvider.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <hoedown/document.h>
#import <hoedown/html.h>
#import <pwd.h>
#import <unistd.h>
#import "hoedown_html_patch.h"


// Preferences domain of the containing app. Mirrors MPPreferences keys.
static NSString * const kMPAppDefaultsDomain = @"com.uranusjr.macdown";
static NSString * const kMPDefaultStyleName = @"GitHub2";
static NSString * const kMPStylesDirectoryName = @"Styles";
static NSString * const kMPStyleFileExtension = @"css";
static size_t kMPRendererNestingLevel = SIZE_MAX;
static int kMPRendererTOCLevel = 6;  // h1 to h6.


#pragma mark - Preferences

static id MPPreferenceValue(NSString *key)
{
    CFPropertyListRef value = CFPreferencesCopyAppValue(
        (__bridge CFStringRef)key, (__bridge CFStringRef)kMPAppDefaultsDomain);
    return CFBridgingRelease(value);
}

// MacDown writes explicit values for every preference on first launch. If a
// key is absent (MacDown never launched), fall back to the same defaults
// MPPreferences applies in -loadDefaultPreferences.
static BOOL MPPreferenceBool(NSString *key, BOOL fallback)
{
    id value = MPPreferenceValue(key);
    if ([value respondsToSelector:@selector(boolValue)])
        return [value boolValue];
    return fallback;
}

static int MPExtensionFlags(void)
{
    int flags = 0;
    if (MPPreferenceBool(@"extensionAutolink", NO))
        flags |= HOEDOWN_EXT_AUTOLINK;
    if (MPPreferenceBool(@"extensionFencedCode", YES))
        flags |= HOEDOWN_EXT_FENCED_CODE;
    if (MPPreferenceBool(@"extensionFootnotes", YES))
        flags |= HOEDOWN_EXT_FOOTNOTES;
    if (MPPreferenceBool(@"extensionHighlight", NO))
        flags |= HOEDOWN_EXT_HIGHLIGHT;
    if (!MPPreferenceBool(@"extensionIntraEmphasis", YES))
        flags |= HOEDOWN_EXT_NO_INTRA_EMPHASIS;
    if (MPPreferenceBool(@"extensionQuote", NO))
        flags |= HOEDOWN_EXT_QUOTE;
    if (MPPreferenceBool(@"extensionStrikethough", NO))
        flags |= HOEDOWN_EXT_STRIKETHROUGH;
    if (MPPreferenceBool(@"extensionSuperscript", NO))
        flags |= HOEDOWN_EXT_SUPERSCRIPT;
    if (MPPreferenceBool(@"extensionTables", YES))
        flags |= HOEDOWN_EXT_TABLES;
    if (MPPreferenceBool(@"extensionUnderline", NO))
        flags |= HOEDOWN_EXT_UNDERLINE;
    if (MPPreferenceBool(@"htmlMathJax", NO))
        flags |= HOEDOWN_EXT_MATH;
    if (MPPreferenceBool(@"htmlMathJaxInlineDollar", NO))
        flags |= HOEDOWN_EXT_MATH_EXPLICIT;
    return flags;
}

static int MPRendererFlags(void)
{
    int flags = 0;
    if (MPPreferenceBool(@"htmlTaskList", NO))
        flags |= HOEDOWN_HTML_USE_TASK_LIST;
    if (MPPreferenceBool(@"htmlHardWrap", NO))
        flags |= HOEDOWN_HTML_HARD_WRAP;
    // Line numbers and code block accessories need Prism (JavaScript), which
    // Quick Look does not run, so those renderer flags are intentionally off.
    return flags;
}


#pragma mark - Styles

// Real home directory, not the sandbox container.
static NSString *MPRealHomeDirectory(void)
{
    struct passwd *pw = getpwuid(getuid());
    if (pw && pw->pw_dir)
        return [NSString stringWithUTF8String:pw->pw_dir];
    return NSHomeDirectory();
}

static NSString *MPStyleCSSNamed(NSString *name)
{
    if (!name.length)
        return nil;
    if (![name.pathExtension isEqualToString:kMPStyleFileExtension])
        name = [name stringByAppendingPathExtension:kMPStyleFileExtension];

    NSMutableArray<NSString *> *candidates = [NSMutableArray array];

    // 1. User's MacDown data directory (where custom styles live).
    NSString *appSupport = [NSString pathWithComponents:@[
        MPRealHomeDirectory(), @"Library", @"Application Support", @"MacDown",
        kMPStylesDirectoryName, name]];
    [candidates addObject:appSupport];

    // 2. Styles bundled with this extension.
    NSString *bundled = [[NSBundle bundleForClass:[MPQuickLookPreviewProvider class]]
        pathForResource:name.stringByDeletingPathExtension
                 ofType:kMPStyleFileExtension
            inDirectory:kMPStylesDirectoryName];
    if (bundled)
        [candidates addObject:bundled];

    for (NSString *path in candidates)
    {
        NSString *css = [NSString stringWithContentsOfFile:path
                                                 encoding:NSUTF8StringEncoding
                                                    error:NULL];
        if (css.length)
            return css;
    }
    return nil;
}

static NSString *MPPreferredStyleCSS(void)
{
    id name = MPPreferenceValue(@"htmlStyleName");
    NSString *css = nil;
    if ([name isKindOfClass:[NSString class]])
        css = MPStyleCSSNamed(name);
    if (!css)
        css = MPStyleCSSNamed(kMPDefaultStyleName);
    return css ?: @"";
}


#pragma mark - Markdown

// Mirrors -[NSString frontMatter:] in MacDown, minus YAML validation.
static NSString *MPStripFrontMatter(NSString *markdown)
{
    static NSRegularExpression *regex = nil;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        NSString *pattern = @"^-{3}[\r\n]+(.*?[\r\n]+)((?:-{3})|(?:\\.{3}))";
        regex = [NSRegularExpression
            regularExpressionWithPattern:pattern
                                 options:NSRegularExpressionDotMatchesLineSeparators
                                   error:NULL];
    });
    NSTextCheckingResult *result =
        [regex firstMatchInString:markdown options:0
                            range:NSMakeRange(0, markdown.length)];
    if (!result)
        return markdown;
    return [markdown substringFromIndex:[result rangeAtIndex:0].length];
}

static NSString *MPStringFromHoedownBuffer(hoedown_buffer *ob)
{
    NSString *s = [[NSString alloc] initWithBytes:ob->data length:ob->size
                                         encoding:NSUTF8StringEncoding];
    return s ?: @"";
}

// Mirrors MPHTMLFromMarkdown / MPCreateHTMLRenderer in MPRenderer.m.
static NSString *MPRenderMarkdownBody(NSString *markdown)
{
    int extensions = MPExtensionFlags();
    BOOL smartypants = MPPreferenceBool(@"extensionSmartyPants", NO);
    BOOL renderTOC = MPPreferenceBool(@"htmlRendersTOC", NO);
    if (MPPreferenceBool(@"htmlDetectFrontMatter", YES))
        markdown = MPStripFrontMatter(markdown);

    hoedown_renderer *htmlRenderer =
        hoedown_html_renderer_new(MPRendererFlags(), kMPRendererTOCLevel);
    htmlRenderer->blockcode = hoedown_patch_render_blockcode;
    htmlRenderer->listitem = hoedown_patch_render_listitem;
    hoedown_html_renderer_state_extra *extra =
        hoedown_malloc(sizeof(hoedown_html_renderer_state_extra));
    extra->language_addition = NULL;  // No Prism language collection here.
    extra->owner = NULL;
    ((hoedown_html_renderer_state *)htmlRenderer->opaque)->opaque = extra;

    NSData *input = [markdown dataUsingEncoding:NSUTF8StringEncoding];
    hoedown_document *document = hoedown_document_new(
        htmlRenderer, extensions, kMPRendererNestingLevel);
    hoedown_buffer *ob = hoedown_buffer_new(64);
    hoedown_document_render(document, ob, input.bytes, input.length);
    if (smartypants)
    {
        hoedown_buffer *ib = ob;
        ob = hoedown_buffer_new(64);
        hoedown_html_smartypants(ob, ib->data, ib->size);
        hoedown_buffer_free(ib);
    }
    NSString *result = MPStringFromHoedownBuffer(ob);
    hoedown_document_free(document);
    hoedown_buffer_free(ob);
    free(extra);
    hoedown_html_renderer_free(htmlRenderer);

    if (renderTOC)
    {
        hoedown_renderer *tocRenderer =
            hoedown_html_toc_renderer_new(kMPRendererTOCLevel);
        tocRenderer->header = hoedown_patch_render_toc_header;
        document = hoedown_document_new(
            tocRenderer, extensions, kMPRendererNestingLevel);
        ob = hoedown_buffer_new(64);
        hoedown_document_render(document, ob, input.bytes, input.length);
        NSString *toc = MPStringFromHoedownBuffer(ob);
        hoedown_document_free(document);
        hoedown_buffer_free(ob);
        hoedown_html_renderer_free(tocRenderer);

        NSRegularExpression *tocRegex = [NSRegularExpression
            regularExpressionWithPattern:@"<p.*?>\\s*\\[TOC\\]\\s*</p>"
                                 options:NSRegularExpressionCaseInsensitive
                                   error:NULL];
        result = [tocRegex
            stringByReplacingMatchesInString:result options:0
                                       range:NSMakeRange(0, result.length)
                                withTemplate:[NSRegularExpression
                                    escapedTemplateForString:toc]];
    }
    return result;
}

static NSString *MPEscapeHTML(NSString *s)
{
    NSMutableString *m = [s mutableCopy];
    [m replaceOccurrencesOfString:@"&" withString:@"&amp;" options:0
                            range:NSMakeRange(0, m.length)];
    [m replaceOccurrencesOfString:@"<" withString:@"&lt;" options:0
                            range:NSMakeRange(0, m.length)];
    [m replaceOccurrencesOfString:@">" withString:@"&gt;" options:0
                            range:NSMakeRange(0, m.length)];
    return m;
}

// Mirrors Templates/Default.handlebars with the stylesheet embedded.
static NSString *MPHTMLDocument(NSString *title, NSString *css, NSString *body)
{
    return [NSString stringWithFormat:
        @"<!DOCTYPE html>\n<html>\n<head>\n"
        @"<meta charset=\"utf-8\">\n"
        @"<meta name=\"viewport\" content=\"width=device-width, "
        @"initial-scale=1.0, user-scalable=yes\">\n"
        @"<title>%@</title>\n"
        @"<style>\n%@\n</style>\n"
        @"</head>\n<body>\n%@\n</body>\n</html>\n",
        MPEscapeHTML(title), css, body];
}


#pragma mark - MPQuickLookPreviewProvider

@implementation MPQuickLookPreviewProvider

- (void)providePreviewForFileRequest:(QLFilePreviewRequest *)request
                   completionHandler:(void (^)(QLPreviewReply * _Nullable,
                                               NSError * _Nullable))handler
{
    NSURL *fileURL = request.fileURL;
    QLPreviewReply *reply = [[QLPreviewReply alloc]
        initWithDataOfContentType:UTTypeHTML
                      contentSize:CGSizeMake(800, 800)
                dataCreationBlock:^NSData *(QLPreviewReply *reply,
                                            NSError **error) {
        NSStringEncoding encoding = 0;
        NSString *markdown = [NSString stringWithContentsOfURL:fileURL
                                                  usedEncoding:&encoding
                                                         error:NULL];
        if (!markdown)
        {
            markdown = [NSString stringWithContentsOfURL:fileURL
                                                encoding:NSUTF8StringEncoding
                                                   error:error];
        }
        if (!markdown)
        {
            NSLog(@"[MacDownQuickLook] could not read file: %@",
                  error ? *error : nil);
            return nil;
        }

        NSString *title = fileURL.lastPathComponent.stringByDeletingPathExtension;
        NSString *body = MPRenderMarkdownBody(markdown);
        NSString *html = MPHTMLDocument(title ?: @"", MPPreferredStyleCSS(), body);
        reply.stringEncoding = NSUTF8StringEncoding;
        return [html dataUsingEncoding:NSUTF8StringEncoding];
    }];
    handler(reply, nil);
}

@end
