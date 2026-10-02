//
//  MPMarkdownTests.m
//  MacDownTests
//
//  Rendering tests for MPMarkdown (cmark-gfm plus MacDown's extensions).
//

#import <XCTest/XCTest.h>
#import "MPMarkdown.h"

static const unsigned int MPAllExtensions =
    MPMarkdownExtensionTables | MPMarkdownExtensionFootnotes
    | MPMarkdownExtensionAutolink | MPMarkdownExtensionStrikethrough
    | MPMarkdownExtensionUnderline | MPMarkdownExtensionHighlight
    | MPMarkdownExtensionSuperscript | MPMarkdownExtensionMath;


static char *MPTestLanguageCallback(const char *language, void *context)
{
    if (strcmp(language, "py") == 0)
        return strdup("python");
    return NULL;
}


@interface MPMarkdownTests : XCTestCase
@end


@implementation MPMarkdownTests

- (NSString *)render:(NSString *)markdown
          extensions:(unsigned int)extensions
               flags:(unsigned int)flags
{
    MPMarkdownOptions options = {0};
    options.extensions = extensions;
    options.renderFlags = flags;
    options.languageCallback = MPTestLanguageCallback;
    NSData *data = [markdown dataUsingEncoding:NSUTF8StringEncoding];
    char *html = MPMarkdownRenderHTML(data.bytes, data.length, &options);
    NSString *result = [NSString stringWithUTF8String:html];
    free(html);
    return result;
}

- (NSString *)render:(NSString *)markdown
{
    return [self render:markdown extensions:MPAllExtensions flags:0];
}

- (void)assertHTML:(NSString *)html contains:(NSString *)fragment
{
    XCTAssertTrue([html containsString:fragment],
                  @"Expected %@ in:\n%@", fragment, html);
}

- (void)assertHTML:(NSString *)html lacks:(NSString *)fragment
{
    XCTAssertFalse([html containsString:fragment],
                   @"Did not expect %@ in:\n%@", fragment, html);
}

#pragma mark - Inline extensions

- (void)testUnderlineHighlightSuperscript
{
    NSString *html = [self render:
        @"_under_ *em* __strong__ ==mark== x^2 and ^(two words)"];
    [self assertHTML:html contains:@"<u>under</u>"];
    [self assertHTML:html contains:@"<em>em</em>"];
    [self assertHTML:html contains:@"<strong>strong</strong>"];
    [self assertHTML:html contains:@"<mark>mark</mark>"];
    [self assertHTML:html contains:@"x<sup>2</sup>"];
    [self assertHTML:html contains:@"<sup>two words</sup>"];
}

- (void)testExtensionsOffFallBackToCommonMark
{
    NSString *html = [self render:@"_under_ ==mark== x^2"
                       extensions:0 flags:0];
    [self assertHTML:html contains:@"<em>under</em>"];
    [self assertHTML:html contains:@"==mark=="];
    [self assertHTML:html contains:@"x^2"];
}

- (void)testSuperscriptLeavesFootnotesAlone
{
    NSString *html = [self render:@"Text[^1]\n\n[^1]: Note."];
    [self assertHTML:html contains:@"footnote-ref"];
    [self assertHTML:html lacks:@"<sup>1]"];
}

#pragma mark - Math

- (void)testMathIsNotParsedAsMarkdown
{
    NSString *html = [self render:@"Inline \\\\(a_1 * b_2\\\\) here."];
    [self assertHTML:html contains:@"\\(a_1 * b_2\\)"];
    [self assertHTML:html lacks:@"<em>"];
}

- (void)testDisplayMathAloneInParagraph
{
    NSString *html = [self render:@"$$\nx_1 < y_2\n$$"];
    [self assertHTML:html contains:@"\\[\nx_1 &lt; y_2\n\\]"];
}

- (void)testDoubleDollarInTextIsInline
{
    NSString *html = [self render:@"So $$E = mc^2$$ holds."];
    [self assertHTML:html contains:@"\\(E = mc^2\\)"];
}

- (void)testSingleDollarNeedsInlineDollarOption
{
    NSString *off = [self render:@"cost $x_1$ here"];
    [self assertHTML:off lacks:@"\\("];

    unsigned int extensions =
        MPAllExtensions | MPMarkdownExtensionMathInlineDollar;
    NSString *on = [self render:@"cost $x_1$ here"
                     extensions:extensions flags:0];
    [self assertHTML:on contains:@"\\(x_1\\)"];
}

- (void)testEscapedDollarIsText
{
    NSString *html = [self render:@"Price \\$5 and \\$6"
                       extensions:MPAllExtensions
                                  | MPMarkdownExtensionMathInlineDollar
                            flags:0];
    [self assertHTML:html contains:@"Price $5 and $6"];
}

#pragma mark - MacDown output

- (void)testHeadingIdsAndTOC
{
    NSString *html = [self render:@"[TOC]\n\n# One\n\n## [Two](http://x)"
                       extensions:MPAllExtensions
                            flags:MPMarkdownRenderTOC];
    [self assertHTML:html contains:@"<h1 id=\"toc_0\">One</h1>"];
    [self assertHTML:html contains:@"<h2 id=\"toc_1\">"];
    [self assertHTML:html contains:@"<ul class=\"toc\">"];
    [self assertHTML:html contains:@"<a href=\"#toc_1\">Two</a>"];
    [self assertHTML:html lacks:@"[TOC]"];
}

- (void)testCodeBlockMarkup
{
    NSString *html = [self render:@"```py:main.py\nprint(\"<x>\")\n```"
                       extensions:MPAllExtensions
                            flags:MPMarkdownRenderLineNumbers
                                  | MPMarkdownRenderCodeBlockInformation];
    [self assertHTML:html contains:
        @"<div><pre class=\"line-numbers\" data-information=\"main.py\">"
        @"<code class=\"language-python\">print(&quot;&lt;x&gt;&quot;)"
        @"</code></pre></div>"];
}

- (void)testIndentedCodeHasNoLanguage
{
    NSString *html = [self render:@"    plain"];
    [self assertHTML:html contains:@"<code class=\"language-none\">plain"];
}

- (void)testTaskList
{
    NSString *html = [self render:@"- [ ] todo\n- [x] done"
                       extensions:MPAllExtensions
                            flags:MPMarkdownRenderTaskList];
    [self assertHTML:html contains:
        @"<li class=\"task-list-item\"><input type=\"checkbox\"> todo</li>"];
    [self assertHTML:html contains:
        @"<input type=\"checkbox\" checked> done"];

    NSString *off = [self render:@"- [ ] todo"];
    [self assertHTML:off contains:@"<li>[ ] todo</li>"];
}

- (void)testRawHTMLPassesThrough
{
    NSString *html = [self render:@"<div class=\"x\">raw</div>"];
    [self assertHTML:html contains:@"<div class=\"x\">raw</div>"];
}

@end
