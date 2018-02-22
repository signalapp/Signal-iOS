//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSSoundSettingsViewController.h"
#import <SignalMessaging/OWSSounds.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSSoundSettingsViewController ()

@property (nonatomic) BOOL isDirty;

@property (nonatomic) OWSSound currentSound;

@end

#pragma mark -

@implementation OWSSoundSettingsViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    switch (self.soundType) {
        case OWSSoundType_Notification:
            [self setTitle:NSLocalizedString(@"SETTINGS_ITEM_NOTIFICATION_SOUND",
                                             @"Label for settings view that allows user to change the notification sound.")];
            self.currentSound
            = (self.thread ? [OWSSounds notificationSoundForThread:self.thread] : [OWSSounds globalNotificationSound]);
            break;
        case OWSSoundType_Ringtone:
            [self setTitle:NSLocalizedString(@"SETTINGS_ITEM_RINGTONE_SOUND",
                                             @"Label for settings view that allows user to change the ringtone sound.")];
            self.currentSound
            = (self.thread ? [OWSSounds ringtoneSoundForThread:self.thread] : [OWSSounds globalRingtoneSound]);
            break;
    }

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
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
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

    __weak OWSSoundSettingsViewController *weakSelf = self;

    OWSTableSection *soundsSection = [OWSTableSection new];
    soundsSection.headerTitle = NSLocalizedString(
        @"NOTIFICATIONS_SECTION_SOUNDS", @"Label for settings UI that allows user to change the notification sound.");
    
    NSArray<NSNumber *> *allSounds;
    switch (self.soundType) {
        case OWSSoundType_Notification:
            allSounds = [OWSSounds allNotificationSounds];
            break;
        case OWSSoundType_Ringtone:
            allSounds = [OWSSounds allRingtoneSounds];
            break;
    }
    for (NSNumber *nsValue in allSounds) {
        OWSSound sound = (OWSSound)nsValue.intValue;
        OWSTableItem *item;
        if (sound == self.currentSound) {
            item = [OWSTableItem checkmarkItemWithText:[OWSSounds displayNameForSound:sound]
                                           actionBlock:^{
                                               [weakSelf soundWasSelected:sound];
                                           }];
        } else {
            item = [OWSTableItem actionItemWithText:[OWSSounds displayNameForSound:sound]
                                        actionBlock:^{
                                            [weakSelf soundWasSelected:sound];
                                        }];
        }
        [soundsSection addItem:item];
    }

    [contents addSection:soundsSection];

    self.contents = contents;
}

#pragma mark - Events

- (void)soundWasSelected:(OWSSound)sound
{
    [OWSSounds playSound:sound];

    if (self.currentSound == sound) {
        return;
    }

    self.currentSound = sound;
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
    switch (self.soundType) {
        case OWSSoundType_Notification:
            if (self.thread) {
                [OWSSounds setNotificationSound:self.currentSound forThread:self.thread];
            } else {
                [OWSSounds setGlobalNotificationSound:self.currentSound];
            }
            break;
        case OWSSoundType_Ringtone:
            if (self.thread) {
                [OWSSounds setRingtoneSound:self.currentSound forThread:self.thread];
            } else {
                [OWSSounds setGlobalRingtoneSound:self.currentSound];
            }
            break;
    }

    [self.navigationController popViewControllerAnimated:YES];
}

@end

NS_ASSUME_NONNULL_END
