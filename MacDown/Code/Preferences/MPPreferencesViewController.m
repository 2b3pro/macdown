//
//  MPPreferencesViewController.m
//  MacDown
//
//  Created by Tzu-ping Chung  on 7/06/2014.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import "MPPreferencesViewController.h"
#import "MPPreferences.h"


NSString * const MPDidRequestPreviewRenderNotification =
    @"MPDidRequestPreviewRenderNotificationName";
NSString * const MPDidRequestEditorSetupNotification =
    @"MPDidRequestEditorSetupNotificationName";

static const CGFloat kPreferencesPanelWidth = 595.0;

@implementation MPPreferencesViewController

- (id)init
{
    return [self initWithNibName:NSStringFromClass(self.class)
                          bundle:nil];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    NSRect frame = self.view.frame;
    if (frame.size.width < kPreferencesPanelWidth)
    {
        frame.size.width = kPreferencesPanelWidth;
        self.view.frame = frame;
    }
}

- (MPPreferences *)preferences
{
    return [MPPreferences sharedInstance];
}

@end
