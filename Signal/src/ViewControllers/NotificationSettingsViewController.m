//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "NotificationSettingsViewController.h"
#import "Environment.h"
#import "NotificationSettingsOptionsViewController.h"
#import "OWSPreferences.h"

@implementation NotificationSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    [self setTitle:NSLocalizedString(@"SETTINGS_NOTIFICATIONS", nil)];

    [self updateTableContents];
}

- (void)viewDidAppear:(BOOL)animated {
    [self updateTableContents];
}

#pragma mark - Table Contents

- (void)updateTableContents
{
    OWSTableContents *contents = [OWSTableContents new];

    __weak NotificationSettingsViewController *weakSelf = self;

    OWSPreferences *prefs = [Environment preferences];

    OWSTableSection *backgroundSection = [OWSTableSection new];
    backgroundSection.headerTitle = NSLocalizedString(@"NOTIFICATIONS_SECTION_BACKGROUND", nil);
    [backgroundSection addItem:[OWSTableItem itemWithCustomCellBlock:^{
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
                                                       reuseIdentifier:@"UITableViewCellStyleValue1"];

        NotificationType notifType = [prefs notificationPreviewType];
        NSString *detailString     = [prefs nameForNotificationPreviewType:notifType];
        cell.textLabel.text = NSLocalizedString(@"NOTIFICATIONS_SHOW", nil);
        cell.detailTextLabel.text = detailString;
        [cell setAccessoryType:UITableViewCellAccessoryDisclosureIndicator];

        return cell;
    }
                                   actionBlock:^{
                                       NotificationSettingsOptionsViewController *vc =
                                           [NotificationSettingsOptionsViewController new];
                                       [weakSelf.navigationController pushViewController:vc animated:YES];
                                   }]];
    [contents addSection:backgroundSection];

    OWSTableSection *inAppSection = [OWSTableSection new];
    inAppSection.headerTitle = NSLocalizedString(@"NOTIFICATIONS_SECTION_INAPP", nil);
    [inAppSection addItem:[OWSTableItem switchItemWithText:NSLocalizedString(@"NOTIFICATIONS_SOUND", nil)
                                                      isOn:[prefs soundInForeground]
                                                    target:weakSelf
                                                  selector:@selector(didToggleSoundNotificationsSwitch:)]];
    [contents addSection:inAppSection];

    self.contents = contents;
}

#pragma mark - Events

- (void)didToggleSoundNotificationsSwitch:(UISwitch *)sender {
    [Environment.preferences setSoundInForeground:sender.on];
}

@end
