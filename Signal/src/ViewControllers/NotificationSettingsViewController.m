//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "NotificationSettingsViewController.h"
#import "Environment.h"
#import "NotificationSettingsOptionsViewController.h"
#import "PropertyListPreferences.h"

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

    PropertyListPreferences *prefs = [Environment preferences];

    OWSTableSection *backgroundSection = [OWSTableSection new];
    backgroundSection.headerTitle = NSLocalizedString(@"NOTIFICATIONS_SECTION_BACKGROUND", nil);
    [backgroundSection addItem:[OWSTableItem itemWithCustomCellBlock:^{
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
                                                       reuseIdentifier:@"UITableViewCellStyleValue1"];

        NotificationType notifType = [prefs notificationPreviewType];
        NSString *detailString     = [prefs nameForNotificationPreviewType:notifType];

        [[cell textLabel] setText:NSLocalizedString(@"NOTIFICATIONS_SHOW", nil)];
        [[cell detailTextLabel] setText:detailString];
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
    [inAppSection addItem:[OWSTableItem itemWithCustomCellBlock:^{
        UITableViewCell *cell = [UITableViewCell new];

        BOOL soundEnabled = [prefs soundInForeground];

        [[cell textLabel] setText:NSLocalizedString(@"NOTIFICATIONS_SOUND", nil)];
        UISwitch *soundSwitch = [UISwitch new];
        soundSwitch.on = soundEnabled;
        [soundSwitch addTarget:self
                        action:@selector(didToggleSoundNotificationsSwitch:)
              forControlEvents:UIControlEventValueChanged];

        cell.accessoryView = soundSwitch;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
                                                    actionBlock:nil]];
    [contents addSection:inAppSection];

    self.contents = contents;
}

#pragma mark - Events

- (void)didToggleSoundNotificationsSwitch:(UISwitch *)sender {
    [Environment.preferences setSoundInForeground:sender.on];
}

@end
