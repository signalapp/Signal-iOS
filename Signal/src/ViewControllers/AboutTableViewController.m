//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "AboutTableViewController.h"
#import "UIUtil.h"
#import "UIView+OWS.h"
#import <SignalServiceKit/TSDatabaseView.h>
#import <SignalServiceKit/TSStorageManager.h>

@implementation AboutTableViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.title = NSLocalizedString(@"SETTINGS_ABOUT", @"Navbar title");

    [self updateTableContents];
}

#pragma mark - Table Contents

- (void)updateTableContents
{
    OWSTableContents *contents = [OWSTableContents new];

    OWSTableSection *informationSection = [OWSTableSection new];
    informationSection.headerTitle = NSLocalizedString(@"SETTINGS_INFORMATION_HEADER", @"");
    [informationSection addItem:[OWSTableItem labelItemWithText:NSLocalizedString(@"SETTINGS_VERSION", @"")
                                                  accessoryText:[[[NSBundle mainBundle] infoDictionary]
                                                                    objectForKey:@"CFBundleVersion"]]];
    [contents addSection:informationSection];

    OWSTableSection *helpSection = [OWSTableSection new];
    helpSection.headerTitle = NSLocalizedString(@"SETTINGS_HELP_HEADER", @"");
    [helpSection addItem:[OWSTableItem disclosureItemWithText:NSLocalizedString(@"SETTINGS_SUPPORT", @"")
                                                  actionBlock:^{
                                                      [[UIApplication sharedApplication]
                                                          openURL:[NSURL URLWithString:@"https://support.signal.org"]];
                                                  }]];
    [contents addSection:helpSection];

    UILabel *copyrightLabel = [UILabel new];
    copyrightLabel.text = NSLocalizedString(@"SETTINGS_COPYRIGHT", @"");
    copyrightLabel.textColor = [UIColor ows_darkGrayColor];
    copyrightLabel.font = [UIFont ows_regularFontWithSize:15.0f];
    copyrightLabel.numberOfLines = 2;
    copyrightLabel.lineBreakMode = NSLineBreakByWordWrapping;
    copyrightLabel.textAlignment = NSTextAlignmentCenter;
    helpSection.customFooterView = copyrightLabel;
    helpSection.customFooterHeight = @(60.f);

#ifdef DEBUG
    __block NSUInteger threadCount;
    __block NSUInteger messageCount;
    [TSStorageManager.sharedManager.dbReadConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        threadCount = [[transaction ext:TSThreadDatabaseViewExtensionName] numberOfItemsInAllGroups];
        messageCount = [[transaction ext:TSMessageDatabaseViewExtensionName] numberOfItemsInAllGroups];
    }];

    OWSTableSection *debugSection = [OWSTableSection new];
    debugSection.headerTitle = @"Debug";
    [debugSection addItem:[OWSTableItem labelItemWithText:[NSString stringWithFormat:@"Threads: %zd", threadCount]]];
    [debugSection addItem:[OWSTableItem labelItemWithText:[NSString stringWithFormat:@"Messages: %zd", messageCount]]];
    [contents addSection:debugSection];
#endif

    self.contents = contents;
}

@end
