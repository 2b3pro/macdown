//
//  MPPDFPreferencesViewController.m
//  MacDown
//
//  PDF header/footer preferences tab.
//

#import "MPPDFPreferencesViewController.h"
#import "MPPreferences.h"
#import "MPPDFHeaderFooterProcessor.h"


static NSArray *MPPDFZoneContentTitles(void)
{
    return @[
        NSLocalizedString(@"(None)", @"PDF zone content: none"),
        NSLocalizedString(@"Document Name", @"PDF zone content"),
        NSLocalizedString(@"Date/Time", @"PDF zone content"),
        NSLocalizedString(@"Page Number", @"PDF zone content"),
        NSLocalizedString(@"Page Count", @"PDF zone content"),
        NSLocalizedString(@"Page X of Y", @"PDF zone content"),
        NSLocalizedString(@"Custom Text\u2026", @"PDF zone content"),
    ];
}


@interface MPPDFPreferencesViewController ()

@property (weak) IBOutlet NSPopUpButton *headerLeftPopUp;
@property (weak) IBOutlet NSPopUpButton *headerCenterPopUp;
@property (weak) IBOutlet NSPopUpButton *headerRightPopUp;
@property (weak) IBOutlet NSPopUpButton *footerLeftPopUp;
@property (weak) IBOutlet NSPopUpButton *footerCenterPopUp;
@property (weak) IBOutlet NSPopUpButton *footerRightPopUp;

@property (weak) IBOutlet NSTextField *headerLeftCustomField;
@property (weak) IBOutlet NSTextField *headerCenterCustomField;
@property (weak) IBOutlet NSTextField *headerRightCustomField;
@property (weak) IBOutlet NSTextField *footerLeftCustomField;
@property (weak) IBOutlet NSTextField *footerCenterCustomField;
@property (weak) IBOutlet NSTextField *footerRightCustomField;
@property (weak) IBOutlet NSButton *differentFirstPageCheckbox;
@property (strong) NSTextField *fontSizeField;
@end


@implementation MPPDFPreferencesViewController

#pragma mark - MASPreferencesViewController

- (NSString *)viewIdentifier
{
    return @"PDFPreferences";
}

- (NSImage *)toolbarItemImage
{
    return [NSImage imageNamed:NSImageNameActionTemplate];
}

- (NSString *)toolbarItemLabel
{
    return NSLocalizedString(@"PDF", @"Preference pane title.");
}


#pragma mark - Override

- (void)viewWillAppear
{
    if (!self.fontSizeField)
        [self createFontSizeRow];
    [self populateAllPopUps];
    [self syncAllPopUps];
    [self updateAllCustomFieldVisibility];
}


#pragma mark - Font size row (created programmatically)

- (void)createFontSizeRow
{
    NSView *container = self.view;

    // "Font size:" label
    NSTextField *label = [NSTextField labelWithString:@"Font size:"];
    label.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:label];

    // Editable number field
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 60, 24)];
    field.editable = YES;
    field.selectable = YES;
    field.bezeled = YES;
    field.bezelStyle = NSTextFieldSquareBezel;
    field.drawsBackground = YES;
    field.alignment = NSTextAlignmentRight;
    field.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
    field.translatesAutoresizingMaskIntoConstraints = NO;

    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    formatter.minimum = @4;
    formatter.maximum = @36;
    formatter.usesGroupingSeparator = NO;
    field.formatter = formatter;

    [field bind:NSValueBinding
       toObject:self
    withKeyPath:@"self.preferences.pdfHeaderFooterFontSize"
        options:nil];
    [container addSubview:field];
    self.fontSizeField = field;

    // "pt" suffix label
    NSTextField *suffix = [NSTextField labelWithString:@"pt"];
    suffix.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
    suffix.textColor = [NSColor secondaryLabelColor];
    suffix.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:suffix];

    // Layout constraints — anchor below the "Different first page" checkbox.
    // Use bottom of container as fallback if outlet is not connected.
    NSLayoutYAxisAnchor *topRef;
    CGFloat topOffset;
    if (self.differentFirstPageCheckbox)
    {
        topRef = self.differentFirstPageCheckbox.bottomAnchor;
        topOffset = 14;
    }
    else
    {
        topRef = container.bottomAnchor;
        topOffset = -30;
    }
    [NSLayoutConstraint activateConstraints:@[
        [label.topAnchor constraintEqualToAnchor:topRef constant:topOffset],
        [label.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:20],
        [field.centerYAnchor constraintEqualToAnchor:label.centerYAnchor],
        [field.leadingAnchor constraintEqualToAnchor:label.trailingAnchor constant:8],
        [field.widthAnchor constraintEqualToConstant:60],
        [field.heightAnchor constraintEqualToConstant:24],
        [suffix.centerYAnchor constraintEqualToAnchor:field.centerYAnchor],
        [suffix.leadingAnchor constraintEqualToAnchor:field.trailingAnchor constant:4],
    ]];
}


