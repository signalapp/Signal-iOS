//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "NotificationSoundsViewController.h"
#import <SignalMessaging/OWSSounds.h>

@interface NotificationSoundsViewController ()

@property (nonatomic) BOOL isDirty;

@property (nonatomic) OWSSound currentSound;

@end

#pragma mark -

@implementation NotificationSoundsViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    [self setTitle:NSLocalizedString(@"NOTIFICATIONS_ITEM_SOUND",
                       @"Label for settings view that allows user to change the notification sound.")];

    self.currentSound
        = (self.thread ? [OWSSounds notificationSoundForThread:self.thread] : [OWSSounds globalNotificationSound]);

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
    for (NSNumber *nsValue in [OWSSounds allNotificationSounds]) {
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
    if (self.thread) {
        [OWSSounds setNotificationSound:self.currentSound forThread:self.thread];
    } else {
        [OWSSounds setGlobalNotificationSound:self.currentSound];
    }

    [self.navigationController popViewControllerAnimated:YES];
}

@end
