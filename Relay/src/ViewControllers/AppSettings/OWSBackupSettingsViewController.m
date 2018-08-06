//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSBackupSettingsViewController.h"
#import "OWSBackup.h"
#import "Relay-Swift.h"
#import "ThreadUtil.h"
#import <RelayMessaging/AttachmentSharing.h>
#import <RelayMessaging/Environment.h>
#import <RelayMessaging/RelayMessaging-Swift.h>
#import <RelayMessaging/UIColor+OWS.h>
#import <RelayMessaging/UIFont+OWS.h>
#import <RelayMessaging/UIView+OWS.h>
#import <RelayServiceKit/MIMETypeUtil.h>

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
    [super viewDidAppear:animated];
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

    if (isBackupEnabled) {
        // TODO: This UI is temporary.
        // Enabling backup will involve entering and registering a PIN.
        OWSTableSection *progressSection = [OWSTableSection new];
        [progressSection
            addItem:[OWSTableItem labelItemWithText:NSLocalizedString(@"SETTINGS_BACKUP_STATUS",
                                                        @"Label for status row in the in the backup settings view.")
                                      accessoryText:[self backupExportStateLocalizedDescription]]];
        if (OWSBackup.sharedManager.backupExportState == OWSBackupState_InProgress) {
            if (OWSBackup.sharedManager.backupExportDescription) {
                [progressSection
                    addItem:[OWSTableItem
                                labelItemWithText:NSLocalizedString(@"SETTINGS_BACKUP_PHASE",
                                                      @"Label for phase row in the in the backup settings view.")
                                    accessoryText:OWSBackup.sharedManager.backupExportDescription]];
                if (OWSBackup.sharedManager.backupExportProgress) {
                    NSUInteger progressPercent
                        = (NSUInteger)round(OWSBackup.sharedManager.backupExportProgress.floatValue * 100);
                    NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
                    [numberFormatter setNumberStyle:NSNumberFormatterPercentStyle];
                    [numberFormatter setMaximumFractionDigits:0];
                    [numberFormatter setMultiplier:@1];
                    NSString *progressString = [numberFormatter stringFromNumber:@(progressPercent)];
                    [progressSection
                        addItem:[OWSTableItem
                                    labelItemWithText:NSLocalizedString(@"SETTINGS_BACKUP_PROGRESS",
                                                          @"Label for phase row in the in the backup settings view.")
                                        accessoryText:progressString]];
                }
            }
        }

        switch (OWSBackup.sharedManager.backupExportState) {
            case OWSBackupState_Idle:
            case OWSBackupState_Failed:
            case OWSBackupState_Succeeded:
                [progressSection
                    addItem:[OWSTableItem disclosureItemWithText:
                                              NSLocalizedString(@"SETTINGS_BACKUP_BACKUP_NOW",
                                                  @"Label for 'backup now' button in the backup settings view.")
                                                     actionBlock:^{
                                                         [OWSBackup.sharedManager tryToExportBackup];
                                                     }]];
                break;
            case OWSBackupState_InProgress:
                [progressSection
                    addItem:[OWSTableItem disclosureItemWithText:
                                              NSLocalizedString(@"SETTINGS_BACKUP_CANCEL_BACKUP",
                                                  @"Label for 'cancel backup' button in the backup settings view.")
                                                     actionBlock:^{
                                                         [OWSBackup.sharedManager cancelExportBackup];
                                                     }]];
                break;
        }

        [contents addSection:progressSection];
    }

    self.contents = contents;
}

- (NSString *)backupExportStateLocalizedDescription
{
    switch (OWSBackup.sharedManager.backupExportState) {
        case OWSBackupState_Idle:
            return NSLocalizedString(@"SETTINGS_BACKUP_STATUS_IDLE", @"Indicates that app is not backing up.");
        case OWSBackupState_InProgress:
            return NSLocalizedString(@"SETTINGS_BACKUP_STATUS_IN_PROGRESS", @"Indicates that app is backing up.");
        case OWSBackupState_Failed:
            return NSLocalizedString(@"SETTINGS_BACKUP_STATUS_FAILED", @"Indicates that the last backup failed.");
        case OWSBackupState_Succeeded:
            return NSLocalizedString(@"SETTINGS_BACKUP_STATUS_SUCCEEDED", @"Indicates that the last backup succeeded.");
    }
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
