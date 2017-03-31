//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "NotificationSettingsViewController.h"
#import "Environment.h"
#import "NotificationSettingsOptionsViewController.h"
#import "PropertyListPreferences.h"

#define kNotificationOptionSection 0

@interface NotificationSettingsViewController ()

@property NSArray *notificationsSections;

@end

@implementation NotificationSettingsViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setTitle:NSLocalizedString(@"SETTINGS_NOTIFICATIONS", nil)];

    self.notificationsSections = @[
        NSLocalizedString(@"NOTIFICATIONS_SECTION_BACKGROUND", nil),
        NSLocalizedString(@"NOTIFICATIONS_SECTION_INAPP", nil)
    ];
}

- (void)viewDidAppear:(BOOL)animated {
    [self.tableView reloadData];
}

#pragma mark - Table view data source

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return [self.notificationsSections objectAtIndex:(NSUInteger)section];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return (NSInteger)self.notificationsSections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *cellIdentifier = @"SignalTableViewCellIdentifier";
    UITableViewCell *cell    = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];

    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cellIdentifier];
    }

    PropertyListPreferences *prefs = Environment.preferences;
    if (indexPath.section == kNotificationOptionSection) {
        NotificationType notifType = [prefs notificationPreviewType];
        NSString *detailString     = [prefs nameForNotificationPreviewType:notifType];

        [[cell textLabel] setText:NSLocalizedString(@"NOTIFICATIONS_SHOW", nil)];
        [[cell detailTextLabel] setText:detailString];
        [cell setAccessoryType:UITableViewCellAccessoryDisclosureIndicator];
    } else {
        BOOL soundEnabled = [prefs soundInForeground];

        [[cell textLabel] setText:NSLocalizedString(@"NOTIFICATIONS_SOUND", nil)];
        [[cell detailTextLabel] setText:nil];
        UISwitch *switchv = [[UISwitch alloc] initWithFrame:CGRectZero];
        switchv.on        = soundEnabled;
        [switchv addTarget:self
                      action:@selector(didToggleSoundNotificationsSwitch:)
            forControlEvents:UIControlEventValueChanged];

        cell.accessoryView = switchv;
    }

    return cell;
}

- (void)didToggleSoundNotificationsSwitch:(UISwitch *)sender {
    [Environment.preferences setSoundInForeground:sender.on];
}

- (NSIndexPath *)tableView:(UITableView *)tableView willSelectRowAtIndexPath:(nonnull NSIndexPath *)indexPath {
    switch (indexPath.section) {
        case kNotificationOptionSection: {
            return indexPath;
        }
        default: {
            return nil;
        }
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    switch (indexPath.section) {
        case kNotificationOptionSection: {
            NotificationSettingsOptionsViewController *vc =
                [[NotificationSettingsOptionsViewController alloc] initWithStyle:UITableViewStyleGrouped];
            [self.navigationController pushViewController:vc animated:YES];
            break;
        }
    }
}

- (void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    cell.accessoryType    = UITableViewCellAccessoryNone;
}

@end
