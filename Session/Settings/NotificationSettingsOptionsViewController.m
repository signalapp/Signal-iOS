//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "NotificationSettingsOptionsViewController.h"
#import "Session-Swift.h"
#import <SignalUtilitiesKit/SignalUtilitiesKit-Swift.h>

@implementation NotificationSettingsOptionsViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [self updateTableContents];

    [LKViewControllerUtilities setUpDefaultSessionStyleForVC:self withTitle:NSLocalizedString(@"Content", @"") customBackButton:NO];
    self.tableView.backgroundColor = UIColor.clearColor;
}

#pragma mark - Table Contents

- (void)updateTableContents
{
    OWSTableContents *contents = [OWSTableContents new];

    __weak NotificationSettingsOptionsViewController *weakSelf = self;

    OWSTableSection *section = [OWSTableSection new];
    // section.footerTitle = NSLocalizedString(@"NOTIFICATIONS_FOOTER_WARNING", nil);

    NSInteger selectedNotifType = [SMKPreferences notificationPreviewType];
    
    for (NSNumber *option in [SMKPreferences notificationTypes]) {
        [section addItem:[OWSTableItem
                             itemWithCustomCellBlock:^{
                                 UITableViewCell *cell = [OWSTableItem newCell];
                                 cell.tintColor = LKColors.accent;
                                 [[cell textLabel] setText:[SMKPreferences nameForNotificationPreviewType:option.intValue]];
                                 if (selectedNotifType == option.intValue) {
                                     cell.accessoryType = UITableViewCellAccessoryCheckmark;
                                 }
                                 cell.accessibilityIdentifier = ACCESSIBILITY_IDENTIFIER_WITH_NAME(NotificationSettingsOptionsViewController, [SMKPreferences accessibilityIdentifierForNotificationPreviewType:option.intValue]);
                                 return cell;
                             }
                             actionBlock:^{
                                [SMKPreferences setNotificationPreviewType: option.intValue];
                                [weakSelf.navigationController popViewControllerAnimated:YES];
                             }]];
    }
    [contents addSection:section];

    self.contents = contents;
}

@end
