//
//  MPDocument.h
//  MacDown
//
//  Created by Tzu-ping Chung  on 6/06/2014.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import <Cocoa/Cocoa.h>
@class MPPreferences;


@interface MPDocument : NSDocument

@property (nonatomic, readonly) MPPreferences *preferences;
@property (readonly) BOOL previewVisible;
@property (readonly) BOOL editorVisible;

@property (nonatomic, readwrite) NSString *markdown;
@property (nonatomic, readonly) NSString *html;

// A style name, or an absolute path to a stylesheet, to render with instead
// of the one chosen in preferences.
@property (copy) NSString *styleOverride;

// Renders the document in a window that is never shown and writes it as PDF
// the way File > Export > PDF does, once the preview (MathJax and Mermaid
// included) has finished rendering. The handler gets nil on success.
- (void)exportPDFHeadlesslyToURL:(NSURL *)url
               completionHandler:(void (^)(NSError *error))handler;

@end
