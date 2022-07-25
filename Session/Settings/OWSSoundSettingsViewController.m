//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSSoundSettingsViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <SessionMessagingKit/OWSAudioPlayer.h>
#import <SessionMessagingKit/SessionMessagingKit-Swift.h>
#import <SignalUtilitiesKit/SignalUtilitiesKit-Swift.h>
#import <SignalUtilitiesKit/UIUtil.h>
#import "Session-Swift.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSSoundSettingsViewController ()

@property (nonatomic) BOOL isDirty;

@property (nonatomic) NSInteger currentSound;

@property (nonatomic, nullable) OWSAudioPlayer *audioPlayer;

@end

#pragma mark -

@implementation OWSSoundSettingsViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    [self setTitle:NSLocalizedString(@"SETTINGS_ITEM_NOTIFICATION_SOUND",
                       @"Label for settings view that allows user to change the notification sound.")];
    self.currentSound = [SMKSound notificationSoundFor:self.threadId];
    
    [self updateTableContents];
    [self updateNavigationItems];
    
    [LKViewControllerUtilities setUpDefaultSessionStyleForVC:self withTitle:NSLocalizedString(@"Sound", @"") customBackButton:NO];
    self.tableView.backgroundColor = UIColor.clearColor;
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

    [self updateTableContents];
}

- (void)updateNavigationItems
{
    UIBarButtonItem *cancelItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                      target:self
                                                      action:@selector(cancelWasPressed:)
                                     accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"cancel")];
    
    cancelItem.tintColor = LKColors.text;
    
    self.navigationItem.leftBarButtonItem = cancelItem;

    if (self.isDirty) {
        UIBarButtonItem *saveItem =
            [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave
                                                          target:self
                                                          action:@selector(saveWasPressed:)
                                         accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"save")];
        self.navigationItem.rightBarButtonItem = saveItem;
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

    NSArray<NSNumber *> *allSounds = [SMKSound notificationSounds];
    for (NSNumber *nsValue in allSounds) {
        NSInteger sound = nsValue.integerValue;
        OWSTableItem *item;

        NSString *soundLabelText = ^{
            NSString *baseName = [SMKSound displayNameFor:sound];
            if ([SMKSound isNote:sound]) {
                NSString *noteStringFormat = NSLocalizedString(@"SETTINGS_AUDIO_DEFAULT_TONE_LABEL_FORMAT",
                    @"Format string for the default 'Note' sound. Embeds the system {{sound name}}.");
                return [NSString stringWithFormat:noteStringFormat, baseName];
            }
            else {
                return [SMKSound displayNameFor:sound];
            }
        }();

        if (sound == self.currentSound) {
            item = [OWSTableItem
                  checkmarkItemWithText:soundLabelText
                accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, [SMKSound displayNameFor:sound])
                            actionBlock:^{
                                [weakSelf soundWasSelected:sound];
                            }];
        } else {
            item = [OWSTableItem
                     actionItemWithText:soundLabelText
                accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, [SMKSound displayNameFor:sound])
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

- (void)soundWasSelected:(NSInteger)sound
{
    [self.audioPlayer stop];
    self.audioPlayer = [SMKSound audioPlayerFor:sound audioBehavior:OWSAudioBehavior_Playback];
    // Suppress looping in this view.
    self.audioPlayer.isLooping = NO;
    [self.audioPlayer play];

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
    [self.audioPlayer stop];
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)saveWasPressed:(id)sender
{
    if (self.threadId) {
        [SMKSound setNotificationSound:self.currentSound forThreadId:self.threadId];
    }
    else {
        [SMKSound setGlobalNotificationSound:self.currentSound];
    }

    [self.audioPlayer stop];
    [self.navigationController popViewControllerAnimated:YES];
}

@end

NS_ASSUME_NONNULL_END
