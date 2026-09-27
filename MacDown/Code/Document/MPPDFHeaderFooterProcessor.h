//
//  MPPDFHeaderFooterProcessor.h
//  MacDown
//
//  Post-processes a PDF file to overlay header/footer text on each page.
//

#import <Foundation/Foundation.h>
@class MPPreferences;

typedef NS_ENUM(NSInteger, MPPDFZoneContentType) {
    MPPDFZoneContentNone = 0,
    MPPDFZoneContentDocumentName,
    MPPDFZoneContentTimestamp,
    MPPDFZoneContentPageNumber,
    MPPDFZoneContentPageCount,
    MPPDFZoneContentPageLabel,
    MPPDFZoneContentCustomText,
};

@interface MPPDFHeaderFooterProcessor : NSObject

/// Process the PDF file at the given URL, adding headers and footers.
/// @param url        File URL of the PDF to post-process (overwritten in place).
/// @param title      Document title string.
/// @param preferences The shared preferences instance.
/// @param error      On failure, populated with error information.
/// @return YES if processing succeeded, NO otherwise.
- (BOOL)processFileAtURL:(NSURL *)url
           documentTitle:(NSString *)title
             preferences:(MPPreferences *)preferences
                   error:(NSError **)error;

@end
