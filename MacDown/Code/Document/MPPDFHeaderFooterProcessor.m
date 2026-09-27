//
//  MPPDFHeaderFooterProcessor.m
//  MacDown
//
//  Post-processes a PDF file to overlay header/footer text on each page.
//

#import "MPPDFHeaderFooterProcessor.h"
#import <Cocoa/Cocoa.h>
#import "MPPreferences.h"

static NSString * const kMPPDFErrorDomain = @"com.uranusjr.macdown.pdf";

// Layout constants (in points).
static const CGFloat kMPPDFMarginInset = 36.0;        // 0.5 inch from page edge
static const CGFloat kMPPDFHeaderYFromTop = 24.0;      // header baseline from top
static const CGFloat kMPPDFFooterYFromBottom = 14.0;    // footer baseline from bottom


@implementation MPPDFHeaderFooterProcessor

#pragma mark - Public

- (BOOL)processFileAtURL:(NSURL *)url
           documentTitle:(NSString *)title
             preferences:(MPPreferences *)preferences
                   error:(NSError **)error
{
    BOOL hasMargins = (preferences.htmlPrintPaddingTop > 0 ||
                        preferences.htmlPrintPaddingBottom > 0 ||
                        preferences.htmlPrintPaddingLeft > 0 ||
                        preferences.htmlPrintPaddingRight > 0);
    BOOL hasHeaderFooter = (preferences.pdfHeaderFooterEnabled &&
                            [self hasAnyConfiguredZonesInPreferences:preferences]);
    if (!hasMargins && !hasHeaderFooter)
        return YES;

    CGPDFDocumentRef srcDoc = CGPDFDocumentCreateWithURL((__bridge CFURLRef)url);
    if (!srcDoc)
    {
        if (error)
            *error = [NSError errorWithDomain:kMPPDFErrorDomain code:1
                                     userInfo:@{NSLocalizedDescriptionKey:
                          @"Could not open PDF for header/footer processing."}];
        return NO;
    }

    size_t pageCount = CGPDFDocumentGetNumberOfPages(srcDoc);
    if (pageCount == 0)
    {
        CGPDFDocumentRelease(srcDoc);
        return YES;
    }

    NSString *timestamp = [self formattedTimestamp];

    // Write to a temp file first, then atomically replace.
    NSString *tempPath = [NSTemporaryDirectory()
        stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    tempPath = [tempPath stringByAppendingPathExtension:@"pdf"];
    NSURL *tempURL = [NSURL fileURLWithPath:tempPath];

    CGContextRef pdfContext = CGPDFContextCreateWithURL(
        (__bridge CFURLRef)tempURL, NULL, NULL);
    if (!pdfContext)
    {
        CGPDFDocumentRelease(srcDoc);
        if (error)
            *error = [NSError errorWithDomain:kMPPDFErrorDomain code:2
                                     userInfo:@{NSLocalizedDescriptionKey:
                          @"Could not create PDF context for writing."}];
        return NO;
    }

    // Content margin insets from preferences.
    CGFloat padTop    = preferences.htmlPrintPaddingTop;
    CGFloat padBottom = preferences.htmlPrintPaddingBottom;
    CGFloat padLeft   = preferences.htmlPrintPaddingLeft;
    CGFloat padRight  = preferences.htmlPrintPaddingRight;
    BOOL applyMargins = (padTop > 0 || padBottom > 0 ||
                         padLeft > 0 || padRight > 0);

    // Full letter-size page for the output.
    CGFloat letterW = 612.0;
    CGFloat letterH = 792.0;
    CGRect letterBox = CGRectMake(0, 0, letterW, letterH);

    for (size_t i = 1; i <= pageCount; i++)
    {
        CGPDFPageRef srcPage = CGPDFDocumentGetPage(srcDoc, i);
        CGRect mediaBox = CGPDFPageGetBoxRect(srcPage, kCGPDFMediaBox);

        // Output page is always full letter size when margins are active.
        CGRect outputBox = applyMargins ? letterBox : mediaBox;
        CGContextBeginPage(pdfContext, &outputBox);

        // Draw original page content, scaled to fit within margins.
        CGContextSaveGState(pdfContext);
        if (applyMargins)
        {
            CGFloat contentW = letterW - padLeft - padRight;
            CGFloat contentH = letterH - padTop - padBottom;

            // WebKit renders at full page size (ignores NSPrintInfo
            // paper size and margins).  Scale uniformly so the source
            // page fits entirely inside the content rectangle.
            CGFloat srcW = mediaBox.size.width;
            CGFloat srcH = mediaBox.size.height;
            CGFloat scaleX = contentW / srcW;
            CGFloat scaleY = contentH / srcH;
            CGFloat scale = MIN(scaleX, scaleY);

            // Position the scaled page so its top-left aligns with the
            // top-left of the content area.  In PDF coords (origin at
            // bottom-left), the content top is at (letterH - padTop).
            // The scaled page height is srcH * scale; its top after
            // translation sits at (yOffset + srcH * scale).
            CGFloat yOffset = letterH - padTop - srcH * scale;

            // Center horizontally within the content area if the
            // scaled width is narrower than contentW.
            CGFloat scaledW = srcW * scale;
            CGFloat xOffset = padLeft + (contentW - scaledW) / 2.0;

            CGContextTranslateCTM(pdfContext, xOffset, yOffset);
            CGContextScaleCTM(pdfContext, scale, scale);
        }
        CGContextDrawPDFPage(pdfContext, srcPage);
        CGContextRestoreGState(pdfContext);

        // Draw header/footer overlay (skip first page if requested).
        BOOL skipThisPage = (i == 1 && preferences.pdfDifferentFirstPage);
        if (!skipThisPage && preferences.pdfHeaderFooterEnabled)
        {
            [self drawHeaderFooterInContext:pdfContext
                                pageBounds:outputBox
                                 pageIndex:(i - 1)
                                 pageCount:pageCount
                             documentTitle:title
                                 timestamp:timestamp
                               preferences:preferences];
        }

        CGContextEndPage(pdfContext);
    }

    CGPDFContextClose(pdfContext);
    CGContextRelease(pdfContext);
    CGPDFDocumentRelease(srcDoc);

    // Replace original with processed file.
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm removeItemAtURL:url error:error])
    {
        [fm removeItemAtURL:tempURL error:nil];
        return NO;
    }
    if (![fm moveItemAtURL:tempURL toURL:url error:error])
        return NO;

    return YES;
}


