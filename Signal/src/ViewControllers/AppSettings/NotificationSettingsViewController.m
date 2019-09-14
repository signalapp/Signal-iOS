//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "NotificationSettingsViewController.h"
#import "NotificationSettingsOptionsViewController.h"
#import "OWSSoundSettingsViewController.h"
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/OWSPreferences.h>
#import <SignalMessaging/OWSSounds.h>
#import <SignalMessaging/UIUtil.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

@implementation NotificationSettingsViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    [self setTitle:NSLocalizedString(@"SETTINGS_NOTIFICATIONS", nil)];

    [self updateTableContents];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

    [self updateTableContents];
}

#pragma mark - Dependencies

- (OWSPreferences *)preferences
{
    return Environment.shared.preferences;
}

- (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
}

#pragma mark - Table Contents

- (void)updateTableContents
{
    OWSTableContents *contents = [OWSTableContents new];

    __weak NotificationSettingsViewController *weakSelf = self;

    // Sounds section.

    OWSTableSection *soundsSection = [OWSTableSection new];
    soundsSection.headerTitle
        = NSLocalizedString(@"SETTINGS_SECTION_SOUNDS", @"Header Label for the sounds section of settings views.");
    [soundsSection
        addItem:[OWSTableItem disclosureItemWithText:
                                  NSLocalizedString(@"SETTINGS_ITEM_NOTIFICATION_SOUND",
                                      @"Label for settings view that allows user to change the notification sound.")
                                          detailText:[OWSSounds displayNameForSound:[OWSSounds globalNotificationSound]]
                             accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"message_sound")
                                         actionBlock:^{
                                             OWSSoundSettingsViewController *vc = [OWSSoundSettingsViewController new];
                                             [weakSelf.navigationController pushViewController:vc animated:YES];
                                         }]];

    NSString *inAppSoundsLabelText = NSLocalizedString(@"NOTIFICATIONS_SECTION_INAPP",
        @"Table cell switch label. When disabled, Signal will not play notification sounds while the app is in the "
        @"foreground.");
    [soundsSection addItem:[OWSTableItem switchItemWithText:inAppSoundsLabelText
                               accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"in_app_sounds")
                               isOnBlock:^{
                                   return [weakSelf.preferences soundInForeground];
                               }
                               isEnabledBlock:^{
                                   return YES;
                               }
                               target:weakSelf
                               selector:@selector(didToggleSoundNotificationsSwitch:)]];
    [contents addSection:soundsSection];

    OWSTableSection *backgroundSection = [OWSTableSection new];
    backgroundSection.headerTitle = NSLocalizedString(@"SETTINGS_NOTIFICATION_CONTENT_TITLE", @"table section header");
    [backgroundSection
        addItem:[OWSTableItem
                     disclosureItemWithText:NSLocalizedString(@"NOTIFICATIONS_SHOW", nil)
                                 detailText:[self.preferences
                                                nameForNotificationPreviewType:[self.preferences
                                                                                       notificationPreviewType]]
                    accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"options")
                                actionBlock:^{
                                    NotificationSettingsOptionsViewController *vc =
                                        [NotificationSettingsOptionsViewController new];
                                    [weakSelf.navigationController pushViewController:vc animated:YES];
                                }]];
    backgroundSection.footerTitle
        = NSLocalizedString(@"SETTINGS_NOTIFICATION_CONTENT_DESCRIPTION", @"table section footer");
    [contents addSection:backgroundSection];


    OWSTableSection *eventsSection = [OWSTableSection new];
    eventsSection.headerTitle
        = NSLocalizedString(@"SETTINGS_NOTIFICATION_EVENTS_SECTION_TITLE", @"table section header");


    NSString *newUsersNotificationText = NSLocalizedString(@"SETTINGS_NOTIFICATION_EVENTS_CONTACT_JOINED_SIGNAL",
        @"When the local device discovers a contact has recently installed signal, the app can generates a message "
        @"encouraging the local user to say hello. Turning this switch off disables that feature.");
    [eventsSection
        addItem:[OWSTableItem switchItemWithText:newUsersNotificationText
                    accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"new_user_notification")
                    isOnBlock:^{
                        __block BOOL result;
                        [weakSelf.databaseStorage uiReadWithBlock:^(SDSAnyReadTransaction *transaction) {
                            result = [weakSelf.preferences shouldNotifyOfNewAccountsWithTransaction:transaction];
                        }];
                        return result;
                    }
                    isEnabledBlock:^{
                        return YES;
                    }
                    target:weakSelf
                    selector:@selector(didToggleshouldNotifyOfNewAccountsSwitch:)]];

    [contents addSection:eventsSection];

    self.contents = contents;
}

#pragma mark - Events

- (void)didToggleSoundNotificationsSwitch:(UISwitch *)sender
{
    [self.preferences setSoundInForeground:sender.on];
}

- (void)didToggleshouldNotifyOfNewAccountsSwitch:(UISwitch *)sender
{
    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [self.preferences setShouldNotifyOfNewAccounts:sender.isOn transaction:transaction];
    }];
}

@end
