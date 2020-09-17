//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSBackupSettingsViewController.h"
#import "OWSBackup.h"
#import "Signal-Swift.h"
#import "ThreadUtil.h"
#import <PromiseKit/AnyPromise.h>
#import <SignalMessaging/AttachmentSharing.h>
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalMessaging/UIFont+OWS.h>
#import <SignalMessaging/UIView+OWS.h>
#import <SignalServiceKit/MIMETypeUtil.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSBackupSettingsViewController ()

@property (nonatomic, nullable) NSError *iCloudError;

@end

#pragma mark -

@implementation OWSBackupSettingsViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.title = NSLocalizedString(@"SETTINGS_BACKUP", @"Label for the backup view in app settings.");

    self.useThemeBackgroundColors = YES;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(backupStateDidChange:)
                                                 name:NSNotificationNameBackupStateDidChange
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidBecomeActive:)
                                                 name:OWSApplicationDidBecomeActiveNotification
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
    [self updateICloudStatus];
}

- (void)updateICloudStatus
{
    __weak OWSBackupSettingsViewController *weakSelf = self;
    [self.backup ensureCloudKitAccess]
        .then(^{
            OWSAssertIsOnMainThread();

            weakSelf.iCloudError = nil;
            [weakSelf updateTableContents];
        })
        .catch(^(NSError *error) {
            OWSAssertIsOnMainThread();

            weakSelf.iCloudError = error;
            [weakSelf updateTableContents];
        });
}

#pragma mark - Table Contents

- (void)updateTableContents
{
    OWSTableContents *contents = [OWSTableContents new];

    BOOL isBackupEnabled = [OWSBackup.shared isBackupEnabled];

    if (self.iCloudError) {
        OWSTableSection *iCloudSection = [OWSTableSection new];
        iCloudSection.headerTitle = NSLocalizedString(
            @"SETTINGS_BACKUP_ICLOUD_STATUS", @"Label for iCloud status row in the in the backup settings view.");
        [iCloudSection
            addItem:[OWSTableItem
                        longDisclosureItemWithText:[OWSBackupAPI errorMessageForCloudKitAccessError:self.iCloudError]
                                       actionBlock:^{
                                           [UIApplication.sharedApplication
                                                         openURL:[NSURL
                                                                     URLWithString:UIApplicationOpenSettingsURLString]
                                                         options:@{}
                                               completionHandler:nil];
                                       }]];
        [contents addSection:iCloudSection];
    }

    // TODO: This UI is temporary.
    // Enabling backup will involve entering and registering a PIN.
    OWSTableSection *enableSection = [OWSTableSection new];
    enableSection.headerTitle = NSLocalizedString(@"SETTINGS_BACKUP", @"Label for the backup view in app settings.");
    [enableSection
        addItem:[OWSTableItem switchItemWithText:
                                  NSLocalizedString(@"SETTINGS_BACKUP_ENABLING_SWITCH",
                                      @"Label for switch in settings that controls whether or not backup is enabled.")
                                       isOnBlock:^{ return [OWSBackup.shared isBackupEnabled]; }
                                          target:self
                                        selector:@selector(isBackupEnabledDidChange:)]];
    [contents addSection:enableSection];

    if (isBackupEnabled) {
        // TODO: This UI is temporary.
        // Enabling backup will involve entering and registering a PIN.
        OWSTableSection *progressSection = [OWSTableSection new];
        [progressSection
            addItem:[OWSTableItem
                        labelItemWithText:NSLocalizedString(@"SETTINGS_BACKUP_STATUS",
                                              @"Label for backup status row in the in the backup settings view.")
                            accessoryText:NSStringForBackupExportState(OWSBackup.shared.backupExportState)]];
        if (OWSBackup.shared.backupExportState == OWSBackupState_InProgress) {
            if (OWSBackup.shared.backupExportDescription) {
                [progressSection
                    addItem:[OWSTableItem
                                labelItemWithText:NSLocalizedString(@"SETTINGS_BACKUP_PHASE",
                                                      @"Label for phase row in the in the backup settings view.")
                                    accessoryText:OWSBackup.shared.backupExportDescription]];
                if (OWSBackup.shared.backupExportProgress) {
                    NSUInteger progressPercent
                        = (NSUInteger)round(OWSBackup.shared.backupExportProgress.floatValue * 100);
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

        switch (OWSBackup.shared.backupExportState) {
            case OWSBackupState_Idle:
            case OWSBackupState_Failed:
            case OWSBackupState_Succeeded:
                [progressSection
                    addItem:[OWSTableItem disclosureItemWithText:
                                              NSLocalizedString(@"SETTINGS_BACKUP_BACKUP_NOW",
                                                  @"Label for 'backup now' button in the backup settings view.")
                                                     actionBlock:^{ [OWSBackup.shared tryToExportBackup]; }]];
                break;
            case OWSBackupState_InProgress:
                [progressSection
                    addItem:[OWSTableItem disclosureItemWithText:
                                              NSLocalizedString(@"SETTINGS_BACKUP_CANCEL_BACKUP",
                                                  @"Label for 'cancel backup' button in the backup settings view.")
                                                     actionBlock:^{ [OWSBackup.shared cancelExportBackup]; }]];
                break;
        }

        [contents addSection:progressSection];
    }

    self.contents = contents;
}

- (void)isBackupEnabledDidChange:(UISwitch *)sender
{
    [OWSBackup.shared setIsBackupEnabled:sender.isOn];

    [self updateTableContents];
}

#pragma mark - Events

- (void)backupStateDidChange:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    [self updateTableContents];
}

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    [self updateICloudStatus];
}

@end

NS_ASSUME_NONNULL_END