#pragma mark - Drawing

- (void)drawHeaderFooterInContext:(CGContextRef)ctx
                       pageBounds:(CGRect)bounds
                        pageIndex:(NSUInteger)pageIndex
                        pageCount:(size_t)pageCount
                    documentTitle:(NSString *)title
                        timestamp:(NSString *)timestamp
                      preferences:(MPPreferences *)preferences
{
    CGFloat fontSize = preferences.pdfHeaderFooterFontSize;
    if (fontSize <= 0)
        fontSize = 9.0;

    NSFont *font = [NSFont systemFontOfSize:fontSize];
    NSDictionary *attrs = @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: [NSColor colorWithWhite:0.3 alpha:1.0],
    };

    CGFloat leftX = bounds.origin.x + kMPPDFMarginInset;
    CGFloat rightX = bounds.origin.x + bounds.size.width - kMPPDFMarginInset;
    CGFloat centerX = bounds.origin.x + bounds.size.width / 2.0;
    CGFloat headerY = bounds.origin.y + bounds.size.height - kMPPDFHeaderYFromTop;
    CGFloat footerY = bounds.origin.y + kMPPDFFooterYFromBottom;

    // Bridge CG context to NSGraphicsContext for NSString drawing.
    NSGraphicsContext *nsCtx =
        [NSGraphicsContext graphicsContextWithCGContext:ctx flipped:NO];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:nsCtx];

    // --- Header ---
    [self drawText:[self textForZoneType:preferences.pdfHeaderLeftType
                              customText:preferences.pdfHeaderLeftCustomText
                               pageIndex:pageIndex pageCount:pageCount
                           documentTitle:title timestamp:timestamp]
          atPointX:leftX y:headerY alignment:NSTextAlignmentLeft
        attributes:attrs];

    [self drawText:[self textForZoneType:preferences.pdfHeaderCenterType
                              customText:preferences.pdfHeaderCenterCustomText
                               pageIndex:pageIndex pageCount:pageCount
                           documentTitle:title timestamp:timestamp]
          atPointX:centerX y:headerY alignment:NSTextAlignmentCenter
        attributes:attrs];

    [self drawText:[self textForZoneType:preferences.pdfHeaderRightType
                              customText:preferences.pdfHeaderRightCustomText
                               pageIndex:pageIndex pageCount:pageCount
                           documentTitle:title timestamp:timestamp]
          atPointX:rightX y:headerY alignment:NSTextAlignmentRight
        attributes:attrs];

    // --- Footer ---
    [self drawText:[self textForZoneType:preferences.pdfFooterLeftType
                              customText:preferences.pdfFooterLeftCustomText
                               pageIndex:pageIndex pageCount:pageCount
                           documentTitle:title timestamp:timestamp]
          atPointX:leftX y:footerY alignment:NSTextAlignmentLeft
        attributes:attrs];

    [self drawText:[self textForZoneType:preferences.pdfFooterCenterType
                              customText:preferences.pdfFooterCenterCustomText
                               pageIndex:pageIndex pageCount:pageCount
                           documentTitle:title timestamp:timestamp]
          atPointX:centerX y:footerY alignment:NSTextAlignmentCenter
        attributes:attrs];

    [self drawText:[self textForZoneType:preferences.pdfFooterRightType
                              customText:preferences.pdfFooterRightCustomText
                               pageIndex:pageIndex pageCount:pageCount
                           documentTitle:title timestamp:timestamp]
          atPointX:rightX y:footerY alignment:NSTextAlignmentRight
        attributes:attrs];

    [NSGraphicsContext restoreGraphicsState];
}

