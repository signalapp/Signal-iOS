//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "NotificationSoundsViewController.h"
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/NotificationSounds.h>
#import <SignalMessaging/OWSPreferences.h>

@interface NotificationSoundsViewController ()

@property (nonatomic) BOOL isDirty;

@property (nonatomic) NotificationSound globalNotificationSound;

@end

#pragma mark -

@implementation NotificationSoundsViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    [self setTitle:NSLocalizedString(@"SETTINGS_NOTIFICATION_SOUND", nil)];

    OWSPreferences *preferences = [Environment preferences];
    self.globalNotificationSound = preferences.globalNotificationSound;

    [self updateTableContents];
    [self updateNavigationItems];
}

- (void)viewDidAppear:(BOOL)animated
{
    [self updateTableContents];
}

- (void)updateNavigationItems
{
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemStop
                                                      target:self
                                                      action:@selector(cancelWasPressed:)];

    if (self.isDirty) {
        self.navigationItem.rightBarButtonItem =
            [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave
                                                          target:self
                                                          action:@selector(saveWasPressed:)];
    } else {
        self.navigationItem.rightBarButtonItem = nil;
    }
}

#pragma mark - Table Contents

- (void)updateTableContents
{
    OWSTableContents *contents = [OWSTableContents new];

    __weak NotificationSoundsViewController *weakSelf = self;

    OWSTableSection *soundsSection = [OWSTableSection new];
    soundsSection.headerTitle = NSLocalizedString(
        @"NOTIFICATIONS_SECTION_SOUNDS", @"Label for settings UI allows user to change the notification sound.");
    for (NSNumber *nsNotificationSound in [NotificationSounds allNotificationSounds]) {
        NotificationSound notificationSound = (NotificationSound)nsNotificationSound.intValue;
        // TODO: No disclosure, show checkmark.
        [soundsSection
            addItem:[OWSTableItem
                        disclosureItemWithText:[NotificationSounds displayNameForNotificationSound:notificationSound]
                                   actionBlock:^{
                                       [weakSelf notificationSoundWasSelected:notificationSound];
                                   }]];
    }

    [contents addSection:soundsSection];

    //    OWSTableSection *backgroundSection = [OWSTableSection new];
    //    backgroundSection.headerTitle = NSLocalizedString(@"NOTIFICATIONS_SECTION_BACKGROUND", nil);
    //    [backgroundSection addItem:[OWSTableItem itemWithCustomCellBlock:^{
    //        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
    //                                                       reuseIdentifier:@"UITableViewCellStyleValue1"];
    //
    //        NotificationType notifType = [prefs notificationPreviewType];
    //        NSString *detailString     = [prefs nameForNotificationPreviewType:notifType];
    //        cell.textLabel.text = NSLocalizedString(@"NOTIFICATIONS_SHOW", nil);
    //        cell.detailTextLabel.text = detailString;
    //        [cell setAccessoryType:UITableViewCellAccessoryDisclosureIndicator];
    //
    //        return cell;
    //    }
    //                                                         actionBlock:^{
    //                                                             NotificationSettingsOptionsViewController *vc =
    //                                                             [NotificationSettingsOptionsViewController new];
    //                                                             [weakSelf.navigationController pushViewController:vc
    //                                                             animated:YES];
    //                                                         }]];
    //    [contents addSection:backgroundSection];
    //
    //    OWSTableSection *inAppSection = [OWSTableSection new];
    //    inAppSection.headerTitle = NSLocalizedString(@"NOTIFICATIONS_SECTION_INAPP", nil);
    //    [inAppSection addItem:[OWSTableItem switchItemWithText:NSLocalizedString(@"NOTIFICATIONS_SOUND", nil)
    //                                                      isOn:[prefs soundInForeground]
    //                                                    target:weakSelf
    //                                                  selector:@selector(didToggleSoundNotificationsSwitch:)]];
    //    [contents addSection:inAppSection];

    self.contents = contents;
}

#pragma mark - Events

- (void)notificationSoundWasSelected:(NotificationSound)notificationSound
{
    [NotificationSounds playNotificationSound:notificationSound];

    if (self.globalNotificationSound == notificationSound) {
        return;
    }

    self.globalNotificationSound = notificationSound;
    self.isDirty = YES;
    [self updateTableContents];
}

//- (void)didToggleSoundNotificationsSwitch:(UISwitch *)sender {
//    [Environment.preferences setSoundInForeground:sender.on];
//}

- (void)cancelWasPressed:(id)sender
{
    // TODO: Add "discard changes?" alert.
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)saveWasPressed:(id)sender
{
    OWSPreferences *preferences = [Environment preferences];
    preferences.globalNotificationSound = self.globalNotificationSound;

    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
