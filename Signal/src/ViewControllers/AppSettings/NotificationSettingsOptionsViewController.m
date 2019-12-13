//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "NotificationSettingsOptionsViewController.h"
#import "Session-Swift.h"
#import "SignalApp.h"
#import <SignalMessaging/Environment.h>
#import "Session-Swift.h"

@implementation NotificationSettingsOptionsViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [self updateTableContents];
    
    // Loki: Set gradient background
    self.tableView.backgroundColor = UIColor.clearColor;
    LKGradient *gradient = LKGradients.defaultLokiBackground;
    self.view.backgroundColor = UIColor.clearColor;
    [self.view setGradient:gradient];
    
    // Loki: Set navigation bar background color
    UINavigationBar *navigationBar = self.navigationController.navigationBar;
    [navigationBar setBackgroundImage:[UIImage new] forBarMetrics:UIBarMetricsDefault];
    navigationBar.shadowImage = [UIImage new];
    [navigationBar setTranslucent:NO];
    navigationBar.barTintColor = LKColors.navigationBarBackground;
    
    // Loki: Customize title
    UILabel *titleLabel = [UILabel new];
    titleLabel.text = NSLocalizedString(@"Content", @"");
    titleLabel.textColor = LKColors.text;
    titleLabel.font = [UIFont boldSystemFontOfSize:LKValues.veryLargeFontSize];
    self.navigationItem.titleView = titleLabel;
}

#pragma mark - Table Contents

- (void)updateTableContents
{
    OWSTableContents *contents = [OWSTableContents new];

    __weak NotificationSettingsOptionsViewController *weakSelf = self;

    OWSTableSection *section = [OWSTableSection new];
    // section.footerTitle = NSLocalizedString(@"NOTIFICATIONS_FOOTER_WARNING", nil);

    OWSPreferences *prefs = Environment.shared.preferences;
    NotificationType selectedNotifType = [prefs notificationPreviewType];
    for (NSNumber *option in
        @[ @(NotificationNamePreview), @(NotificationNameNoPreview), @(NotificationNoNameNoPreview) ]) {
        NotificationType notificationType = (NotificationType)option.intValue;

        [section addItem:[OWSTableItem
                             itemWithCustomCellBlock:^{
                                 UITableViewCell *cell = [OWSTableItem newCell];
                                 cell.tintColor = LKColors.accent;
                                 [[cell textLabel] setText:[prefs nameForNotificationPreviewType:notificationType]];
                                 if (selectedNotifType == notificationType) {
                                     cell.accessoryType = UITableViewCellAccessoryCheckmark;
                                 }
                                 cell.accessibilityIdentifier
                                     = ACCESSIBILITY_IDENTIFIER_WITH_NAME(NotificationSettingsOptionsViewController,
                                         NSStringForNotificationType(notificationType));
                                 return cell;
                             }
                             actionBlock:^{
                                 [weakSelf setNotificationType:notificationType];
                             }]];
    }
    [contents addSection:section];

    self.contents = contents;
}

- (void)setNotificationType:(NotificationType)notificationType
{
    [Environment.shared.preferences setNotificationPreviewType:notificationType];

    // rebuild callUIAdapter since notification configuration changed.
    [AppEnvironment.shared.callService createCallUIAdapter];

    [self.navigationController popViewControllerAnimated:YES];
}

@end