- (void)drawText:(NSString *)text
        atPointX:(CGFloat)x y:(CGFloat)y
       alignment:(NSTextAlignment)alignment
      attributes:(NSDictionary *)attrs
{
    if (!text.length)
        return;

    NSSize size = [text sizeWithAttributes:attrs];

    CGFloat drawX = x;
    if (alignment == NSTextAlignmentCenter)
        drawX = x - size.width / 2.0;
    else if (alignment == NSTextAlignmentRight)
        drawX = x - size.width;

    [text drawAtPoint:NSMakePoint(drawX, y) withAttributes:attrs];
}


#pragma mark - Text Resolution

- (NSString *)textForZoneType:(MPPDFZoneContentType)type
                   customText:(NSString *)customText
                    pageIndex:(NSUInteger)pageIndex
                    pageCount:(size_t)pageCount
                documentTitle:(NSString *)title
                    timestamp:(NSString *)timestamp
{
    switch (type)
    {
        case MPPDFZoneContentNone:
            return nil;
        case MPPDFZoneContentDocumentName:
            return title ?: @"";
        case MPPDFZoneContentTimestamp:
            return timestamp;
        case MPPDFZoneContentPageNumber:
            return [NSString stringWithFormat:@"%lu",
                    (unsigned long)(pageIndex + 1)];
        case MPPDFZoneContentPageCount:
            return [NSString stringWithFormat:@"%lu",
                    (unsigned long)pageCount];
        case MPPDFZoneContentPageLabel:
            return [NSString stringWithFormat:
                    NSLocalizedString(@"Page %lu of %lu",
                                      @"PDF page label format"),
                    (unsigned long)(pageIndex + 1),
                    (unsigned long)pageCount];
        case MPPDFZoneContentCustomText:
            return customText ?: @"";
        default:
            return nil;
    }
}


#pragma mark - Helpers

- (NSString *)formattedTimestamp
{
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateStyle = NSDateFormatterMediumStyle;
    formatter.timeStyle = NSDateFormatterShortStyle;
    return [formatter stringFromDate:[NSDate date]];
}

- (BOOL)hasAnyConfiguredZonesInPreferences:(MPPreferences *)prefs
{
    return (prefs.pdfHeaderLeftType   != MPPDFZoneContentNone ||
            prefs.pdfHeaderCenterType != MPPDFZoneContentNone ||
            prefs.pdfHeaderRightType  != MPPDFZoneContentNone ||
            prefs.pdfFooterLeftType   != MPPDFZoneContentNone ||
            prefs.pdfFooterCenterType != MPPDFZoneContentNone ||
            prefs.pdfFooterRightType  != MPPDFZoneContentNone);
}

@end
