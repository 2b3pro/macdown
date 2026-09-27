//
//  MPQuickLookPreviewProvider.h
//  MacDownQuickLook
//
//  Quick Look preview extension for Markdown documents. Renders the file with
//  the same Hoedown pipeline MacDown uses, honoring the user's MacDown
//  rendering preferences (Markdown extensions and preview style).
//

#import <QuickLookUI/QuickLookUI.h>

@interface MPQuickLookPreviewProvider : QLPreviewProvider <QLPreviewingController>
@end
