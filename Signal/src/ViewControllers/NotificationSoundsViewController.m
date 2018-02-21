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

    [self setTitle:NSLocalizedString(@"NOTIFICATIONS_ITEM_SOUND",
                       @"Label for settings view that allows user to change the notification sound.")];

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
        @"NOTIFICATIONS_SECTION_SOUNDS", @"Label for settings UI that allows user to change the notification sound.");
    for (NSNumber *nsNotificationSound in [NotificationSounds allNotificationSounds]) {
        NotificationSound notificationSound = (NotificationSound)nsNotificationSound.intValue;
        OWSTableItem *item;
        if (notificationSound == self.globalNotificationSound) {
            item = [OWSTableItem
                checkmarkItemWithText:[NotificationSounds displayNameForNotificationSound:notificationSound]
                          actionBlock:^{
                              [weakSelf notificationSoundWasSelected:notificationSound];
                          }];
        } else {
            item =
                [OWSTableItem actionItemWithText:[NotificationSounds displayNameForNotificationSound:notificationSound]
                                     actionBlock:^{
                                         [weakSelf notificationSoundWasSelected:notificationSound];
                                     }];
        }
        [soundsSection addItem:item];
    }

    [contents addSection:soundsSection];

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
    [self updateNavigationItems];
}

- (void)cancelWasPressed:(id)sender
{
    // TODO: Add "discard changes?" alert.
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)saveWasPressed:(id)sender
{
    OWSPreferences *preferences = [Environment preferences];
    preferences.globalNotificationSound = self.globalNotificationSound;

    [self.navigationController popViewControllerAnimated:YES];
}

@end
