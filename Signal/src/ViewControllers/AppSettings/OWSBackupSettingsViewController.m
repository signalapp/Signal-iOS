//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSBackupSettingsViewController.h"
#import "OWSBackup.h"
#import "OWSProgressView.h"
#import "Signal-Swift.h"
#import "ThreadUtil.h"
#import <SignalMessaging/AttachmentSharing.h>
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalMessaging/UIColor+OWS.h>
#import <SignalMessaging/UIFont+OWS.h>
#import <SignalMessaging/UIView+OWS.h>
#import <SignalServiceKit/MIMETypeUtil.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSBackupSettingsViewController ()

@end

#pragma mark -

@implementation OWSBackupSettingsViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.title = NSLocalizedString(@"SETTINGS_BACKUP", @"Label for the backup view in app settings.");

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(backupStateDidChange:)
                                                 name:NSNotificationNameBackupStateDidChange
                                               object:nil];

    [self updateTableContents];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidAppear:(BOOL)animated
{
    [self updateTableContents];
}

#pragma mark - Table Contents

- (void)updateTableContents
{
    OWSTableContents *contents = [OWSTableContents new];

    BOOL isBackupEnabled = [OWSBackup.sharedManager isBackupEnabled];

    // TODO: This UI is temporary.
    // Enabling backup will involve entering and registering a PIN.
    OWSTableSection *enableSection = [OWSTableSection new];
    enableSection.headerTitle = NSLocalizedString(@"SETTINGS_BACKUP", @"Label for the backup view in app settings.");
    [enableSection
        addItem:[OWSTableItem switchItemWithText:
                                  NSLocalizedString(@"SETTINGS_BACKUP_ENABLING_SWITCH",
                                      @"Label for switch in settings that controls whether or not backup is enabled.")
                                            isOn:isBackupEnabled
                                          target:self
                                        selector:@selector(isBackupEnabledDidChange:)]];
    [contents addSection:enableSection];

    self.contents = contents;
}

- (void)isBackupEnabledDidChange:(UISwitch *)sender
{
    [OWSBackup.sharedManager setIsBackupEnabled:sender.isOn];
}

#pragma mark - Events

- (void)backupStateDidChange:(NSNotification *)notification
{
    [self updateTableContents];
}

@end

NS_ASSUME_NONNULL_END
