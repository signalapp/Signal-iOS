//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSSoundSettingsViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <SignalMessaging/OWSAudioPlayer.h>
#import <SignalMessaging/OWSSounds.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalMessaging/Theme.h>
#import <SignalMessaging/UIUtil.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSSoundSettingsViewController () <UIDocumentPickerDelegate>

@property (nonatomic) BOOL isDirty;

@property (nonatomic) OWSSound currentSound;

@property (nonatomic, nullable) OWSAudioPlayer *audioPlayer;

@end

#pragma mark -

@implementation OWSSoundSettingsViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.useThemeBackgroundColors = YES;

    [self setTitle:NSLocalizedString(@"SETTINGS_ITEM_NOTIFICATION_SOUND",
                       @"Label for settings view that allows user to change the notification sound.")];
    self.currentSound
        = (self.thread ? [OWSSounds notificationSoundForThread:self.thread] : [OWSSounds globalNotificationSound]);

    [self updateTableContents];
    [self updateNavigationItems];
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

    NSArray<NSNumber *> *allSounds = [OWSSounds allNotificationSounds];
    for (NSNumber *nsValue in allSounds) {
        OWSSound sound = (OWSSound)nsValue.unsignedLongValue;
        OWSTableItem *item;

        NSString *soundLabelText = ^{
            NSString *baseName = [OWSSounds displayNameForSound:sound];
            if (sound == OWSStandardSound_Note) {
                NSString *noteStringFormat = NSLocalizedString(@"SETTINGS_AUDIO_DEFAULT_TONE_LABEL_FORMAT",
                    @"Format string for the default 'Note' sound. Embeds the system {{sound name}}.");
                return [NSString stringWithFormat:noteStringFormat, baseName];
            } else {
                return [OWSSounds displayNameForSound:sound];
            }
        }();

        if (sound == self.currentSound) {
            item = [OWSTableItem
                  checkmarkItemWithText:soundLabelText
                accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, [OWSSounds displayNameForSound:sound])
                            actionBlock:^{
                                [weakSelf soundWasSelected:sound];
                            }];
        } else {
            item = [OWSTableItem
                     actionItemWithText:soundLabelText
                accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, [OWSSounds displayNameForSound:sound])
                            actionBlock:^{
                                [weakSelf soundWasSelected:sound];
                            }];
        }
        [soundsSection addItem:item];
    }

    NSString *addCustomSoundItemTitle = NSLocalizedString(@"NOTIFICATIONS_SECTION_SOUNDS_ADD_CUSTOM_SOUND",
        @"Label for settings UI that allows user to add a new notification sound.");
    OWSTableItem *addCustomSoundItem =
        [OWSTableItem disclosureItemWithText:addCustomSoundItemTitle
                                 actionBlock:^{
                                     UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
                                         initWithDocumentTypes:@[
                                             @"com.microsoft.waveform-audio",
                                             @"public.aifc-audio",
                                             @"public.aiff-audio",
                                             @"com.apple.coreaudio-format"
                                         ]
                                                        inMode:UIDocumentPickerModeImport];
                                     picker.delegate = weakSelf;
                                     [weakSelf presentViewController:picker animated:true completion:nil];
                                 }];
    [soundsSection addItem:addCustomSoundItem];

    [contents addSection:soundsSection];

    self.contents = contents;
}

#pragma mark - Events

- (void)soundWasSelected:(OWSSound)sound
{
    [self.audioPlayer stop];
    self.audioPlayer = [OWSSounds audioPlayerForSound:sound audioBehavior:OWSAudioBehavior_Playback];
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
    if (self.thread) {
        [OWSSounds setNotificationSound:self.currentSound forThread:self.thread];
    } else {
        [OWSSounds setGlobalNotificationSound:self.currentSound];
    }

    [self.audioPlayer stop];
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls
{
    [OWSSounds importSoundsAtURLs:urls];
    [self updateTableContents];
}

@end

NS_ASSUME_NONNULL_END
