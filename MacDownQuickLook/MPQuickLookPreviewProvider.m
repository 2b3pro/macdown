//
//  MPQuickLookPreviewProvider.m
//  MacDownQuickLook
//
//  Data-based Quick Look preview (macOS 12+). Produces a self-contained HTML
//  document: Markdown body rendered by MacDown's renderer (MPMarkdown),
//  wrapped in the user's selected MacDown style. Quick Look does not execute
//  JavaScript in HTML previews, so Prism, MathJax and Mermaid are not included.
//

#import "MPQuickLookPreviewProvider.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <pwd.h>
#import <unistd.h>
#import "MPMarkdown.h"


// Preferences domain of the containing app. Mirrors MPPreferences keys.
#ifdef DEBUG
static NSString * const kMPAppDefaultsDomain = @"com.2b3pro.macdown-debug";
#else
static NSString * const kMPAppDefaultsDomain = @"com.2b3pro.macdown";
#endif
static NSString * const kMPDefaultStyleName = @"GitHub2";
static NSString * const kMPStylesDirectoryName = @"Styles";
static NSString * const kMPStyleFileExtension = @"css";


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

// Mirrors -[MPPreferences extensionFlags] in MPDocument.m.
static unsigned int MPExtensionFlags(void)
{
    unsigned int flags = 0;
    if (MPPreferenceBool(@"extensionAutolink", NO))
        flags |= MPMarkdownExtensionAutolink;
    if (MPPreferenceBool(@"extensionFootnotes", YES))
        flags |= MPMarkdownExtensionFootnotes;
    if (MPPreferenceBool(@"extensionHighlight", NO))
        flags |= MPMarkdownExtensionHighlight;
    if (MPPreferenceBool(@"extensionStrikethough", NO))
        flags |= MPMarkdownExtensionStrikethrough;
    if (MPPreferenceBool(@"extensionSuperscript", NO))
        flags |= MPMarkdownExtensionSuperscript;
    if (MPPreferenceBool(@"extensionTables", YES))
        flags |= MPMarkdownExtensionTables;
    if (MPPreferenceBool(@"extensionUnderline", NO))
        flags |= MPMarkdownExtensionUnderline;
    if (MPPreferenceBool(@"htmlMathJax", NO))
        flags |= MPMarkdownExtensionMath;
    if (MPPreferenceBool(@"htmlMathJaxInlineDollar", NO))
        flags |= MPMarkdownExtensionMathInlineDollar;
    return flags;
}

static unsigned int MPRendererFlags(void)
{
    unsigned int flags = 0;
    if (MPPreferenceBool(@"htmlTaskList", NO))
        flags |= MPMarkdownRenderTaskList;
    if (MPPreferenceBool(@"htmlHardWrap", NO))
        flags |= MPMarkdownRenderHardWrap;
    if (MPPreferenceBool(@"extensionSmartyPants", NO))
        flags |= MPMarkdownRenderSmartyPants;
    if (MPPreferenceBool(@"htmlRendersTOC", NO))
        flags |= MPMarkdownRenderTOC;
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

static NSString *MPRenderMarkdownBody(NSString *markdown)
{
    if (MPPreferenceBool(@"htmlDetectFrontMatter", YES))
        markdown = MPStripFrontMatter(markdown);

    MPMarkdownOptions options = {0};
    options.extensions = MPExtensionFlags();
    options.renderFlags = MPRendererFlags();

    NSData *input = [markdown dataUsingEncoding:NSUTF8StringEncoding];
    char *html = MPMarkdownRenderHTML(input.bytes, input.length, &options);
    NSString *result = html ? [NSString stringWithUTF8String:html] : nil;
    free(html);
    return result ?: @"";
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