#pragma mark - IBAction

- (IBAction)headerLeftChanged:(NSPopUpButton *)sender
{
    self.preferences.pdfHeaderLeftType = sender.indexOfSelectedItem;
    [self updateCustomFieldVisibility:self.headerLeftCustomField
                            forPopUp:sender];
}

- (IBAction)headerCenterChanged:(NSPopUpButton *)sender
{
    self.preferences.pdfHeaderCenterType = sender.indexOfSelectedItem;
    [self updateCustomFieldVisibility:self.headerCenterCustomField
                            forPopUp:sender];
}

- (IBAction)headerRightChanged:(NSPopUpButton *)sender
{
    self.preferences.pdfHeaderRightType = sender.indexOfSelectedItem;
    [self updateCustomFieldVisibility:self.headerRightCustomField
                            forPopUp:sender];
}

- (IBAction)footerLeftChanged:(NSPopUpButton *)sender
{
    self.preferences.pdfFooterLeftType = sender.indexOfSelectedItem;
    [self updateCustomFieldVisibility:self.footerLeftCustomField
                            forPopUp:sender];
}

- (IBAction)footerCenterChanged:(NSPopUpButton *)sender
{
    self.preferences.pdfFooterCenterType = sender.indexOfSelectedItem;
    [self updateCustomFieldVisibility:self.footerCenterCustomField
                            forPopUp:sender];
}

- (IBAction)footerRightChanged:(NSPopUpButton *)sender
{
    self.preferences.pdfFooterRightType = sender.indexOfSelectedItem;
    [self updateCustomFieldVisibility:self.footerRightCustomField
                            forPopUp:sender];
}


#pragma mark - Private

- (void)populateAllPopUps
{
    NSArray *titles = MPPDFZoneContentTitles();
    for (NSPopUpButton *popup in @[
        self.headerLeftPopUp, self.headerCenterPopUp, self.headerRightPopUp,
        self.footerLeftPopUp, self.footerCenterPopUp, self.footerRightPopUp])
    {
        [popup removeAllItems];
        [popup addItemsWithTitles:titles];
    }
}

- (void)syncAllPopUps
{
    [self.headerLeftPopUp selectItemAtIndex:self.preferences.pdfHeaderLeftType];
    [self.headerCenterPopUp selectItemAtIndex:self.preferences.pdfHeaderCenterType];
    [self.headerRightPopUp selectItemAtIndex:self.preferences.pdfHeaderRightType];
    [self.footerLeftPopUp selectItemAtIndex:self.preferences.pdfFooterLeftType];
    [self.footerCenterPopUp selectItemAtIndex:self.preferences.pdfFooterCenterType];
    [self.footerRightPopUp selectItemAtIndex:self.preferences.pdfFooterRightType];
}

- (void)updateAllCustomFieldVisibility
{
    [self updateCustomFieldVisibility:self.headerLeftCustomField
                            forPopUp:self.headerLeftPopUp];
    [self updateCustomFieldVisibility:self.headerCenterCustomField
                            forPopUp:self.headerCenterPopUp];
    [self updateCustomFieldVisibility:self.headerRightCustomField
                            forPopUp:self.headerRightPopUp];
    [self updateCustomFieldVisibility:self.footerLeftCustomField
                            forPopUp:self.footerLeftPopUp];
    [self updateCustomFieldVisibility:self.footerCenterCustomField
                            forPopUp:self.footerCenterPopUp];
    [self updateCustomFieldVisibility:self.footerRightCustomField
                            forPopUp:self.footerRightPopUp];
}

- (void)updateCustomFieldVisibility:(NSTextField *)field
                           forPopUp:(NSPopUpButton *)popup
{
    BOOL isCustom = (popup.indexOfSelectedItem == MPPDFZoneContentCustomText);
    field.hidden = !isCustom;
}

@end
